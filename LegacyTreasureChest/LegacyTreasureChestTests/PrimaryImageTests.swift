//
//  PrimaryImageTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 1: deterministic photo order and primary photo
//  (LTCItem+PrimaryImage). Synthetic data, in-memory store, no network.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

@MainActor
struct PrimaryImageTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: LTCItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeItem(_ context: ModelContext) -> LTCItem {
        let item = LTCItem(name: "Sample", itemDescription: "", category: "Furniture")
        context.insert(item)
        return item
    }

    /// Mirrors ItemPhotosSection.handlePickedItems / AddItemView.saveItem:
    /// create, link, append, insert.
    @discardableResult
    private func addPhoto(_ path: String, at date: Date, id: UUID = UUID(),
                          to item: LTCItem, in context: ModelContext) -> ItemImage {
        let image = ItemImage(imageId: id, filePath: path, createdAt: date)
        image.item = item
        item.images.append(image)
        context.insert(image)
        return image
    }

    @Test func itemWithoutPhotosHasNoPrimary() throws {
        let context = try makeContext()
        let item = makeItem(context)
        try context.save()

        #expect(item.primaryImage == nil)
        #expect(item.orderedImages.isEmpty)
        #expect(item.supplementaryImages.isEmpty)
    }

    @Test func creationPhotoIsPrimaryRegardlessOfRelationshipOrder() throws {
        let context = try makeContext()
        let item = makeItem(context)
        // Appended out of order on purpose: relationship order must not matter.
        addPhoto("stamp.jpg", at: t0.addingTimeInterval(60), to: item, in: context)
        addPhoto("creation.jpg", at: t0, to: item, in: context)
        addPhoto("label.jpg", at: t0.addingTimeInterval(120), to: item, in: context)
        try context.save()

        #expect(item.primaryImage?.filePath == "creation.jpg")
        #expect(item.orderedImages.map(\.filePath) == ["creation.jpg", "stamp.jpg", "label.jpg"])
        #expect(item.supplementaryImages.map(\.filePath) == ["stamp.jpg", "label.jpg"])
    }

    @Test func equalDatesUseStableImageIdTieBreak() throws {
        let context = try makeContext()
        let item = makeItem(context)
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        addPhoto("high.jpg", at: t0, id: highID, to: item, in: context)
        addPhoto("low.jpg", at: t0, id: lowID, to: item, in: context)
        try context.save()

        #expect(item.primaryImage?.filePath == "low.jpg")
        #expect(item.orderedImages.map(\.filePath) == ["low.jpg", "high.jpg"])
        // Repeated reads give the same answer.
        for _ in 0..<5 { #expect(item.primaryImage?.imageId == lowID) }
    }

    @Test func deletingPrimaryPromotesNextEarliest() throws {
        let context = try makeContext()
        let item = makeItem(context)
        let primary = addPhoto("creation.jpg", at: t0, to: item, in: context)
        addPhoto("second.jpg", at: t0.addingTimeInterval(10), to: item, in: context)
        addPhoto("third.jpg", at: t0.addingTimeInterval(20), to: item, in: context)
        try context.save()

        // ItemPhotosSection.deletePhoto deletes from the context only.
        context.delete(primary)
        #expect(item.primaryImage?.filePath == "second.jpg")   // before save
        try context.save()
        #expect(item.primaryImage?.filePath == "second.jpg")   // after save
        #expect(item.orderedImages.map(\.filePath) == ["second.jpg", "third.jpg"])
    }

    @Test func deletingOnlyPhotoLeavesNoPrimary() throws {
        let context = try makeContext()
        let item = makeItem(context)
        let only = addPhoto("only.jpg", at: t0, to: item, in: context)
        try context.save()

        context.delete(only)
        try context.save()
        #expect(item.primaryImage == nil)
    }

    @Test func firstPhotoAddedToPhotolessItemBecomesPrimaryAndStays() throws {
        let context = try makeContext()
        let item = makeItem(context)   // manual item created without photos
        try context.save()

        addPhoto("first.jpg", at: t0, to: item, in: context)
        try context.save()
        #expect(item.primaryImage?.filePath == "first.jpg")

        // Later evidence photos are supplementary.
        addPhoto("evidence.jpg", at: t0.addingTimeInterval(3600), to: item, in: context)
        try context.save()
        #expect(item.primaryImage?.filePath == "first.jpg")
        #expect(item.supplementaryImages.map(\.filePath) == ["evidence.jpg"])
    }

    @Test func batchAddSinglePhotoIsPrimary() throws {
        let context = try makeContext()
        // Mirrors BatchAddItemsFromPhotosView.createItem: one ItemImage per item.
        let item = LTCItem(name: "Batch", itemDescription: "", category: "Decor")
        let image = ItemImage(filePath: "batch.jpg")
        item.images.append(image)
        context.insert(item)
        try context.save()

        #expect(item.primaryImage?.filePath == "batch.jpg")
        #expect(item.supplementaryImages.isEmpty)
    }

    @Test func manualCreationLoopKeepsPickOrder() throws {
        let context = try makeContext()
        let item = makeItem(context)
        // AddItemView saves picked photos one at a time; each record is stamped
        // when created, so the first picked photo is the earliest.
        for (offset, name) in ["picked1.jpg", "picked2.jpg", "picked3.jpg"].enumerated() {
            addPhoto(name, at: t0.addingTimeInterval(Double(offset) * 0.25), to: item, in: context)
        }
        try context.save()

        #expect(item.primaryImage?.filePath == "picked1.jpg")
        #expect(item.orderedImages.map(\.filePath) == ["picked1.jpg", "picked2.jpg", "picked3.jpg"])
    }
}
