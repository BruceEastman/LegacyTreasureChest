//
//  EstateReportGenerator.swift
//  LegacyTreasureChest
//
//  Generates simple, attorney-friendly PDF reports:
//  - Estate Snapshot Report
//  - Detailed Inventory Report
//
//  Uses only existing models (LTCItem, Beneficiary, ItemBeneficiary, ItemValuation).
//

import Foundation
import UIKit
import SwiftData

enum EstateReportGenerator {

    // MARK: - Public API

    /// High-level estate summary: totals, paths, beneficiaries, categories, and top-valued items.
    static func generateSnapshotReport(
        items: [LTCItem],
        itemSets: [LTCItemSet] = [],
        batches: [LiquidationBatch] = [],
        beneficiaries: [Beneficiary]
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var cursorY: CGFloat = 40

            // Header
            let generatedDate = currentDateString()

            cursorY = drawTitle("Estate Snapshot Report", in: pageRect, y: cursorY)
            cursorY += 6
            cursorY = drawSubheading(generatedDate, in: pageRect, y: cursorY)
            cursorY += 8

            cursorY = drawCaptionText(
                "This report reflects the current state of the estate as of \(generatedDate).",
                in: pageRect,
                y: cursorY
            )

            cursorY += 16

            // Compute aggregates once
            let aggregates = EstateAggregates(items: items, itemSets: itemSets, batches: batches, beneficiaries: beneficiaries)
            func drawKeyValue(_ key: String, _ value: String) {
                cursorY = drawBodyText("\(key): \(value)", in: pageRect, y: cursorY)
            }

            func drawBullet(_ text: String) {
                cursorY = drawBodyText("• \(text)", in: pageRect, y: cursorY)
            }


            // MARK: - Executive Summary
            cursorY = ensureSpace(for: 160, in: pageRect, context: context, currentY: cursorY)
            cursorY = drawSectionHeader("Executive Summary", in: pageRect, y: cursorY)
            cursorY += 4

            drawKeyValue("Total estate (conservative resale)", currencyString(aggregates.totalEstateValue))
            drawKeyValue("Total cataloged items", "\(aggregates.totalItems)")
            cursorY += 6

            drawBullet("Legacy: \(aggregates.legacyItemCount) item\(aggregates.legacyItemCount == 1 ? "" : "s") · \(currencyString(aggregates.legacyValue)) (\(percentString(aggregates.legacyValueShare)) of value)")
            drawBullet("Liquidate: \(aggregates.liquidateItemCount) item\(aggregates.liquidateItemCount == 1 ? "" : "s") · \(currencyString(aggregates.liquidateValue)) (\(percentString(aggregates.liquidateValueShare)) of value)")

            cursorY += 10
            cursorY = drawCaptionText(
                "Totals reflect quantity (unit value × quantity). Values use the best available estimate (valuation estimate if present; otherwise the item’s stored value).",
                in: pageRect,
                y: cursorY
            )

            // MARK: - Disposition Summary (Disposition Snapshot v2)
            cursorY += 18
            cursorY = ensureSpace(for: 160, in: pageRect, context: context, currentY: cursorY)
            cursorY = drawSectionHeader("Disposition Summary (Disposition Snapshot v2)", in: pageRect, y: cursorY)
            cursorY += 4

            cursorY = drawCaptionText(
                "This section reflects LiquidationState status for Items, Sets, and Batches. Totals are advisory and reflect the catalog as of \(generatedDate).",
                in: pageRect,
                y: cursorY
            )
            cursorY += 6

            func drawRollup(label: String, rollup: EstateAggregates.DispositionRollup, note: String? = nil) {
                cursorY = ensureSpace(for: 120, in: pageRect, context: context, currentY: cursorY)
                cursorY = drawBodyText("\(label): \(rollup.entityCount) · \(currencyString(rollup.totalValue))", in: pageRect, y: cursorY)

                cursorY = drawBodyText(
                    "Status — Not Started: \(rollup.notStartedCount), Has Brief: \(rollup.hasBriefCount), In Progress: \(rollup.inProgressCount), Completed: \(rollup.completedCount), On Hold: \(rollup.onHoldCount), N/A: \(rollup.notApplicableCount)",
                    in: pageRect,
                    y: cursorY
                )

                cursorY = drawBodyText(
                    "Records — Active Brief: \(rollup.activeBriefCount), Active Plan: \(rollup.activePlanCount)",
                    in: pageRect,
                    y: cursorY
                )

                if let note {
                    cursorY = drawCaptionText(note, in: pageRect, y: cursorY)
                }
                cursorY += 8
            }

            drawRollup(label: "Items", rollup: aggregates.itemDispositionRollup)

            drawRollup(
                label: "Sets",
                rollup: aggregates.setDispositionRollup,
                note: "Set value is computed conservatively from member items (valuation estimate if present; otherwise stored item value) × membership quantity."
            )

            drawRollup(
                label: "Batches",
                rollup: aggregates.batchDispositionRollup,
                note: "Batch value is a staging view based on linked items/sets. Batch-level inclusion/exclusion rules may be refined in a later version."
            )

            // MARK: - Legacy Allocation by Beneficiary
            cursorY += 18
            cursorY = ensureSpace(for: 120, in: pageRect, context: context, currentY: cursorY)
            cursorY = drawSectionHeader("Legacy Allocation by Beneficiary", in: pageRect, y: cursorY)
            cursorY += 4

            if aggregates.beneficiarySummaries.isEmpty {
                cursorY = drawBodyText("None recorded.", in: pageRect, y: cursorY)
            } else {
                for summary in aggregates.beneficiarySummaries {
                    let line = "\(summary.name): \(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s") · \(currencyString(summary.totalValue))"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }

            // MARK: - Value by Category
            cursorY += 18
            cursorY = ensureSpace(for: 120, in: pageRect, context: context, currentY: cursorY)
            cursorY = drawSectionHeader("Value by Category", in: pageRect, y: cursorY)
            cursorY += 4

            if aggregates.categorySummaries.isEmpty {
                cursorY = drawBodyText("None recorded.", in: pageRect, y: cursorY)
            } else {
                for summary in aggregates.categorySummaries {
                    let displayName = summary.name.isEmpty ? "Uncategorized" : summary.name
                    let line = "\(displayName): \(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s") · \(currencyString(summary.totalValue))"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }

            // MARK: - Highest Value Assets
            cursorY += 18
            cursorY = ensureSpace(for: 160, in: pageRect, context: context, currentY: cursorY)
            cursorY = drawSectionHeader("Highest Value Assets", in: pageRect, y: cursorY)
            cursorY += 4

            // Legacy
            cursorY = drawBodyText("Legacy (Top \(min(5, aggregates.topLegacyItems.count))):", in: pageRect, y: cursorY)
            if aggregates.topLegacyItems.isEmpty {
                cursorY = drawBodyText("None recorded.", in: pageRect, y: cursorY)
            } else {
                for item in aggregates.topLegacyItems {
                    let qty = max(item.quantity, 1)
                    let unit = aggregates.effectiveUnitValue(for: item)
                    let total = aggregates.effectiveTotalValue(for: item)
                    let unitSuffix = qty > 1 ? " (\(currencyString(unit)) each ×\(qty))" : ""
                    let category = item.category.isEmpty ? "Uncategorized" : item.category
                    let line = "• \(item.name) (\(category)) – \(currencyString(total))\(unitSuffix)"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }

            cursorY += 10
            cursorY = ensureSpace(for: 120, in: pageRect, context: context, currentY: cursorY)

            // Liquidate
            cursorY = drawBodyText("Liquidate (Top \(min(5, aggregates.topLiquidateItems.count))):", in: pageRect, y: cursorY)
            if aggregates.topLiquidateItems.isEmpty {
                cursorY = drawBodyText("None recorded.", in: pageRect, y: cursorY)
            } else {
                for item in aggregates.topLiquidateItems {
                    let qty = max(item.quantity, 1)
                    let unit = aggregates.effectiveUnitValue(for: item)
                    let total = aggregates.effectiveTotalValue(for: item)
                    let unitSuffix = qty > 1 ? " (\(currencyString(unit)) each ×\(qty))" : ""
                    let category = item.category.isEmpty ? "Uncategorized" : item.category
                    let line = "• \(item.name) (\(category)) – \(currencyString(total))\(unitSuffix)"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }

            // MARK: - Footer Metadata
            cursorY += 22
            cursorY = ensureSpace(for: 80, in: pageRect, context: context, currentY: cursorY)
            cursorY = drawCaptionText(
                "Generated on-device · Report schema: Exports.v1 · Snapshot: Disposition.v2 · \(generatedDate)",
                in: pageRect,
                y: cursorY
            )
        }

        return data
    }

    /// Full item list with estate path, beneficiary, and value.
    static func generateInventoryReport(items: [LTCItem]) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var cursorY: CGFloat = 40

            let aggregates = EstateAggregates(items: items, itemSets: [], batches: [], beneficiaries: [])

            // Header
            let generatedDate = currentDateString()

            cursorY = drawTitle("Detailed Inventory Report", in: pageRect, y: cursorY)
            cursorY += 6
            cursorY = drawSubheading(generatedDate, in: pageRect, y: cursorY)
            cursorY += 8

            cursorY = drawCaptionText(
                "This report reflects the current state of the estate as of \(generatedDate).",
                in: pageRect,
                y: cursorY
            )

            cursorY += 16

            cursorY = drawCaptionText(
                "This report lists all cataloged items with category, estate path (Legacy or Liquidate), first beneficiary (if any), quantity, unit value, and total value (unit × quantity).",
                in: pageRect,
                y: cursorY
            )
            cursorY += 16

            // Table headers
            func drawTableHeader(at y: CGFloat) -> CGFloat {
                let rowY = y + 2
                drawTableRow(
                    name: "Name",
                    category: "Category",
                    path: "Path",
                    beneficiary: "Beneficiary",
                    quantity: "Qty",
                    unitValue: "Each",
                    totalValue: "Total",
                    in: pageRect,
                    y: rowY,
                    isHeader: true
                )
                return rowY + 18
            }

            cursorY = drawTableHeader(at: cursorY)

            // Sort items by category then name for readability
            let sortedItems = items.sorted {
                if $0.category == $1.category {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
            }

            for item in sortedItems {

                // Check space before drawing row
                let previousY = cursorY
                cursorY = ensureSpace(
                    for: 22,
                    in: pageRect,
                    context: context,
                    currentY: cursorY
                )

                // If we started a new page, redraw table header properly
                if cursorY == 40 && previousY != 40 {
                    cursorY = drawTableHeader(at: cursorY)
                }

                let path = aggregates.isLegacy(item) ? "Legacy" : "Liquidate"
                let beneficiaryName = item.itemBeneficiaries.first?.beneficiary?.name ?? ""

                let qty = max(item.quantity, 1)
                let unit = aggregates.effectiveUnitValue(for: item)
                let total = aggregates.effectiveTotalValue(for: item)

                drawTableRow(
                    name: item.name,
                    category: item.category,
                    path: path,
                    beneficiary: beneficiaryName,
                    quantity: "\(qty)",
                    unitValue: currencyString(unit),
                    totalValue: currencyString(total),
                    in: pageRect,
                    y: cursorY,
                    isHeader: false
                )

                cursorY += 18
            }
        }

        return data
    }

    // MARK: - Internal Aggregates

    private struct BeneficiarySummary {
        let name: String
        let itemCount: Int
        let totalValue: Double
    }

    private struct CategorySummary {
        let name: String
        let itemCount: Int
        let totalValue: Double
    }

    private struct EstateAggregates {
        let items: [LTCItem]
        let itemSets: [LTCItemSet]
        let batches: [LiquidationBatch]
        let beneficiaries: [Beneficiary]

        let totalItems: Int
        let totalEstateValue: Double

        // v1 heuristic (beneficiary-based) still used for beneficiary/category/top-item sections
        let legacyItems: [LTCItem]
        let liquidateItems: [LTCItem]
        let legacyItemCount: Int
        let liquidateItemCount: Int

        let legacyValue: Double
        let liquidateValue: Double
        let legacyValueShare: Double
        let liquidateValueShare: Double

        let beneficiarySummaries: [BeneficiarySummary]
        let categorySummaries: [CategorySummary]
        let topLegacyItems: [LTCItem]
        let topLiquidateItems: [LTCItem]

        // Disposition Snapshot v2 (state-based)
        let itemDispositionRollup: DispositionRollup
        let setDispositionRollup: DispositionRollup
        let batchDispositionRollup: DispositionRollup

        struct DispositionRollup {
            let entityCount: Int
            let totalValue: Double

            let notStartedCount: Int
            let hasBriefCount: Int
            let inProgressCount: Int
            let completedCount: Int
            let onHoldCount: Int
            let notApplicableCount: Int

            let activeBriefCount: Int
            let activePlanCount: Int
        }

        init(items: [LTCItem], itemSets: [LTCItemSet], batches: [LiquidationBatch], beneficiaries: [Beneficiary]) {
            self.items = items
            self.itemSets = itemSets
            self.batches = batches
            self.beneficiaries = beneficiaries

            self.totalItems = items.count
            self.totalEstateValue = items.reduce(0) { $0 + Self.effectiveTotalValueStatic(for: $1) }

            self.legacyItems = items.filter { !$0.itemBeneficiaries.isEmpty }
            self.liquidateItems = items.filter { $0.itemBeneficiaries.isEmpty }

            self.legacyItemCount = legacyItems.count
            self.liquidateItemCount = liquidateItems.count

            self.legacyValue = legacyItems.reduce(0) { $0 + Self.effectiveTotalValueStatic(for: $1) }
            self.liquidateValue = liquidateItems.reduce(0) { $0 + Self.effectiveTotalValueStatic(for: $1) }

            let denominator = max(totalEstateValue, 0.01)
            self.legacyValueShare = legacyValue / denominator
            self.liquidateValueShare = liquidateValue / denominator

            // Beneficiary summaries – only Legacy items
            self.beneficiarySummaries = beneficiaries.compactMap { beneficiary in
                let ownedLegacyItems = items.filter { item in
                    item.itemBeneficiaries.contains { $0.beneficiary === beneficiary }
                }
                guard !ownedLegacyItems.isEmpty else { return nil }

                let value = ownedLegacyItems.reduce(0) { $0 + Self.effectiveTotalValueStatic(for: $1) }
                return BeneficiarySummary(
                    name: beneficiary.name.isEmpty ? "Unnamed Beneficiary" : beneficiary.name,
                    itemCount: ownedLegacyItems.count,
                    totalValue: value
                )
            }
            .sorted { $0.totalValue > $1.totalValue }

            // Category summaries
            let grouped = Dictionary(grouping: items, by: { $0.category })
            self.categorySummaries = grouped.map { (category, itemsInCategory) in
                let totalValue = itemsInCategory.reduce(0) { $0 + Self.effectiveTotalValueStatic(for: $1) }
                return CategorySummary(
                    name: category,
                    itemCount: itemsInCategory.count,
                    totalValue: totalValue
                )
            }
            .sorted { $0.totalValue > $1.totalValue }

            // Top items by TOTAL value (item-based)
            let sortedByTotalValue = items.sorted {
                Self.effectiveTotalValueStatic(for: $0) > Self.effectiveTotalValueStatic(for: $1)
            }

            self.topLegacyItems = Array(sortedByTotalValue.filter { !$0.itemBeneficiaries.isEmpty }.prefix(5))
            self.topLiquidateItems = Array(sortedByTotalValue.filter { $0.itemBeneficiaries.isEmpty }.prefix(5))

            // Disposition Snapshot v2 rollups
            self.itemDispositionRollup = Self.rollupForItems(items)
            self.setDispositionRollup = Self.rollupForSets(itemSets)
            self.batchDispositionRollup = Self.rollupForBatches(batches)
        }

        func effectiveUnitValue(for item: LTCItem) -> Double {
            Self.effectiveUnitValueStatic(for: item)
        }

        func effectiveTotalValue(for item: LTCItem) -> Double {
            Self.effectiveTotalValueStatic(for: item)
        }

        func isLegacy(_ item: LTCItem) -> Bool {
            !item.itemBeneficiaries.isEmpty
        }

        private static func effectiveUnitValueStatic(for item: LTCItem) -> Double {
            if let estimated = item.valuation?.estimatedValue, estimated > 0 {
                return estimated
            }
            return max(item.value, 0)
        }

        private static func effectiveTotalValueStatic(for item: LTCItem) -> Double {
            let qty = max(item.quantity, 1)
            return effectiveUnitValueStatic(for: item) * Double(qty)
        }

        private static func rollupForItems(_ items: [LTCItem]) -> DispositionRollup {
            var totalValue: Double = 0
            var notStarted = 0, hasBrief = 0, inProgress = 0, completed = 0, onHold = 0, notApplicable = 0
            var activeBriefs = 0, activePlans = 0

            for item in items {
                totalValue += effectiveTotalValueStatic(for: item)

                let state = item.liquidationState
                let status = state?.status ?? .notStarted

                switch status {
                case .notStarted: notStarted += 1
                case .hasBrief: hasBrief += 1
                case .inProgress: inProgress += 1
                case .completed: completed += 1
                case .onHold: onHold += 1
                case .notApplicable: notApplicable += 1
                }

                if state?.activeBrief != nil { activeBriefs += 1 }
                if state?.activePlan != nil { activePlans += 1 }
            }

            return DispositionRollup(
                entityCount: items.count,
                totalValue: totalValue,
                notStartedCount: notStarted,
                hasBriefCount: hasBrief,
                inProgressCount: inProgress,
                completedCount: completed,
                onHoldCount: onHold,
                notApplicableCount: notApplicable,
                activeBriefCount: activeBriefs,
                activePlanCount: activePlans
            )
        }

        private static func effectiveTotalValueForSetStatic(_ itemSet: LTCItemSet) -> Double {
            var total: Double = 0
            for m in itemSet.memberships {
                guard let item = m.item else { continue }
                let qty = Double(max(m.quantityInSet ?? item.quantity, 1))
                total += effectiveUnitValueStatic(for: item) * qty
            }
            return max(total, 0)
        }

        private static func rollupForSets(_ sets: [LTCItemSet]) -> DispositionRollup {
            var totalValue: Double = 0
            var notStarted = 0, hasBrief = 0, inProgress = 0, completed = 0, onHold = 0, notApplicable = 0
            var activeBriefs = 0, activePlans = 0

            for set in sets {
                totalValue += effectiveTotalValueForSetStatic(set)

                let state = set.liquidationState
                let status = state?.status ?? .notStarted

                switch status {
                case .notStarted: notStarted += 1
                case .hasBrief: hasBrief += 1
                case .inProgress: inProgress += 1
                case .completed: completed += 1
                case .onHold: onHold += 1
                case .notApplicable: notApplicable += 1
                }

                if state?.activeBrief != nil { activeBriefs += 1 }
                if state?.activePlan != nil { activePlans += 1 }
            }

            return DispositionRollup(
                entityCount: sets.count,
                totalValue: totalValue,
                notStartedCount: notStarted,
                hasBriefCount: hasBrief,
                inProgressCount: inProgress,
                completedCount: completed,
                onHoldCount: onHold,
                notApplicableCount: notApplicable,
                activeBriefCount: activeBriefs,
                activePlanCount: activePlans
            )
        }

        private static func rollupForBatches(_ batches: [LiquidationBatch]) -> DispositionRollup {
            var totalValue: Double = 0
            var notStarted = 0, hasBrief = 0, inProgress = 0, completed = 0, onHold = 0, notApplicable = 0
            var activeBriefs = 0, activePlans = 0

            for batch in batches {
                for bi in batch.items {
                    if let item = bi.item {
                        totalValue += effectiveTotalValueStatic(for: item)
                    }
                }
                for bs in batch.sets {
                    if let set = bs.itemSet {
                        totalValue += effectiveTotalValueForSetStatic(set)
                    }
                }

                let state = batch.liquidationState
                let status = state?.status ?? .notStarted

                switch status {
                case .notStarted: notStarted += 1
                case .hasBrief: hasBrief += 1
                case .inProgress: inProgress += 1
                case .completed: completed += 1
                case .onHold: onHold += 1
                case .notApplicable: notApplicable += 1
                }

                if state?.activeBrief != nil { activeBriefs += 1 }
                if state?.activePlan != nil { activePlans += 1 }
            }

            return DispositionRollup(
                entityCount: batches.count,
                totalValue: totalValue,
                notStartedCount: notStarted,
                hasBriefCount: hasBrief,
                inProgressCount: inProgress,
                completedCount: completed,
                onHoldCount: onHold,
                notApplicableCount: notApplicable,
                activeBriefCount: activeBriefs,
                activePlanCount: activePlans
            )
        }
    }
    // MARK: - Drawing Helpers

    @discardableResult
    private static func drawTitle(_ text: String, in rect: CGRect, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold)
        ]
        let size = text.size(withAttributes: attributes)
        let x = rect.midX - size.width / 2
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        return y + size.height
    }

    @discardableResult
    private static func drawSubheading(_ text: String, in rect: CGRect, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        let size = text.size(withAttributes: attributes)
        let x = rect.midX - size.width / 2
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        return y + size.height
    }

    @discardableResult
    private static func drawSectionHeader(_ text: String, in rect: CGRect, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ]
        let size = text.size(withAttributes: attributes)
        let x = rect.minX + 40
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        return y + size.height + 2
    }

    @discardableResult
    private static func drawBodyText(_ text: String, in rect: CGRect, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        let maxWidth = rect.width - 80
        let boundingRect = text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let textRect = CGRect(x: rect.minX + 40, y: y, width: maxWidth, height: boundingRect.height)
        (text as NSString).draw(in: textRect, withAttributes: attributes)
        return y + boundingRect.height + 2
    }

    @discardableResult
    private static func drawCaptionText(_ text: String, in rect: CGRect, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray
        ]
        let maxWidth = rect.width - 80
        let boundingRect = text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let textRect = CGRect(x: rect.minX + 40, y: y, width: maxWidth, height: boundingRect.height)
        (text as NSString).draw(in: textRect, withAttributes: attributes)
        return y + boundingRect.height + 2
    }

    /// Ensures there is enough vertical space; if not, starts a new page.
    private static func ensureSpace(
        for neededHeight: CGFloat,
        in rect: CGRect,
        context: UIGraphicsPDFRendererContext,
        currentY: CGFloat,
        onNewPage: ((CGFloat) -> Void)? = nil
    ) -> CGFloat {
        let bottomMargin: CGFloat = 40
        if currentY + neededHeight > rect.height - bottomMargin {
            context.beginPage()
            let newY: CGFloat = 40
            onNewPage?(newY)
            return newY
        }
        return currentY
    }

    private static func drawTableRow(
        name: String,
        category: String,
        path: String,
        beneficiary: String,
        quantity: String,
        unitValue: String,
        totalValue: String,
        in rect: CGRect,
        y: CGFloat,
        isHeader: Bool
    ) {
        let font = UIFont.systemFont(ofSize: 10.5, weight: isHeader ? .semibold : .regular)
        let headerColor = UIColor.black
        let textColor = isHeader ? headerColor : UIColor.darkGray

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        func draw(_ text: String, x: CGFloat, maxChars: Int) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let limited: String
            if trimmed.count > maxChars {
                let prefix = trimmed.prefix(maxChars - 1)
                limited = prefix + "…"
            } else {
                limited = trimmed
            }
            (limited as NSString).draw(
                at: CGPoint(x: x, y: y),
                withAttributes: attributes
            )
        }

        let xName: CGFloat = rect.minX + 20
        let xCategory: CGFloat = rect.minX + 210
        let xPath: CGFloat = rect.minX + 305
        let xBeneficiary: CGFloat = rect.minX + 375
        let xQty: CGFloat = rect.minX + 470
        let xUnit: CGFloat = rect.minX + 505
        let xTotal: CGFloat = rect.minX + 555

        draw(name, x: xName, maxChars: 24)
        draw(category, x: xCategory, maxChars: 12)
        draw(path, x: xPath, maxChars: 9)
        draw(beneficiary, x: xBeneficiary, maxChars: 14)
        draw(quantity, x: xQty, maxChars: 4)
        draw(unitValue, x: xUnit, maxChars: 10)
        draw(totalValue, x: xTotal, maxChars: 10)
    }

    // MARK: - Formatting Helpers

    private static func currencyString(_ value: Double) -> String {
        CurrencyFormat.dollars(value)
    }
    
    private static func percentString(_ share: Double) -> String {
        let percent = Int((share * 100).rounded())
        return "\(percent)%"
    }

    private static func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }
}
