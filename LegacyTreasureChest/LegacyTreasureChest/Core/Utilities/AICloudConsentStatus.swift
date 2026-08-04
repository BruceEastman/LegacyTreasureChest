//
//  AICloudConsentStatus.swift
//  LegacyTreasureChest
//
//  Persisted user choice about sending selected item data off-device for
//  optional AI / Local Help features. Distinguishes "never asked" from
//  an explicit decline so the disclosure sheet is shown at most once
//  automatically, and can otherwise only be reached by explicit review.
//

import Foundation

enum AICloudConsentStatus: String {
    case notDetermined
    case granted
    case declined
}
