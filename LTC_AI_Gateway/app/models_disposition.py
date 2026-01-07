from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


# -----------------------------
# Common DTOs
# -----------------------------

class DispositionLocationDTO(BaseModel):
    city: str
    region: str
    countryCode: str = "US"
    postalCode: Optional[str] = None
    radiusMiles: Optional[int] = None

    # Optional coordinates for accurate distance computation & better ranking.
    # Backwards compatible: iOS can omit these in v1.
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class MoneyRangeDTO(BaseModel):
    currencyCode: str = "USD"
    low: Optional[float] = None
    likely: Optional[float] = None
    high: Optional[float] = None


# -----------------------------
# Partner discovery
# -----------------------------

class DispositionScenarioDTO(BaseModel):
    category: Optional[str] = None
    valueBand: Optional[str] = None  # LOW|MED|HIGH|UNKNOWN
    bulky: Optional[bool] = None
    fragile: Optional[bool] = None
    setMembership: Optional[str] = None  # NONE|POSSIBLE|CONFIRMED
    goal: Optional[str] = None  # maximize_value|balanced|min_effort
    constraints: List[str] = Field(default_factory=list)

    # Optional matching enrichers (v1-safe)
    brandHints: List[str] = Field(default_factory=list)
    conditionHint: Optional[str] = None  # excellent|good|fair|poor|unknown
    quantityHint: Optional[str] = None  # single|multi|set|unknown


class DispositionHintsDTO(BaseModel):
    keywords: List[str] = Field(default_factory=list)
    notes: Optional[str] = None


class DispositionPartnersSearchRequest(BaseModel):
    schemaVersion: int = 1
    scope: str = "item"  # item|set (set not used in v1)
    itemId: Optional[str] = None
    planId: Optional[str] = None
    chosenPath: str  # A|B|C|DONATE (iOS can map from liquidation paths)
    scenario: DispositionScenarioDTO
    location: DispositionLocationDTO
    hints: Optional[DispositionHintsDTO] = None


class DispositionPartnerContactDTO(BaseModel):
    phone: Optional[str] = None
    website: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    region: Optional[str] = None


class DispositionTrustGateResultDTO(BaseModel):
    id: str
    mode: str  # required|boost
    status: str  # pass|fail|unknown
    source: Optional[str] = None
    strength: float = 0.0


class DispositionTrustDTO(BaseModel):
    trustScore: float
    claimLevel: str = "claimed"
    gates: List[DispositionTrustGateResultDTO] = Field(default_factory=list)
    signals: List[dict] = Field(default_factory=list)


class DispositionRankingDTO(BaseModel):
    score: float
    reasons: List[str] = Field(default_factory=list)


class DispositionPartnerResultDTO(BaseModel):
    partnerId: str
    name: str
    partnerType: str  # consignment|estate_sale|auction|donation|junk_haul
    contact: DispositionPartnerContactDTO
    distanceMiles: Optional[float] = None

    # NEW: high-signal “everyone understands it” fields from Google Places
    rating: Optional[float] = None
    userRatingsTotal: Optional[int] = None

    trust: DispositionTrustDTO
    ranking: DispositionRankingDTO

    whyRecommended: str
    questionsToAsk: List[str] = Field(default_factory=list)


class DispositionPartnersSearchResponse(BaseModel):
    schemaVersion: int = 1
    generatedAt: datetime
    scenarioId: str
    partnerTypes: List[str] = Field(default_factory=list)
    results: List[DispositionPartnerResultDTO] = Field(default_factory=list)
    disclaimer: str
    recommendedRefreshDays: int = 30


# -----------------------------
# Outreach composition
# -----------------------------

class DispositionOutreachPartnerDTO(BaseModel):
    partnerId: str
    name: str
    partnerType: str
    contact: DispositionPartnerContactDTO


class DispositionPacketScopeDTO(BaseModel):
    kind: str = "single_item"  # single_item (v1)
    includePhotos: bool = True
    includeInventoryPdf: bool = True
    includePlanSummary: bool = False


class DispositionItemSummaryDTO(BaseModel):
    title: str
    description: Optional[str] = None
    category: Optional[str] = None
    quantity: Optional[int] = None
    valueEstimate: Optional[MoneyRangeDTO] = None


class DispositionOutreachComposeRequest(BaseModel):
    schemaVersion: int = 1
    scope: str = "item"
    itemId: str
    planId: Optional[str] = None

    partner: DispositionOutreachPartnerDTO
    packetScope: Optional[DispositionPacketScopeDTO] = None
    itemSummary: DispositionItemSummaryDTO
    location: DispositionLocationDTO


class DispositionAttachmentDTO(BaseModel):
    kind: str
    label: str
    required: bool = False


class DispositionOutreachComposeResponse(BaseModel):
    schemaVersion: int = 1
    generatedAt: datetime
    preferredContactMethod: str  # email|website_form|phone
    subject: str
    emailBody: str
    attachments: List[DispositionAttachmentDTO] = Field(default_factory=list)
    followUps: List[str] = Field(default_factory=list)
    instructions: Optional[str] = None
