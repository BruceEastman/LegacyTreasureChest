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
# Saved-provider refreshes (Place Details Pro) per device per day.
PLACES_DETAILS_PER_DEVICE_DAY_LIMIT = int(os.getenv("LTC_PLACES_DETAILS_PER_DEVICE_DAY_LIMIT", "40"))
# Largest /ai/analyze-item-photo request body accepted (bytes). Images travel
# inline as base64. Matches Cloud Run's own 32 MiB request limit, so no request
# LTC 1.2 could send successfully today is newly refused; it gives a clear 413
# before the body is parsed.
MAX_ANALYZE_REQUEST_BYTES = int(os.getenv("LTC_MAX_ANALYZE_REQUEST_BYTES", str(32 * 1024 * 1024)))
