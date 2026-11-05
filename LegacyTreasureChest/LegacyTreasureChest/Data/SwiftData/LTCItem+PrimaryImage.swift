//
//  LTCItem+PrimaryImage.swift
//  LegacyTreasureChest
//
//  Deterministic photo order and primary photo for an item.
//
//  `LTCItem.images` is an unordered SwiftData to-many relationship, so
//  `images.first` can return any photo. Every photo-creation path (Add Item,
//  adding photos on Item Detail, Batch Add) creates ItemImage records one at a
//  time in the order the owner picked them, each stamped with `createdAt`. The
//  earliest photo is therefore the photo the item was created with, and it is
//  the primary photo. Later photos are supplementary.
//
//  Rules (no schema change):
//  - Order: `createdAt` ascending; equal dates fall back to `imageId` so the
//    order is stable.
//  - Primary: the first photo in that order. If it is deleted, the next
//    earliest photo becomes primary automatically.
//  - No photos: `primaryImage` is nil.
//

import Foundation
import SwiftData

extension ItemImage {
    /// Strict ordering used for an item's photos: oldest first, then `imageId`.
    static func isOrderedBefore(_ lhs: ItemImage, _ rhs: ItemImage) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.imageId.uuidString < rhs.imageId.uuidString
    }
}

extension LTCItem {
    /// The item's photos in deterministic order (primary first).
    /// Photos already deleted from the model context but still present in the
    /// relationship before the next save are excluded.
    var orderedImages: [ItemImage] {
        images
            .filter { !$0.isDeleted }
            .sorted(by: ItemImage.isOrderedBefore)
    }

    /// The primary photo: the photo the item was created with, or the next
    /// earliest photo if that one was deleted. Nil when the item has no photos.
    var primaryImage: ItemImage? {
        images
            .filter { !$0.isDeleted }
            .min(by: ItemImage.isOrderedBefore)
    }

    /// Photos after the primary photo, in order.
    var supplementaryImages: [ItemImage] {
        Array(orderedImages.dropFirst())
    }
}
