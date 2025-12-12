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
        beneficiaries: [Beneficiary]
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var cursorY: CGFloat = 40

            // Header
            cursorY = drawTitle("Estate Snapshot Report", in: pageRect, y: cursorY)
            cursorY += 6
            cursorY = drawSubheading(currentDateString(), in: pageRect, y: cursorY)
            cursorY += 24

            // Compute aggregates once
            let aggregates = EstateAggregates(items: items, beneficiaries: beneficiaries)

            // Estate Summary
            cursorY = ensureSpace(for: 120, in: pageRect, context: context, currentY: cursorY)
            cursorY = drawSectionHeader("Estate Summary", in: pageRect, y: cursorY)
            cursorY += 4

            let summaryLines = [
                "Total estate (conservative sale value): \(currencyString(aggregates.totalEstateValue))",
                "Total items: \(aggregates.totalItems)",
                "Legacy items: \(aggregates.legacyItemCount) (\(percentString(aggregates.legacyValueShare)) of value)",
                "Liquidate items: \(aggregates.liquidateItemCount) (\(percentString(aggregates.liquidateValueShare)) of value)"
            ]

            for line in summaryLines {
                cursorY = drawBodyText(line, in: pageRect, y: cursorY)
            }

            cursorY += 8
            cursorY = drawCaptionText(
                "Items without a named beneficiary are treated as Liquidate items—sold, with proceeds handled by the will or estate plan.",
                in: pageRect,
                y: cursorY
            )

            // Beneficiaries (Legacy only)
            if !aggregates.beneficiarySummaries.isEmpty {
                cursorY += 20
                cursorY = ensureSpace(for: CGFloat(40 + aggregates.beneficiarySummaries.count * 20),
                                      in: pageRect,
                                      context: context,
                                      currentY: cursorY)
                cursorY = drawSectionHeader("Legacy by Beneficiary", in: pageRect, y: cursorY)
                cursorY += 4

                for summary in aggregates.beneficiarySummaries {
                    let line = "\(summary.name): \(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s") · \(currencyString(summary.totalValue))"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }

            // Categories
            if !aggregates.categorySummaries.isEmpty {
                cursorY += 20
                cursorY = ensureSpace(for: CGFloat(40 + aggregates.categorySummaries.count * 20),
                                      in: pageRect,
                                      context: context,
                                      currentY: cursorY)
                cursorY = drawSectionHeader("Value by Category", in: pageRect, y: cursorY)
                cursorY += 4

                for summary in aggregates.categorySummaries {
                    let displayName = summary.name.isEmpty ? "Uncategorized" : summary.name
                    let line = "\(displayName): \(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s") · \(currencyString(summary.totalValue))"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }

            // Top Legacy Items
            if !aggregates.topLegacyItems.isEmpty {
                cursorY += 20
                cursorY = ensureSpace(for: CGFloat(80 + aggregates.topLegacyItems.count * 20),
                                      in: pageRect,
                                      context: context,
                                      currentY: cursorY)
                cursorY = drawSectionHeader("Top Legacy Items by Value", in: pageRect, y: cursorY)
                cursorY += 4

                for item in aggregates.topLegacyItems {
                    let value = currencyString(aggregates.effectiveValue(for: item))
                    let line = "• \(item.name) (\(item.category)) – \(value)"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }

            // Top Liquidate Items
            if !aggregates.topLiquidateItems.isEmpty {
                cursorY += 20
                cursorY = ensureSpace(for: CGFloat(80 + aggregates.topLiquidateItems.count * 20),
                                      in: pageRect,
                                      context: context,
                                      currentY: cursorY)
                cursorY = drawSectionHeader("Top Liquidate Items by Value", in: pageRect, y: cursorY)
                cursorY += 4

                for item in aggregates.topLiquidateItems {
                    let value = currencyString(aggregates.effectiveValue(for: item))
                    let line = "• \(item.name) (\(item.category)) – \(value)"
                    cursorY = drawBodyText(line, in: pageRect, y: cursorY)
                }
            }
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

            let aggregates = EstateAggregates(items: items, beneficiaries: [])

            // Header
            cursorY = drawTitle("Detailed Inventory Report", in: pageRect, y: cursorY)
            cursorY += 6
            cursorY = drawSubheading(currentDateString(), in: pageRect, y: cursorY)
            cursorY += 16

            cursorY = drawCaptionText(
                "This report lists all cataloged items with their category, estate path (Legacy or Liquidate), first beneficiary (if any), and conservative sale value.",
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
                    value: "Value",
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
                // New page if needed
                cursorY = ensureSpace(for: 22, in: pageRect, context: context, currentY: cursorY) { newY in
                    // On new page, redraw table header
                    drawTableHeader(at: newY)
                }

                let path = aggregates.isLegacy(item) ? "Legacy" : "Liquidate"
                let beneficiaryName = item.itemBeneficiaries.first?.beneficiary?.name ?? ""
                let value = currencyString(aggregates.effectiveValue(for: item))

                drawTableRow(
                    name: item.name,
                    category: item.category,
                    path: path,
                    beneficiary: beneficiaryName,
                    value: value,
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
        let beneficiaries: [Beneficiary]

        let totalItems: Int
        let totalEstateValue: Double

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

        init(items: [LTCItem], beneficiaries: [Beneficiary]) {
            self.items = items
            self.beneficiaries = beneficiaries

            self.totalItems = items.count
            self.totalEstateValue = items.reduce(0) { $0 + Self.effectiveValueStatic(for: $1) }

            self.legacyItems = items.filter { !$0.itemBeneficiaries.isEmpty }
            self.liquidateItems = items.filter { $0.itemBeneficiaries.isEmpty }

            self.legacyItemCount = legacyItems.count
            self.liquidateItemCount = liquidateItems.count

            self.legacyValue = legacyItems.reduce(0) { $0 + Self.effectiveValueStatic(for: $1) }
            self.liquidateValue = liquidateItems.reduce(0) { $0 + Self.effectiveValueStatic(for: $1) }

            let denominator = max(totalEstateValue, 0.01)
            self.legacyValueShare = legacyValue / denominator
            self.liquidateValueShare = liquidateValue / denominator

            // Beneficiary summaries – only Legacy items
            self.beneficiarySummaries = beneficiaries.compactMap { beneficiary in
                let ownedLegacyItems = items.filter { item in
                    item.itemBeneficiaries.contains { $0.beneficiary === beneficiary }
                }
                guard !ownedLegacyItems.isEmpty else { return nil }

                let value = ownedLegacyItems.reduce(0) { $0 + Self.effectiveValueStatic(for: $1) }
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
                let totalValue = itemsInCategory.reduce(0) { $0 + Self.effectiveValueStatic(for: $1) }
                return CategorySummary(
                    name: category,
                    itemCount: itemsInCategory.count,
                    totalValue: totalValue
                )
            }
            .sorted { $0.totalValue > $1.totalValue }

            // Top items by value
            let sortedByValue = items.sorted {
                Self.effectiveValueStatic(for: $0) > Self.effectiveValueStatic(for: $1)
            }

            self.topLegacyItems = Array(sortedByValue.filter { !$0.itemBeneficiaries.isEmpty }.prefix(5))
            self.topLiquidateItems = Array(sortedByValue.filter { $0.itemBeneficiaries.isEmpty }.prefix(5))
        }

        func effectiveValue(for item: LTCItem) -> Double {
            Self.effectiveValueStatic(for: item)
        }

        func isLegacy(_ item: LTCItem) -> Bool {
            !item.itemBeneficiaries.isEmpty
        }

        private static func effectiveValueStatic(for item: LTCItem) -> Double {
            if let estimated = item.valuation?.estimatedValue, estimated > 0 {
                return estimated
            }
            return max(item.value, 0)
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
        value: String,
        in rect: CGRect,
        y: CGFloat,
        isHeader: Bool
    ) {
        let font = UIFont.systemFont(ofSize: 11, weight: isHeader ? .semibold : .regular)
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

        let xName: CGFloat = rect.minX + 32
        let xCategory: CGFloat = rect.minX + 220
        let xPath: CGFloat = rect.minX + 320
        let xBeneficiary: CGFloat = rect.minX + 400
        let xValue: CGFloat = rect.minX + 520

        draw(name, x: xName, maxChars: 22)
        draw(category, x: xCategory, maxChars: 14)
        draw(path, x: xPath, maxChars: 9)
        draw(beneficiary, x: xBeneficiary, maxChars: 14)
        draw(value, x: xValue, maxChars: 12)
    }

    // MARK: - Formatting Helpers

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()

    private static func currencyString(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
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
