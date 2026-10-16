from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

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


class DispositionSearchIntentDTO(BaseModel):
    """
    B1: a homeowner-reviewed specialty search. When present, the Gateway uses
    intent-based discovery instead of the legacy scenario matrix. Validated
    again server-side (see partner_discovery/intent.py); only these fields are
    used, never item names, notes, or identifiers.
    """
    schemaVersion: int = 1
    strategy: str  # maximizePrice | consignment | quickSale | donation
    phrase: str  # short, item-specific wording the homeowner reviewed
    detailTerms: List[str] = Field(default_factory=list)  # optional identifying terms (ranking only)
    geoScope: str = "local"  # local | regional | national
    valueBand: Optional[str] = None  # LOW|MED|HIGH, only when the homeowner opts in


class DispositionPartnersSearchRequest(BaseModel):
    schemaVersion: int = 1
    scope: str = "item"  # item|set (set not used in v1)
    itemId: Optional[str] = None
    planId: Optional[str] = None
    chosenPath: Optional[str] = None  # A|B|C|donate|needsInfo (iOS maps from liquidation paths)
    scenario: DispositionScenarioDTO
    location: DispositionLocationDTO
    hints: Optional[DispositionHintsDTO] = None
    # B1 (optional): app 1.2 never sends it, and its absence keeps legacy behavior.
    searchIntent: Optional[DispositionSearchIntentDTO] = None


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

    # B1 (optional; set only on intent-based results)
    source: Optional[str] = None  # google_places | ltc_directory
    placeId: Optional[str] = None  # Google place ID (storable)
    directoryId: Optional[str] = None
    googleMapsUri: Optional[str] = None  # the Google Maps listing, distinct from the business website
    # What the business's own Google name/type text says, never inferred acceptance:
    # {"consignment"|"buysOutright"|"auction"|"donations"|"marketplace": "mentioned"|"not_mentioned"|"offered"}
    serviceEvidence: Optional[Dict[str, str]] = None
    evidenceSource: Optional[str] = None  # google_places_name_and_type | ltc_directory_review
    relevance: Optional[Dict[str, Any]] = None  # {"level": "specialist"|"general", "matchedTerms": [...]}
    geoScope: Optional[str] = None  # local | regional | national
    areaMatch: Optional[str] = None  # in_area | outside_area | unknown
    serviceArea: Optional[str] = None  # directory entries, e.g. "Nationwide (mail-in), US"
    intakeModel: Optional[str] = None  # directory entries: mail_in | in_person | mail_in_or_in_person | online_listing
    verifiedAt: Optional[str] = None  # directory entries: date the entry was last checked
    acceptanceStatus: Optional[str] = None  # always "unknown": acceptance is confirmed only by the business
    attribution: Optional[str] = None  # "google_maps" when the data comes from Google Places


class DispositionPartnersSearchResponse(BaseModel):
    schemaVersion: int = 1
    generatedAt: datetime
    scenarioId: str
    partnerTypes: List[str] = Field(default_factory=list)
    results: List[DispositionPartnerResultDTO] = Field(default_factory=list)
    disclaimer: str
    recommendedRefreshDays: int = 30

    # Local (Google Places) discovery outcome, so the app can say why there are
    # no local results instead of implying a search found nothing.
    # ok | no_results | unavailable | disabled | limited | not_applicable
    localDiscoveryStatus: str = "ok"
    notice: Optional[str] = None

    # B1 (optional; intent searches only)
    searchScope: Optional[str] = None  # local | regional | national
    directoryStatus: Optional[str] = None  # ok | no_match | not_applicable


# -----------------------------
# Saved-provider details (B2)
# -----------------------------

class PlaceDetailsRequest(BaseModel):
    """Refresh up to five saved Google place IDs (the only Places data the app stores)."""
    placeIds: List[str] = Field(default_factory=list)


class PlaceDetailsDTO(BaseModel):
    placeId: str
    status: str  # ok | not_found | closed | unavailable
    name: Optional[str] = None
    address: Optional[str] = None
    googleMapsUri: Optional[str] = None


class PlaceDetailsResponse(BaseModel):
    generatedAt: datetime
    places: List[PlaceDetailsDTO] = Field(default_factory=list)
    status: str = "ok"  # ok | unavailable | disabled | limited
    attribution: str = "google_maps"


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
