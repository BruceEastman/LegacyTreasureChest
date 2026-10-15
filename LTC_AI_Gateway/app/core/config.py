from __future__ import annotations

import os


def _env_flag(name: str, default: str = "false") -> bool:
    return os.getenv(name, default).strip().lower() in {"1", "true", "yes", "on"}


# Kill switches
DISABLE_ALL_AI = _env_flag("LTC_DISABLE_ALL_AI", "false")
DISABLE_GEMINI = _env_flag("LTC_DISABLE_GEMINI", "false")
DISABLE_PLACES = _env_flag("LTC_DISABLE_PLACES", "false")

# Rate limits (overrideable in Cloud Run)
AI_PER_MINUTE_LIMIT = int(os.getenv("LTC_AI_PER_MINUTE_LIMIT", "60"))
AI_PER_DAY_LIMIT = int(os.getenv("LTC_AI_PER_DAY_LIMIT", "200"))
ANALYZE_PER_MINUTE_LIMIT = int(os.getenv("LTC_ANALYZE_PER_MINUTE_LIMIT", "10"))
PLACES_PER_DAY_LIMIT = int(os.getenv("LTC_PLACES_PER_DAY_LIMIT", "30"))

# Places cost controls for Local Help.
# PLACES_PER_DAY_LIMIT counts Text Search calls per instance (all devices).
# PLACES_SEARCHES_PER_DEVICE_DAY_LIMIT counts Local Help searches per device.
PLACES_SEARCHES_PER_DEVICE_DAY_LIMIT = int(os.getenv("LTC_PLACES_SEARCHES_PER_DEVICE_DAY_LIMIT", "20"))
PLACES_MAX_QUERIES_PER_TYPE = int(os.getenv("LTC_PLACES_MAX_QUERIES_PER_TYPE", "2"))