# app/services/partner_discovery/factory.py
from __future__ import annotations

import os
from functools import lru_cache

from app.services.partner_discovery.providers import (
    GooglePlacesNewProvider,
    PartnerDiscoveryProvider,
    StubPartnerDiscoveryProvider,
)


@lru_cache(maxsize=1)
def get_partner_discovery_provider(stub_fn=None) -> PartnerDiscoveryProvider:
    """
    Explicit provider selection.
    Env:
      - PARTNER_DISCOVERY_PROVIDER: "stub" | "google"
      - GOOGLE_PLACES_API_KEY: required if provider == "google"
    """
    provider = (os.getenv("PARTNER_DISCOVERY_PROVIDER") or "stub").strip().lower()

    if provider == "stub":
        if stub_fn is None:
            raise ValueError("Stub provider selected but stub_fn was not provided.")
        return StubPartnerDiscoveryProvider(stub_fn=stub_fn)

    if provider == "google":
        api_key = (os.getenv("GOOGLE_PLACES_API_KEY") or "").strip()
        if not api_key:
            raise ValueError("PARTNER_DISCOVERY_PROVIDER=google requires GOOGLE_PLACES_API_KEY to be set.")
        return GooglePlacesNewProvider(api_key=api_key)

    raise ValueError(f"Unknown PARTNER_DISCOVERY_PROVIDER='{provider}'. Expected 'stub' or 'google'.")
