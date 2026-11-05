# app/ai/evidence.py
"""Validation and labeling of LTC 1.3 supplementary evidence for item analysis.

Evidence arrives inline in one request, is checked here in memory, is sent
inline to Gemini, and is never written to disk, logged, or uploaded to Gemini's
Files API. Errors carry a code, a fixed message and an index only: never any
evidence content, label text or item text.
"""

from __future__ import annotations

import base64
import binascii
import os
from dataclasses import dataclass, field
from typing import List, Optional, Sequence, Tuple

from app.ai.prompts.item_analysis import DOCUMENT_PAGE_LABEL, SUPPLEMENTARY_PHOTO_LABEL


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


# Approved 1.3 limits (overrideable for testing via environment).
MAX_SUPPLEMENTARY_PHOTOS = _env_int("LTC_EVIDENCE_MAX_PHOTOS", 3)
MAX_DOCUMENTS = _env_int("LTC_EVIDENCE_MAX_DOCUMENTS", 1)
MAX_DOCUMENT_PAGES = _env_int("LTC_EVIDENCE_MAX_PAGES", 10)
# Decoded bytes per supplementary image, and for the primary photo when the
# request carries evidence. The app targets well below these.
MAX_EVIDENCE_IMAGE_BYTES = _env_int("LTC_EVIDENCE_MAX_IMAGE_BYTES", 3 * 1024 * 1024)
# Decoded bytes for primary + all evidence. Base64 adds a third, so this keeps
# the Gemini request under its inline-data request limit.
MAX_EVIDENCE_TOTAL_BYTES = _env_int("LTC_EVIDENCE_MAX_TOTAL_BYTES", 12 * 1024 * 1024)

ALLOWED_MIME_TYPES = {"image/jpeg"}
_JPEG_SIGNATURE = b"\xff\xd8\xff"

KIND_PHOTO = "photo"
KIND_DOCUMENT_PAGE = "documentPage"


class EvidenceError(Exception):
    """A request the gateway refuses. Safe to return to the client."""

    def __init__(self, code: str, message: str, *, status: int = 400, index: Optional[int] = None):
        super().__init__(code)
        self.code = code
        self.message = message
        self.status = status
        self.index = index

    def details(self) -> dict:
        return {"evidenceIndex": self.index} if self.index is not None else {}


@dataclass
class ValidatedEvidence:
    """Evidence ready for Gemini: (label, base64) pairs in the owner's order."""
    labeled: List[Tuple[str, str]] = field(default_factory=list)
    primary_photo: bool = False
    supplementary_photos: int = 0
    documents: int = 0
    document_pages: int = 0
    total_bytes: int = 0
    # (document number, pages provided, pages in the document) when fewer pages
    # than the document has were provided.
    truncations: List[Tuple[int, int, int]] = field(default_factory=list)


def _decode_jpeg(data_b64: Optional[str], *, index: Optional[int], max_bytes: int) -> int:
    """Validate base64 + JPEG signature + size; return the decoded size."""
    if not isinstance(data_b64, str) or not data_b64:
        raise EvidenceError("EVIDENCE_MISSING_DATA", "An evidence image has no data.", index=index)
    try:
        raw = base64.b64decode(data_b64, validate=True)
    except (binascii.Error, ValueError):
        raise EvidenceError("EVIDENCE_INVALID_BASE64", "An evidence image is not valid base64.", index=index)
    if len(raw) > max_bytes:
        raise EvidenceError("EVIDENCE_TOO_LARGE", "An evidence image is too large.", status=413, index=index)
    if not raw.startswith(_JPEG_SIGNATURE):
        raise EvidenceError("EVIDENCE_INVALID_IMAGE", "An evidence image is not a JPEG.", index=index)
    return len(raw)


def validate_evidence(primary_b64: Optional[str], supplementary: Optional[Sequence]) -> ValidatedEvidence:
    """Validate the primary photo (when evidence is present) and each item.

    `supplementary` holds SupplementaryEvidence models. Photos and document
    pages keep the order they were sent in; pages of a document must be
    consecutive, start at 1, and not exceed the page limit.
    """
    items = list(supplementary or [])
    result = ValidatedEvidence()

    if primary_b64:
        result.total_bytes += _decode_jpeg(primary_b64, index=None, max_bytes=MAX_EVIDENCE_IMAGE_BYTES * 2)
        result.primary_photo = True

    if not items and not result.primary_photo:
        raise EvidenceError("NO_INPUT", "Send a primary photo or at least one evidence image.")

    photo_n = 0
    pages_by_doc: dict[int, List[int]] = {}
    page_counts: dict[int, int] = {}
    doc_order: List[int] = []

    for index, item in enumerate(items):
        kind = getattr(item, "kind", None)
        if kind not in (KIND_PHOTO, KIND_DOCUMENT_PAGE):
            raise EvidenceError("EVIDENCE_UNSUPPORTED_KIND", "Unsupported evidence kind.", index=index)
        if getattr(item, "mimeType", None) not in ALLOWED_MIME_TYPES:
            raise EvidenceError("EVIDENCE_UNSUPPORTED_TYPE", "Evidence images must be JPEG.", index=index)

        if kind == KIND_PHOTO:
            photo_n += 1
            if photo_n > MAX_SUPPLEMENTARY_PHOTOS:
                raise EvidenceError("EVIDENCE_TOO_MANY_PHOTOS",
                                    f"At most {MAX_SUPPLEMENTARY_PHOTOS} additional photos can be analyzed.",
                                    index=index)
            label = SUPPLEMENTARY_PHOTO_LABEL.format(n=photo_n)
        else:
            doc, page, pages = item.documentIndex, item.page, item.pageCount
            if not all(isinstance(v, int) for v in (doc, page, pages)) or doc < 1 or page < 1 or pages < 1:
                raise EvidenceError("EVIDENCE_INVALID_PAGE", "A document page is missing its page details.",
                                    index=index)
            if page > pages:
                raise EvidenceError("EVIDENCE_INVALID_PAGE", "A page number exceeds the document's page count.",
                                    index=index)
            if doc not in pages_by_doc:
                if len(doc_order) >= MAX_DOCUMENTS:
                    raise EvidenceError("EVIDENCE_TOO_MANY_DOCUMENTS",
                                        f"At most {MAX_DOCUMENTS} document can be analyzed.", index=index)
                doc_order.append(doc)
                pages_by_doc[doc] = []
                page_counts[doc] = pages
            if page_counts[doc] != pages:
                raise EvidenceError("EVIDENCE_INVALID_PAGE", "A document's page count is inconsistent.",
                                    index=index)
            expected = len(pages_by_doc[doc]) + 1
            if page != expected:
                raise EvidenceError("EVIDENCE_PAGE_ORDER", "Document pages must be sent in order starting at 1.",
                                    index=index)
            if expected > MAX_DOCUMENT_PAGES:
                raise EvidenceError("EVIDENCE_TOO_MANY_PAGES",
                                    f"At most {MAX_DOCUMENT_PAGES} document pages can be analyzed.", index=index)
            pages_by_doc[doc].append(page)
            label = DOCUMENT_PAGE_LABEL.format(doc=doc_order.index(doc) + 1, page=page, pages=pages)

        result.total_bytes += _decode_jpeg(item.dataBase64, index=index, max_bytes=MAX_EVIDENCE_IMAGE_BYTES)
        if result.total_bytes > MAX_EVIDENCE_TOTAL_BYTES:
            raise EvidenceError("EVIDENCE_TOTAL_TOO_LARGE", "The selected evidence is too large in total.",
                                status=413, index=index)
        result.labeled.append((label, item.dataBase64))

    result.supplementary_photos = photo_n
    result.documents = len(doc_order)
    result.document_pages = sum(len(p) for p in pages_by_doc.values())
    for number, doc in enumerate(doc_order, start=1):
        shown, total = len(pages_by_doc[doc]), page_counts[doc]
        if shown < total:
            result.truncations.append((number, shown, total))
    return result
