//
//  LocalHelpLocation.swift
//  LegacyTreasureChest
//
//  Location handling for Local Help searches.
//  - LTCLocationAutofill: one-shot "Use Current Location" (When In Use permission)
//  - LocalHelpLocationResolver: decides which coordinates (if any) go with a search
//
//  Rules:
//  - Device coordinates are used only while the City/State/Country fields still
//    show the place the device reported. Editing the city drops them.
//  - A typed city is geocoded on device (MapKit) to get its own coordinates.
//  - If neither is available, no coordinates are sent. The backend then searches
//    by city name and shows no distances rather than inventing them.
//  - Coordinates are rounded to ~1 km before they leave the device and are
//    never persisted. Only the last city/region text is saved.
//

import Combine
import CoreLocation
import Foundation
import MapKit

/// The place reported by the device for a "Use Current Location" request.
struct LocalHelpDeviceFix: Equatable, Sendable {
    var city: String
    var region: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
}

struct LocalHelpCoordinates: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

enum LocalHelpLocationResolver {

    static let lastCityKey = "ltc.lastDisposition.city"
    static let lastRegionKey = "ltc.lastDisposition.region"

    /// Device coordinates, but only if the fields still describe the device's place.
    static func deviceCoordinates(
        city: String,
        region: String,
        countryCode: String,
        fix: LocalHelpDeviceFix?
    ) -> LocalHelpCoordinates? {
        guard let fix else { return nil }

        let cityNow = normalize(city)
        guard !cityNow.isEmpty, cityNow == normalize(fix.city) else { return nil }

        let fixRegion = normalize(fix.region)
        if !fixRegion.isEmpty, normalize(region) != fixRegion { return nil }

        let fixCountry = normalize(fix.countryCode)
        let countryNow = normalize(countryCode)
        if !fixCountry.isEmpty, !countryNow.isEmpty, countryNow != fixCountry { return nil }

        guard isValid(latitude: fix.latitude, longitude: fix.longitude) else { return nil }
        return LocalHelpCoordinates(latitude: fix.latitude, longitude: fix.longitude)
    }

    /// "Denver, CO, US" style query for on-device geocoding of a typed place.
    static func addressQuery(city: String, region: String, countryCode: String) -> String? {
        let parts = [city, region, countryCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    /// Coordinates for a search: the device fix when it still applies,
    /// otherwise the typed city geocoded on device, otherwise nil.
    @MainActor
    static func resolveCoordinates(
        city: String,
        region: String,
        countryCode: String,
        fix: LocalHelpDeviceFix?
    ) async -> LocalHelpCoordinates? {
        if let device = deviceCoordinates(city: city, region: region, countryCode: countryCode, fix: fix) {
            return device
        }
        guard let query = addressQuery(city: city, region: region, countryCode: countryCode),
              let request = MKGeocodingRequest(addressString: query) else {
            return nil
        }
        do {
            let items = try await request.mapItems
            guard let coordinate = items.first?.location.coordinate,
                  isValid(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
                return nil
            }
            return LocalHelpCoordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            return nil
        }
    }

    static func makeLocationDTO(
        city: String,
        region: String,
        countryCode: String,
        radiusMiles: Int,
        coordinates: LocalHelpCoordinates?
    ) -> DispositionLocationDTO {
        DispositionLocationDTO(
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            countryCode: countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            radiusMiles: radiusMiles,
            latitude: coordinates.map { roundedForSearch($0.latitude) },
            longitude: coordinates.map { roundedForSearch($0.longitude) }
        )
    }

    /// Two decimal places (~1 km): enough for business distances, not an address.
    static func roundedForSearch(_ degrees: Double) -> Double {
        (degrees * 100).rounded() / 100
    }

    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }

    static func isValid(latitude: Double, longitude: Double) -> Bool {
        CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            && !(latitude == 0 && longitude == 0)
    }
}

/// One-shot current-location lookup for Local Help.
/// Requests When In Use permission only when the user asks for (or the screen
/// needs) a location, and reports the result as a single `LocalHelpDeviceFix`.
final class LTCLocationAutofill: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// Set once per successful lookup. Views copy it into their fields.
    @Published var deviceFix: LocalHelpDeviceFix? = nil

    @Published var statusText: String? = nil
    @Published var isWorking: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce() {
        // Don’t spam requests
        guard !isWorking else { return }
        isWorking = true
        statusText = "Using your current location…"

        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            statusText = "Location access is off. Enter a city, or allow location for Legacy Treasure Chest in Settings."
            isWorking = false
        @unknown default:
            statusText = "Location status unknown. Enter a city."
            isWorking = false
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Only act if a lookup is in progress (the delegate also fires on creation).
        guard isWorking else { return }
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            statusText = "Location access is off. Enter a city, or allow location for Legacy Treasure Chest in Settings."
            isWorking = false
        case .notDetermined:
            break
        @unknown default:
            statusText = "Location status unknown. Enter a city."
            isWorking = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "Couldn’t get current location. Enter a city."
        isWorking = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else {
            statusText = "Couldn’t get current location. Enter a city."
            isWorking = false
            return
        }

        guard let request = MKReverseGeocodingRequest(location: loc) else {
            statusText = "Couldn’t determine your location details. Enter a city."
            isWorking = false
            return
        }

        let coordinate = loc.coordinate

        Task { [weak self] in
            guard let self else { return }

            do {
                let mapItems = try await request.mapItems
                let mapItem = mapItems.first

                let fullAddress = mapItem?.address?.fullAddress ?? ""
                let reps = mapItem?.addressRepresentations

                // Use MapKit's structured city fields. The short address starts
                // with the street ("625 W Main St, Boise"), so it can't be split.
                let city = (reps?.cityName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let region = Self.region(fromCityWithContext: reps?.cityWithContext(.short) ?? "", city: city)
                let cc = Self.extractCountryCode(from: fullAddress)

                await MainActor.run {
                    if city.isEmpty {
                        self.statusText = "Couldn’t determine your city. Enter a city."
                    } else {
                        self.deviceFix = LocalHelpDeviceFix(
                            city: city,
                            region: region,
                            countryCode: cc,
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                        self.statusText = nil
                    }
                    self.isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.statusText = "Couldn’t determine your location details. Enter a city."
                    self.isWorking = false
                }
            }
        }
    }

    /// "Boise, ID" -> "ID". Empty when MapKit gives no state/province context.
    static func region(fromCityWithContext text: String, city: String) -> String {
        let parts = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return "" }
        let last = parts[parts.count - 1]
        return LocalHelpLocationResolver.normalize(last) == LocalHelpLocationResolver.normalize(city) ? "" : last
    }

    static func extractCountryCode(from fullAddress: String) -> String {
        let normalized = fullAddress.lowercased()

        if normalized.contains("united states") || normalized.contains("usa") {
            return "US"
        }
        if normalized.contains("canada") {
            return "CA"
        }
        if normalized.contains("united kingdom") {
            return "GB"
        }

        return ""
    }
}
