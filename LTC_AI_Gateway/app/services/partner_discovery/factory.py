# app/services/partner_discovery/factory.py
from __future__ import annotations

import os

from app.services.partner_discovery.providers import (
    GooglePlacesNewProvider,
    PartnerDiscoveryProvider,
    StubPartnerDiscoveryProvider,
)


class PartnerDiscoveryConfigError(Exception):
    """The deployment has no usable partner-discovery provider configured."""


def running_on_cloud_run() -> bool:
    # Cloud Run always sets K_SERVICE for the container.
    return bool((os.getenv("K_SERVICE") or "").strip())


def get_partner_discovery_provider(stub_fn=None) -> PartnerDiscoveryProvider:
    """
    Explicit provider selection.
    Env:
      - PARTNER_DISCOVERY_PROVIDER: "google" | "stub"
        Unset means "google". The stub is never chosen implicitly.
      - GOOGLE_PLACES_API_KEY: required for "google"

    The stub returns fictitious businesses, so it is refused on Cloud Run
    regardless of configuration.
    """
    provider = (os.getenv("PARTNER_DISCOVERY_PROVIDER") or "google").strip().lower()

    if provider == "stub":
        if running_on_cloud_run():
            raise PartnerDiscoveryConfigError("Stub partner discovery is not allowed on Cloud Run.")
        if stub_fn is None:
            raise PartnerDiscoveryConfigError("Stub provider selected but stub_fn was not provided.")
        return StubPartnerDiscoveryProvider(stub_fn=stub_fn)

    if provider == "google":
        api_key = (os.getenv("GOOGLE_PLACES_API_KEY") or "").strip()
        if not api_key:
            raise PartnerDiscoveryConfigError("PARTNER_DISCOVERY_PROVIDER=google requires GOOGLE_PLACES_API_KEY.")
        return GooglePlacesNewProvider(api_key=api_key)

    raise PartnerDiscoveryConfigError(f"Unknown PARTNER_DISCOVERY_PROVIDER='{provider}'. Expected 'google' or 'stub'.")
