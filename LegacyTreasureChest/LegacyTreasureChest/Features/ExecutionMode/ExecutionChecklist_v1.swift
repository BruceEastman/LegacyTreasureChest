//
//  ExecutionChecklist_v1.swift
//  LegacyTreasureChest
//
//  Execution Mode v1: Standard, non-configurable lot checklist.
//  This file is the code representation of the semantically locked spec in EXECUTION_MODE_v1.md.
//  iOS 18+, Swift 6.
//

import Foundation

// MARK: - Execution Mode v1 Checklist

/// Canonical checklist definition for Execution Mode v1.
///
/// Notes:
/// - This is NOT loaded from markdown at runtime.
/// - Checklist items are not configurable in v1.
/// - `stepId` is the persisted key (stored in LotChecklistItemState.stepId).
/// - "ready" is the final item by definition.
public enum ExecutionChecklistV1 {

    // MARK: Sections

    public struct Section: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let items: [ItemDefinition]

        public init(id: String, title: String, items: [ItemDefinition]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    // MARK: Items

    public struct ItemDefinition: Identifiable, Hashable, Sendable {
        /// Stable identifier used for persistence (`LotChecklistItemState.stepId`)
        public let id: String

        /// User-facing checklist text
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    // MARK: - Canonical Checklist (v1)

    /// The canonical ordered sections and items for v1.
    public static let sections: [Section] = [
        Section(
            id: "preparation",
            title: "Preparation",
            items: [
                ItemDefinition(id: "review_contents", title: "Review items and sets in this lot"),
                ItemDefinition(id: "confirm_disposition", title: "Confirm disposition choices"),
                ItemDefinition(id: "add_handling_notes", title: "Add handling notes if needed")
            ]
        ),
        Section(
            id: "documentation",
            title: "Documentation",
            items: [
                ItemDefinition(id: "verify_photos", title: "Verify photos exist for all items"),
                ItemDefinition(id: "add_missing_photos", title: "Add missing photos (if discovered during execution)")
            ]
        ),
        Section(
            id: "staging",
            title: "Staging",
            items: [
                ItemDefinition(id: "physically_group_items", title: "Physically group items"),
                ItemDefinition(id: "label_with_lot_number", title: "Label items with lot number"),
                ItemDefinition(id: "note_location", title: "Note location (room / storage area)")
            ]
        ),
        Section(
            id: "ready",
            title: "Ready",
            items: [
                ItemDefinition(id: "ready", title: "Lot is ready for sale / handoff")
            ]
        )
    ]

    /// Flat, ordered list of all item definitions.
    public static let allItems: [ItemDefinition] = sections.flatMap { $0.items }

    /// The final checklist stepId by definition (v1).
    public static let finalStepId: String = "ready"
}

