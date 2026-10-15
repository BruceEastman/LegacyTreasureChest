//
//  LocalHelpLiveTests.swift
//  LegacyTreasureChestTests
//
//  End-to-end Local Help checks against the PRODUCTION gateway, using the app's
//  real location, geocoding, request-building, and networking code.
//
//  Off by default. They call Google Places through the gateway (billed, capped),
//  so run them deliberately:
//
//    xcrun simctl location <sim> set 39.7392,-104.9903        # Denver
//    xcrun simctl privacy <sim> grant location com.bruceeastman.LegacyTreasureChest
//    TEST_RUNNER_LTC_LIVE_TESTS=1 xcodebuild test ... \
//      -only-testing:LegacyTreasureChestTests/LocalHelpLiveTests
//
//  They never contact a business.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

private let liveTestsEnabled = ProcessInfo.processInfo.environment["LTC_LIVE_TESTS"] == "1"
private let productionGateway = URL(string: "https://ltc-ai-gateway-530541590215.us-west1.run.app")!

@Suite(.enabled(if: liveTestsEnabled, "Set LTC_LIVE_TESTS=1 to call the production gateway"), .serialized)
struct LocalHelpLiveTests {

    private func service() -> DispositionAIService {
        let defaults = UserDefaults(suiteName: "LocalHelpLiveTests")!
        let consent = AICloudConsentManager(defaults: defaults)
        consent.grant()
        return DispositionAIService(backend: BackendAIProvider(baseURL: productionGateway, consent: consent))
    }

    private func item(_ name: String, category: String, value: Double) throws -> (LTCItem, ModelContainer) {
        let container = try ModelContainer(
            for: LTCItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let item = LTCItem(name: name, itemDescription: "Local Help live test", category: category, value: value)
        container.mainContext.insert(item)
        return (item, container)
    }

    private func expectRealLocalBusinesses(_ r: DispositionPartnersSearchResponse, stateCode: String, expectDistances: Bool) {
        #expect(r.localDiscoveryStatus == "ok")
        #expect(!r.results.isEmpty)
        #expect(r.hasGooglePlacesResults)
        for p in r.results {
            #expect(p.partnerId.hasPrefix("gplaces:"), "not a Google Places result: \(p.name)")
            let address = p.contact.address ?? ""
            #expect(address.contains(", \(stateCode) "), "\(p.name) is not in \(stateCode): \(address)")
            let blob = "\(p.name) \(p.contact.phone ?? "") \(p.contact.website ?? "")"
            #expect(!blob.contains("555-01") && !blob.contains("example.com") && !blob.contains("Heritage Consignment"))
            if expectDistances {
                #expect((p.distanceMiles ?? 999) <= 100, "\(p.name) distance \(String(describing: p.distanceMiles))")
            }
        }
    }

    /// Device location (simulated Denver) -> permission -> reverse geocode ->
    /// device coordinates -> production search for a furniture item.
    @Test func deviceLocationFindsRealBusinessesNearTheDevice() async throws {
        let autofill = LTCLocationAutofill()
        autofill.requestOnce()

        var waited = 0
        while autofill.deviceFix == nil && waited < 300 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        let fix = try #require(autofill.deviceFix, "No device fix: \(autofill.statusText ?? "no status")")
        #expect(fix.city == "Denver")
        #expect(fix.region == "CO")

        let coords = await LocalHelpLocationResolver.resolveCoordinates(
            city: fix.city, region: fix.region, countryCode: fix.countryCode, fix: fix)
        #expect(coords == LocalHelpCoordinates(latitude: fix.latitude, longitude: fix.longitude))

        let location = LocalHelpLocationResolver.makeLocationDTO(
            city: fix.city, region: fix.region, countryCode: fix.countryCode, radiusMiles: 25, coordinates: coords)
        let (item, container) = try item("Walnut dining table", category: "Furniture", value: 400)
        _ = container

        let r = try await service().searchPartners(item: item, location: location, radiusMiles: 25)
        #expect(r.scenarioId == "furniture_bulky_med_balanced")
        expectRealLocalBusinesses(r, stateCode: "CO", expectDistances: true)
    }

    /// Manual city that differs from the device fix: the device's Denver
    /// coordinates must not be reused; Boise is geocoded instead.
    @Test func manualCityUsesItsOwnLocationNotTheDevice() async throws {
        let denverFix = LocalHelpDeviceFix(
            city: "Denver", region: "CO", countryCode: "US", latitude: 39.7392, longitude: -104.9903)
        let coords = try #require(await LocalHelpLocationResolver.resolveCoordinates(
            city: "Boise", region: "ID", countryCode: "US", fix: denverFix))
        #expect(abs(coords.latitude - 43.6) < 0.3)

        let location = LocalHelpLocationResolver.makeLocationDTO(
            city: "Boise", region: "ID", countryCode: "US", radiusMiles: 25, coordinates: coords)
        let (item, container) = try item("Persian rug", category: "Rug", value: 800)
        _ = container

        let r = try await service().searchPartners(item: item, location: location, radiusMiles: 25)
        #expect(r.scenarioId == "rug_any")
        expectRealLocalBusinesses(r, stateCode: "ID", expectDistances: true)
    }

    /// With location revoked (`xcrun simctl privacy <sim> revoke location ...`
    /// and LTC_EXPECT_LOCATION_DENIED=1), no fix is produced and the user is
    /// told to enter a city. No coordinates can reach a search.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LTC_EXPECT_LOCATION_DENIED"] == "1"))
    func deniedLocationFallsBackToManualCity() async throws {
        let autofill = LTCLocationAutofill()
        autofill.requestOnce()
        var waited = 0
        while autofill.isWorking && waited < 100 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        #expect(autofill.deviceFix == nil)
        #expect(autofill.statusText?.contains("Enter a city") == true)
        #expect(LocalHelpLocationResolver.deviceCoordinates(
            city: "Boise", region: "ID", countryCode: "US", fix: autofill.deviceFix) == nil)
    }

    /// Curated luxury hubs still come back (no Places involved).
    @Test func luxuryClothingStillReturnsCuratedHubs() async throws {
        let location = LocalHelpLocationResolver.makeLocationDTO(
            city: "Boise", region: "ID", countryCode: "US", radiusMiles: 25, coordinates: nil)
        let (item, container) = try item("Chanel jacket", category: "Clothing", value: 900)
        _ = container

        let r = try await service().searchPartners(item: item, location: location, radiusMiles: 25)
        #expect(r.scenarioId == "clothing_luxury_med_high_value")
        #expect(Set(r.results.map(\.name)) == ["The RealReal", "Vestiaire Collective", "Grailed (Menswear)"])
        #expect(!r.hasGooglePlacesResults)
    }
}
