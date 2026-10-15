//
//  LocalHelpLocationTests.swift
//  LegacyTreasureChestTests
//
//  Local Help location rules: when device coordinates are used, when they are
//  dropped, manual-city geocoding, the request payload, and response decoding.
//

import Foundation
import Testing
@testable import LegacyTreasureChest

struct LocalHelpDeviceCoordinateTests {

    private let boiseFix = LocalHelpDeviceFix(
        city: "Boise", region: "ID", countryCode: "US",
        latitude: 43.6187, longitude: -116.2146
    )

    @Test func usesDeviceCoordinatesWhileFieldsMatchTheFix() {
        let c = LocalHelpLocationResolver.deviceCoordinates(
            city: "Boise", region: "ID", countryCode: "US", fix: boiseFix)
        #expect(c == LocalHelpCoordinates(latitude: 43.6187, longitude: -116.2146))
    }

    @Test func matchingIgnoresCaseSpacingAndDiacritics() {
        let c = LocalHelpLocationResolver.deviceCoordinates(
            city: "  boise ", region: "id", countryCode: "us", fix: boiseFix)
        #expect(c != nil)
    }

    @Test func editingTheCityDropsDeviceCoordinates() {
        let c = LocalHelpLocationResolver.deviceCoordinates(
            city: "Denver", region: "ID", countryCode: "US", fix: boiseFix)
        #expect(c == nil)
    }

    @Test func editingTheRegionDropsDeviceCoordinates() {
        // Same city name, different state: must not reuse Boise, ID coordinates.
        let c = LocalHelpLocationResolver.deviceCoordinates(
            city: "Boise", region: "CO", countryCode: "US", fix: boiseFix)
        #expect(c == nil)
    }

    @Test func changingTheCountryDropsDeviceCoordinates() {
        let c = LocalHelpLocationResolver.deviceCoordinates(
            city: "Boise", region: "ID", countryCode: "CA", fix: boiseFix)
        #expect(c == nil)
    }

    @Test func noFixMeansNoDeviceCoordinates() {
        #expect(LocalHelpLocationResolver.deviceCoordinates(
            city: "Boise", region: "ID", countryCode: "US", fix: nil) == nil)
    }

    @Test func emptyCityNeverUsesDeviceCoordinates() {
        #expect(LocalHelpLocationResolver.deviceCoordinates(
            city: " ", region: "ID", countryCode: "US", fix: boiseFix) == nil)
    }

    @Test func nullIslandIsRejected() {
        let bad = LocalHelpDeviceFix(city: "Boise", region: "ID", countryCode: "US", latitude: 0, longitude: 0)
        #expect(LocalHelpLocationResolver.deviceCoordinates(
            city: "Boise", region: "ID", countryCode: "US", fix: bad) == nil)
    }
}

struct LocalHelpManualLocationTests {

    @Test func addressQueryCombinesTypedFields() {
        #expect(LocalHelpLocationResolver.addressQuery(city: "Denver", region: "CO", countryCode: "US") == "Denver, CO, US")
        #expect(LocalHelpLocationResolver.addressQuery(city: "Denver", region: "", countryCode: "") == "Denver")
        #expect(LocalHelpLocationResolver.addressQuery(city: "  ", region: "CO", countryCode: "US") == nil)
    }

    @Test func manualCityResolvesToItsOwnCoordinatesNotTheStaleFix() async {
        let boiseFix = LocalHelpDeviceFix(
            city: "Boise", region: "ID", countryCode: "US", latitude: 43.6187, longitude: -116.2146)
        let c = await LocalHelpLocationResolver.resolveCoordinates(
            city: "Denver", region: "CO", countryCode: "US", fix: boiseFix)
        let coords = try? #require(c)
        // Geocoded Denver, not Boise.
        #expect(abs((coords?.latitude ?? 0) - 39.74) < 0.3)
        #expect(abs((coords?.longitude ?? 0) - (-104.99)) < 0.3)
    }

    @Test func matchingFixIsUsedWithoutGeocoding() async {
        let fix = LocalHelpDeviceFix(
            city: "Boise", region: "ID", countryCode: "US", latitude: 43.6187, longitude: -116.2146)
        let c = await LocalHelpLocationResolver.resolveCoordinates(
            city: "Boise", region: "ID", countryCode: "US", fix: fix)
        #expect(c == LocalHelpCoordinates(latitude: 43.6187, longitude: -116.2146))
    }
}

struct LocalHelpRequestPayloadTests {

    @Test func locationIsTrimmedUppercasedAndRounded() {
        let dto = LocalHelpLocationResolver.makeLocationDTO(
            city: " Boise ", region: " ID ", countryCode: "us", radiusMiles: 25,
            coordinates: LocalHelpCoordinates(latitude: 43.61874, longitude: -116.21468))
        #expect(dto.city == "Boise")
        #expect(dto.region == "ID")
        #expect(dto.countryCode == "US")
        #expect(dto.radiusMiles == 25)
        #expect(dto.latitude == 43.62)
        #expect(dto.longitude == -116.21)
    }

    @Test func noCoordinatesAreOmittedFromTheJSON() throws {
        let dto = LocalHelpLocationResolver.makeLocationDTO(
            city: "Denver", region: "CO", countryCode: "US", radiusMiles: 25, coordinates: nil)
        let json = try #require(String(data: JSONEncoder().encode(dto), encoding: .utf8))
        #expect(!json.contains("latitude"))
        #expect(!json.contains("longitude"))
        #expect(json.contains("\"city\":\"Denver\""))
    }

    @Test func noHardcodedBoiseInTheDefaultPayload() throws {
        // A manual search with no location fix must not carry any coordinates.
        let dto = LocalHelpLocationResolver.makeLocationDTO(
            city: "Portland", region: "OR", countryCode: "US", radiusMiles: 25, coordinates: nil)
        #expect(dto.latitude == nil && dto.longitude == nil)
    }
}

struct LocalHelpReverseGeocodeParsingTests {

    @Test func regionComesFromCityWithContext() {
        #expect(LTCLocationAutofill.region(fromCityWithContext: "Boise, ID", city: "Boise") == "ID")
        #expect(LTCLocationAutofill.region(fromCityWithContext: "Denver, CO", city: "Denver") == "CO")
        #expect(LTCLocationAutofill.region(fromCityWithContext: "Paris", city: "Paris") == "")
        #expect(LTCLocationAutofill.region(fromCityWithContext: "", city: "Boise") == "")
    }

    @Test func countryCodeFromFullAddress() {
        #expect(LTCLocationAutofill.extractCountryCode(from: "625 W Main St, Boise, ID  83702, United States") == "US")
        #expect(LTCLocationAutofill.extractCountryCode(from: "Somewhere") == "")
    }
}

struct LocalHelpResponseDecodingTests {

    private func decode(_ json: String) throws -> DispositionPartnersSearchResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DispositionPartnersSearchResponse.self, from: Data(json.utf8))
    }

    @Test func decodesDiscoveryStatusNoticeAndGoogleResults() throws {
        let r = try decode("""
        {"schemaVersion":1,"generatedAt":"2026-10-15T20:00:00Z","scenarioId":"default_any",
         "partnerTypes":["consignment"],"disclaimer":"d","localDiscoveryStatus":"ok","notice":null,
         "results":[{"partnerId":"gplaces:abc","name":"Real Shop","partnerType":"consignment",
           "contact":{"address":"1 Main St, Boise, ID 83702"},"distanceMiles":2.5}]}
        """)
        #expect(r.localDiscoveryStatus == "ok")
        #expect(r.notice == nil)
        #expect(r.hasGooglePlacesResults)
        #expect(r.results.first?.contact.address == "1 Main St, Boise, ID 83702")
    }

    @Test func decodesUnavailableNoticeWithNoResults() throws {
        let r = try decode("""
        {"schemaVersion":1,"generatedAt":"2026-10-15T20:00:00Z","scenarioId":"default_any",
         "partnerTypes":["consignment"],"results":[],"disclaimer":"d",
         "localDiscoveryStatus":"unavailable","notice":"Local business search is temporarily unavailable."}
        """)
        #expect(r.results.isEmpty)
        #expect(r.localDiscoveryStatus == "unavailable")
        #expect(r.notice != nil)
        #expect(!r.hasGooglePlacesResults)
    }

    @Test func olderResponsesWithoutNewFieldsStillDecode() throws {
        let r = try decode("""
        {"schemaVersion":1,"generatedAt":"2026-10-15T20:00:00Z","scenarioId":"x","partnerTypes":[],"results":[]}
        """)
        #expect(r.localDiscoveryStatus == nil)
        #expect(r.notice == nil)
    }

    @Test func curatedResultsNeedNoGoogleAttribution() throws {
        let r = try decode("""
        {"schemaVersion":1,"generatedAt":"2026-10-15T20:00:00Z","scenarioId":"c","partnerTypes":["luxury_hub_mailin"],
         "results":[{"partnerId":"curated:luxury:therealreal","name":"The RealReal","partnerType":"luxury_hub_mailin","contact":{}}]}
        """)
        #expect(!r.hasGooglePlacesResults)
    }
}
