//
//  OutreachPacketPDFRenderer.swift
//  LegacyTreasureChest
//
//  Renders Outreach Packet PDF (on-device).
//  v1: Cover page + sets/items listing + Audio Appendix + Documents Appendix.
//

import Foundation
import UIKit

enum OutreachPacketPDFRenderer {

    static func render(snapshot: OutreachPacketSnapshot) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var cursorY: CGFloat = 40

            // Cover
            cursorY = drawTitle("Outreach Packet", in: pageRect, y: cursorY)
            cursorY += 6
            cursorY = drawSubheading(dateString(snapshot.generatedAt), in: pageRect, y: cursorY)
            cursorY += 16

            cursorY = drawBodyText("Target: \(snapshot.targetDisplayName)", in: pageRect, y: cursorY)
            cursorY += 10

            cursorY = drawSectionHeader("Packet Summary", in: pageRect, y: cursorY)
            cursorY += 4
            cursorY = drawBodyText("Sets: \(snapshot.setCount)", in: pageRect, y: cursorY)
            cursorY = drawBodyText("Loose Items: \(snapshot.looseItemCount)", in: pageRect, y: cursorY)
            cursorY = drawBodyText("Total Value (Range): \(rangeString(snapshot.packetValueRange))", in: pageRect, y: cursorY)
            cursorY += 10

            cursorY = drawCaptionText(
                "Values shown are advisory estimates for discussion purposes and are not guarantees of sale price.",
                in: pageRect,
                y: cursorY
            )
            cursorY += 18

            // Sets
            if !snapshot.sets.isEmpty {
                cursorY = ensureSpace(for: 40, in: pageRect, context: context, currentY: cursorY)
                cursorY = drawSectionHeader("Sets", in: pageRect, y: cursorY)
                cursorY += 6

                for set in snapshot.sets {
                    cursorY = ensureSpace(for: 120, in: pageRect, context: context, currentY: cursorY)
                    cursorY = drawBodyText("\(set.name) — \(rangeString(set.valueRange))", in: pageRect, y: cursorY)

                    if !set.description.isEmpty {
                        cursorY = drawCaptionText(set.description, in: pageRect, y: cursorY)
                    }
                    cursorY = drawCaptionText("Items: \(set.itemCount)", in: pageRect, y: cursorY)
                    cursorY += 4

                    for item in set.items {
                        cursorY = ensureSpace(for: 86, in: pageRect, context: context, currentY: cursorY)
                        cursorY = drawItemLine(item, in: pageRect, y: cursorY)
                    }

                    cursorY += 10
                }
            }

            // Loose Items
            if !snapshot.looseItems.isEmpty {
                cursorY = ensureSpace(for: 40, in: pageRect, context: context, currentY: cursorY)
                cursorY = drawSectionHeader("Loose Items", in: pageRect, y: cursorY)
                cursorY += 6

                for item in snapshot.looseItems {
                    cursorY = ensureSpace(for: 86, in: pageRect, context: context, currentY: cursorY)
                    cursorY = drawItemLine(item, in: pageRect, y: cursorY)
                }
            }

            // Audio Appendix
            if !snapshot.audioIndex.isEmpty {
                cursorY = ensureSpace(for: 90, in: pageRect, context: context, currentY: cursorY)
                cursorY += 12
                cursorY = drawSectionHeader("Audio Appendix", in: pageRect, y: cursorY)
                cursorY += 4

                cursorY = drawCaptionText(
                    "Audio files are included in the bundle under /Audio. Filenames are referenced below.",
                    in: pageRect,
                    y: cursorY
                )
                cursorY += 6

                for ref in snapshot.audioIndex {
                    cursorY = ensureSpace(for: 70, in: pageRect, context: context, currentY: cursorY)

                    let duration = durationString(ref.duration)
                    cursorY = drawBodyText("• \(ref.itemName) (\(duration))", in: pageRect, y: cursorY)
                    cursorY = drawCaptionText("File: \(ref.bundleFilename)", in: pageRect, y: cursorY)

                    if let summary = ref.summaryText, !summary.isEmpty {
                        cursorY = drawCaptionText("Owner’s Note (AI Summary): \(summary)", in: pageRect, y: cursorY)
                    }

                    cursorY += 4
                }
            }

            // Documents Appendix
            if !snapshot.documentIndex.isEmpty {
                cursorY = ensureSpace(for: 90, in: pageRect, context: context, currentY: cursorY)
                cursorY += 12
                cursorY = drawSectionHeader("Documents Appendix", in: pageRect, y: cursorY)
                cursorY += 4

                cursorY = drawCaptionText(
                    "Documents are included in the bundle under /Documents. Filenames are referenced below.",
                    in: pageRect,
                    y: cursorY
                )
                cursorY += 6

                for ref in snapshot.documentIndex {
                    cursorY = ensureSpace(for: 58, in: pageRect, context: context, currentY: cursorY)

                    let type = ref.documentType.isEmpty ? "Document" : ref.documentType
                    cursorY = drawBodyText("• \(ref.itemName) (\(type))", in: pageRect, y: cursorY)
                    cursorY = drawCaptionText("File: \(ref.bundleFilename)", in: pageRect, y: cursorY)

                    if let original = ref.originalFilename, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        cursorY = drawCaptionText("Original: \(original)", in: pageRect, y: cursorY)
                    }

                    cursorY += 4
                }
            }

            // Footer (last page)
            drawFooter(in: pageRect, generatedAt: snapshot.generatedAt)
        }

        return data
    }

    private static func drawItemLine(_ item: OutreachItemSnapshot, in rect: CGRect, y: CGFloat) -> CGFloat {
        var cursorY = y
        cursorY = drawBodyText("• \(item.name) — \(rangeString(item.valueRange))", in: rect, y: cursorY)

        let metaParts: [String] = [
            item.category.isEmpty ? nil : item.category,
            item.quantity > 1 ? "Qty \(item.quantity)" : nil,
            item.hasAudio ? "Audio included" : nil,
            item.hasDocuments ? "Document included" : nil
        ].compactMap { $0 }

        if !metaParts.isEmpty {
            cursorY = drawCaptionText(metaParts.joined(separator: " · "), in: rect, y: cursorY)
        }

        if let note = item.ownerNoteSummary, !note.isEmpty {
            cursorY = drawCaptionText("Owner’s Note (AI Summary): \(note)", in: rect, y: cursorY)
        }

        return cursorY + 2
    }

    private static func drawFooter(in rect: CGRect, generatedAt: Date) {
        let footer = "Generated on-device · Outreach Packet v1 · \(dateString(generatedAt))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray
        ]
        let maxWidth = rect.width - 80
        let textRect = CGRect(x: rect.minX + 40, y: rect.maxY - 28, width: maxWidth, height: 14)
        (footer as NSString).draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - Drawing helpers (mirrors EstateReportGenerator style)

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

    // MARK: - Formatting

    private static func rangeString(_ range: OutreachValueRange) -> String {
        if range.isEmpty { return "$0–$0" }
        return "\(currencyString(range.low))–\(currencyString(range.high))"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()

    private static func currencyString(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func durationString(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let m = s / 60
        let r = s % 60
        if m > 0 {
            return "\(m)m \(r)s"
        } else {
            return "\(r)s"
        }
    }
}
