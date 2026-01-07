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


class LiquidationPlanChecklistDTO(BaseModel):
    schemaVersion: int = 1
    createdAt: datetime = Field(default_factory=_utcnow)
    items: List[LiquidationChecklistItemDTO] = Field(default_factory=list)


class LiquidationPlanRequest(BaseModel):
    schemaVersion: int = 1
    scope: str  # item | set
    chosenPath: str  # pathA_maximizePrice | pathB_delegateConsign | pathC_quickExit | donate | needsInfo

    # Send the brief back (this keeps parity and makes plan generation better).
    brief: LiquidationBriefDTO

    # Optional extra grounding (nice-to-have; iOS can omit)
    title: Optional[str] = None
    category: Optional[str] = None
