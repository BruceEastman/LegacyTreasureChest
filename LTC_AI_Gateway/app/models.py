from __future__ import annotations

from typing import List, Optional

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


# ---- Request from iOS for photo analysis ----

class AnalyzeItemPhotoRequest(BaseModel):
    imageJpegBase64: str
    hints: Optional[ItemAIHints] = None
