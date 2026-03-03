from __future__ import annotations

import time
from collections import defaultdict
from typing import Dict, Tuple


class InMemoryRateLimiter:
    """
    In-memory rate limiter.
    NOTE:
    - Per-process only.
    - Resets on deploy/restart.
    - Not shared across Cloud Run instances.
    Acceptable for v1 / TestFlight.
    """

    def __init__(self) -> None:
        # key -> (count, reset_timestamp)
        self._store: Dict[Tuple[str, str], Tuple[int, float]] = {}

        # Daily counters
        self._daily: Dict[Tuple[str, str], Tuple[int, float]] = {}

    def _now(self) -> float:
        return time.time()

    def check(
        self,
        *,
        device_id: str,
        scope: str,
        limit: int,
        window_seconds: int,
    ) -> Tuple[bool, int]:
        """
        Returns (allowed, retry_after_seconds)
        """
        now = self._now()
        key = (device_id, scope)

        count, reset_ts = self._store.get(key, (0, now + window_seconds))

        if now > reset_ts:
            count = 0
            reset_ts = now + window_seconds

        if count >= limit:
            retry_after = int(reset_ts - now)
            return False, max(retry_after, 1)

        self._store[key] = (count + 1, reset_ts)
        return True, 0

    def check_daily(
        self,
        *,
        device_id: str,
        scope: str,
        limit: int,
    ) -> Tuple[bool, int]:
        """
        Daily (UTC-based 24h rolling window).
        """
        now = self._now()
        window_seconds = 86400
        key = (device_id, scope)

        count, reset_ts = self._daily.get(key, (0, now + window_seconds))

        if now > reset_ts:
            count = 0
            reset_ts = now + window_seconds

        if count >= limit:
            retry_after = int(reset_ts - now)
            return False, max(retry_after, 1)

        self._daily[key] = (count + 1, reset_ts)
        return True, 0


rate_limiter = InMemoryRateLimiter()