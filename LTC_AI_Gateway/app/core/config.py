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