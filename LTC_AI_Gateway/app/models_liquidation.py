from __future__ import annotations

from datetime import datetime, timezone
from typing import List, Optional

from pydantic import BaseModel, Field


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# -----------------------------
# Request models (from iOS)
# -----------------------------

class MoneyRangeDTO(BaseModel):
    currencyCode: str = "USD"
    low: Optional[float] = None
    likely: Optional[float] = None
    high: Optional[float] = None


class LiquidationConstraintsDTO(BaseModel):
    localPickupOnly: Optional[bool] = None
    canShip: Optional[bool] = None
    deadline: Optional[datetime] = None
    notes: Optional[str] = None


class LiquidationInputsDTO(BaseModel):
    goal: Optional[str] = None  # maximizeValue | minimizeEffort | balanced | fastestExit
    constraints: Optional[LiquidationConstraintsDTO] = None
    locationHint: Optional[str] = None


class LiquidationMemberSummary(BaseModel):
    title: Optional[str] = None
    category: Optional[str] = None
    quantity: Optional[int] = None
    unitValue: Optional[float] = None


class LiquidationSetContext(BaseModel):
    setName: Optional[str] = None
    setType: Optional[str] = None
    story: Optional[str] = None
    sellTogetherPreference: Optional[str] = None
    completeness: Optional[str] = None
    memberSummaries: List[LiquidationMemberSummary] = Field(default_factory=list)


class LiquidationBriefRequest(BaseModel):
    schemaVersion: int = 1
    scope: str  # item | set

    title: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    quantity: Optional[int] = None
    unitValue: Optional[float] = None
    currencyCode: Optional[str] = "USD"

    valuationLow: Optional[float] = None
    valuationLikely: Optional[float] = None
    valuationHigh: Optional[float] = None

    photoJpegBase64: Optional[str] = None

    setContext: Optional[LiquidationSetContext] = None
    inputs: Optional[LiquidationInputsDTO] = None


# -----------------------------
# Response models (to iOS)
# -----------------------------

class LiquidationPathOptionDTO(BaseModel):
    id: str  # UUID string
    path: str  # pathA_maximizePrice | pathB_delegateConsign | pathC_quickExit | donate | needsInfo

    label: str
    netProceeds: Optional[MoneyRangeDTO] = None

    effort: str  # low | medium | high | veryHigh
    timeEstimate: Optional[str] = None

    risks: List[str] = Field(default_factory=list)
    logisticsNotes: Optional[str] = None


class LiquidationSpecialtyDTO(BaseModel):
    """
    Optional description of what kind of item this is, for later specialist
    searches. Metadata only: derived from the request's own item text, never
    a business name. Every field is optional so older Briefs stay valid.
    """
    itemKind: Optional[str] = None  # short generic noun phrase, e.g. "film camera"
    detailTerms: List[str] = Field(default_factory=list)  # up to 4 identifying terms
    brand: Optional[str] = None  # only when stated in the item text
    model: Optional[str] = None  # only when stated in the item text
    isSpecialistItem: bool = False


class LiquidationBriefDTO(BaseModel):
    schemaVersion: int = 1
    scope: str  # item | set

    generatedAt: datetime
    aiProvider: Optional[str] = None
    aiModel: Optional[str] = None

    recommendedPath: str  # pathA_maximizePrice | pathB_delegateConsign | pathC_quickExit | donate | needsInfo
    reasoning: str

    pathOptions: List[LiquidationPathOptionDTO]
    actionSteps: List[str]

    missingDetails: List[str] = Field(default_factory=list)
    assumptions: List[str] = Field(default_factory=list)
    confidence: Optional[float] = None

    inputs: Optional[LiquidationInputsDTO] = None

    # Optional; absent in Briefs created before it existed.
    specialty: Optional[LiquidationSpecialtyDTO] = None


# -----------------------------
# Plan models
# -----------------------------

class LiquidationChecklistItemDTO(BaseModel):
    # Keep parity with Swift: Swift has an id UUID with a default.
    # If backend omits it, Swift should still decode using its default.
    order: int
    text: str
    isCompleted: bool = False
    completedAt: Optional[datetime] = None
    userNotes: Optional[str] = None

    # Plan v2 (optional): one short "why/how" line, a hook for opening Find Help
    # (findHelp | findSpecialtyHelp), and the closet-lot pile a step belongs to
    # (luxury | contemporary | donate | discard | other).
    detail: Optional[str] = None
    action: Optional[str] = None
    group: Optional[str] = None


class LiquidationPlanChecklistDTO(BaseModel):
    schemaVersion: int = 1
    createdAt: datetime = Field(default_factory=_utcnow)
    items: List[LiquidationChecklistItemDTO] = Field(default_factory=list)

    # Plan v2 (optional)
    focus: Optional[str] = None  # one sentence: the strategy in plain words
    aiProvider: Optional[str] = None
    aiModel: Optional[str] = None


class LiquidationPlanItemContext(BaseModel):
    """
    Plan v2: what LTC already knows about a single item. Metadata only: counts
    and document types, never photos, files, or audio.
    """
    description: Optional[str] = None
    quantity: Optional[int] = None
    unitValue: Optional[float] = None
    currencyCode: Optional[str] = None
    valuationLow: Optional[float] = None
    valuationHigh: Optional[float] = None
    valuationNotes: Optional[str] = None
    photoCount: Optional[int] = None
    documentCount: Optional[int] = None
    documentTypes: List[str] = Field(default_factory=list)
    hasAudioStory: Optional[bool] = None


class LiquidationPlanRequest(BaseModel):
    schemaVersion: int = 1
    scope: str  # item | set
    chosenPath: str  # pathA_maximizePrice | pathB_delegateConsign | pathC_quickExit | donate | needsInfo

    # Send the brief back (this keeps parity and makes plan generation better).
    brief: LiquidationBriefDTO

    # Optional extra grounding (nice-to-have; iOS can omit)
    title: Optional[str] = None
    category: Optional[str] = None

    # Plan v2 (optional; app 1.2 omits all of these)
    selectedOption: Optional[LiquidationPathOptionDTO] = None  # the Brief option the owner chose
    isRecommended: Optional[bool] = None  # whether that option was the Brief's recommendation
    itemContext: Optional[LiquidationPlanItemContext] = None
    setContext: Optional[LiquidationSetContext] = None
