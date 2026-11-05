from __future__ import annotations

from typing import Dict, List, Optional

from pydantic import BaseModel


# ---- Hints sent with the image ----

class ItemAIHints(BaseModel):
    """Optional hints sent from the iOS app to guide analysis.

    These come from user-entered text or prior knowledge:
    - userWrittenTitle / userWrittenDescription: anything the user already knows.
    - knownCategory: category the user has chosen (e.g. "Jewelry").
    """
    userWrittenTitle: Optional[str] = None
    userWrittenDescription: Optional[str] = None
    knownCategory: Optional[str] = None


# ---- Value hints (used to build ItemValuation on iOS) ----

class ValueHints(BaseModel):
    """Structured valuation hints returned by the AI backend.

    This shape is intentionally generic so it can be reused for Jewelry, Rugs,
    Art, Furniture, etc. iOS will map this into the SwiftData `ItemValuation`
    model on each LTCItem.
    """

    # Core numeric valuation
    valueLow: Optional[float] = None
    estimatedValue: Optional[float] = None
    valueHigh: Optional[float] = None
    currencyCode: str = "USD"

    # AI meta
    confidenceScore: Optional[float] = None  # 0.0–1.0, overall confidence
    valuationDate: Optional[str] = None      # ISO-8601 string stamped by backend
    aiProvider: Optional[str] = None         # e.g. "gemini-2.0-flash"

    # Explainability & guidance
    aiNotes: Optional[str] = None            # Why this range?
    missingDetails: Optional[List[str]] = None  # What info would improve accuracy?


# ---- Canonical item categories ----
# Must mirror LTCItem.baseCategories in the iOS app (Data/SwiftData/LTCModels.swift).
# Shared by the prompt builders (closed-list instruction to Gemini) and the
# response normalizer (collapses any invented value to "Other").
CANONICAL_ITEM_CATEGORIES: List[str] = [
    "Uncategorized",
    "Art",
    "Furniture",
    "Jewelry",
    "Collectibles",
    "Documents",
    "Electronics",
    "Appliance",
    "Rug",
    "China & Crystal",
    "Luxury Personal Items",
    "Clothing",
    "Tools",
    "Luggage",
    "Decor",
    "Other",
]


# ---- Item analysis (top-level response from Gemini) ----

class ItemAnalysis(BaseModel):
    """High-level item analysis returned to the iOS app.

    This mirrors the Swift `ItemAnalysis` struct in AIModels.swift.
    """

    # Core identity & description
    title: str
    description: str
    category: str

    # Optional classification metadata
    tags: Optional[List[str]] = None
    confidence: Optional[float] = None  # confidence in category/classification

    # Valuation hints used by the app to build ItemValuation
    valueHints: Optional[ValueHints] = None

    # Additional attributes (category-specific but kept generic in shape)
    brand: Optional[str] = None
    materials: Optional[List[str]] = None
    style: Optional[str] = None
    origin: Optional[str] = None
    condition: Optional[str] = None
    dimensions: Optional[str] = None
    eraOrYear: Optional[str] = None
    features: Optional[List[str]] = None

    # ---- 1.3 additions (all optional; older apps ignore unknown keys) ----
    # Manufacturer model / reference / pattern number, when identified.
    modelNumber: Optional[str] = None
    # What ONE catalog unit is, e.g. "one stool" or "complete 10-place-setting
    # service". Every value in valueHints is for this unit.
    valuationUnit: Optional[str] = None
    # Short notes where the evidence contradicts the owner's notes or earlier
    # AI-identified details.
    conflicts: Optional[List[str]] = None
    # Filled by the gateway (never by Gemini) for requests that use the 1.3
    # context/evidence fields, so the app can confirm what was analyzed.
    inputSummary: Optional["ItemAnalysisInputSummary"] = None


# ---- 1.3: processing metadata returned to the app ----

class ItemAnalysisInputSummary(BaseModel):
    """Counts only. Never contains evidence content, labels, or item text."""
    contractVersion: int = 2
    primaryPhoto: bool = False
    supplementaryPhotos: int = 0
    documents: int = 0
    documentPages: int = 0
    quantity: Optional[int] = None
    ownerNotes: bool = False
    savedDescriptionParts: int = 0
    priorAttributes: int = 0


# ---- 1.3: optional analysis context and supplementary evidence ----

class SavedDescriptionPart(BaseModel):
    """Part of the item's saved description, labeled by where it came from.

    origin: "owner" (written by the owner), "priorAI" (an earlier AI
    suggestion the owner accepted; not verified), or "mixed" (edited after an
    AI suggestion; which parts are whose is unknown).
    """
    origin: str
    text: str


class ItemAnalysisContext(BaseModel):
    """Optional context sent by LTC 1.3. Its presence selects the 1.3 prompt."""
    # How many identical units this catalog entry represents (the app's
    # quantity). Values are always requested for ONE unit.
    quantity: Optional[int] = None
    # The owner's separately stored notes (More Details).
    ownerNotes: Optional[str] = None
    savedDescription: Optional[List[SavedDescriptionPart]] = None
    # Attributes from the earlier AI details line (not verified), keyed by
    # the ItemAnalysis field name (brand, materials, eraOrYear, ...).
    priorAttributes: Optional[Dict[str, str]] = None


class SupplementaryEvidence(BaseModel):
    """One supplementary image selected by the owner.

    kind: "photo" (an additional item photo) or "documentPage" (one page of a
    selected document, rendered to JPEG on the device). Pages carry their
    document index and page number so order and source are preserved.
    """
    kind: str
    mimeType: str
    dataBase64: str
    documentIndex: Optional[int] = None
    page: Optional[int] = None
    pageCount: Optional[int] = None


# ---- Request from iOS for photo analysis ----

class AnalyzeItemPhotoRequest(BaseModel):
    # Required by LTC 1.2 and earlier, which always send it. LTC 1.3 may omit
    # it when the item has no photo but the owner selected evidence.
    imageJpegBase64: Optional[str] = None
    hints: Optional[ItemAIHints] = None
    context: Optional[ItemAnalysisContext] = None
    supplementary: Optional[List[SupplementaryEvidence]] = None

    @property
    def uses_v2(self) -> bool:
        """True when the 1.3 context/evidence fields are present."""
        return self.context is not None or bool(self.supplementary)


ItemAnalysis.model_rebuild()
