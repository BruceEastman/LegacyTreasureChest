//
//  HowItWorksContent.swift
//  LegacyTreasureChest
//
//  Orientation copy only. No data model dependencies.
//

import Foundation

struct HowItWorksIconRow: Identifiable, Hashable {
    let id = UUID()
    let systemImage: String
    let title: String
    let body: String
}

struct HowItWorksPage: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let body: String
    let iconRows: [HowItWorksIconRow]
}

enum HowItWorksContent {
    static let pages: [HowItWorksPage] = [

        // MARK: - The Journey

        HowItWorksPage(
            title: "How the System Works",
            body: """
Legacy Treasure Chest guides you through five steps. You don't need to complete them all at once — most people work through them gradually over days or weeks.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "camera.fill",
                    title: "Capture",
                    body: "Photograph items or add them manually. Start anywhere — a single room, a cabinet, or the items you already know are valuable."
                ),
                HowItWorksIconRow(
                    systemImage: "sparkles",
                    title: "Understand",
                    body: "AI helps identify items and suggest realistic resale value ranges. These are advisory estimates, not formal appraisals."
                ),
                HowItWorksIconRow(
                    systemImage: "arrow.triangle.branch",
                    title: "Decide",
                    body: "Choose what happens to each item — keep it in the family, assign it to someone specific, or plan to sell or donate it."
                ),
                HowItWorksIconRow(
                    systemImage: "checklist",
                    title: "Execute",
                    body: "For items you plan to sell, the system helps you choose a selling strategy and generates a step-by-step checklist."
                ),
                HowItWorksIconRow(
                    systemImage: "doc.text.fill",
                    title: "Document",
                    body: "Generate clear reports for family members, executors, and professionals when you are ready to share."
                )
            ]
        ),

        // MARK: - Building Your Inventory

        HowItWorksPage(
            title: "Building Your Inventory",
            body: """
Start small. Even five or ten items gives you a feel for how the system works. You can add more anytime.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "photo.on.rectangle.angled",
                    title: "Add with Photos",
                    body: "Tap the photo icon in the Items screen to photograph one item or import several at once. AI will suggest a title, category, and value range."
                ),
                HowItWorksIconRow(
                    systemImage: "plus",
                    title: "Add Manually",
                    body: "Tap the + button to create an item without a photo. Useful for items you know well or want to record quickly."
                ),
                HowItWorksIconRow(
                    systemImage: "rectangle.stack.fill",
                    title: "Create Sets",
                    body: "Group related items — a china pattern, a jewelry collection, a closet — into a Set so they can be planned and sold together."
                ),
                HowItWorksIconRow(
                    systemImage: "waveform",
                    title: "Record Audio",
                    body: "Attach a short voice recording to any item to capture its story, history, or meaning in your own words."
                ),
                HowItWorksIconRow(
                    systemImage: "sparkles",
                    title: "Improve with AI",
                    body: "On any item, tap Improve with AI to get a better description, category, or value estimate. Adding more detail produces better results."
                )
            ]
        ),

        // MARK: - AI Valuation

        HowItWorksPage(
            title: "Understanding AI Valuation",
            body: """
The AI provides realistic resale estimates — what an item might actually sell for at an estate sale, consignment shop, or online marketplace. These are not insurance values or retail replacement costs.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "chart.bar.fill",
                    title: "You'll See a Range",
                    body: "Valuations show a low, mid, and high estimate. The midpoint is the most realistic expectation under typical conditions."
                ),
                HowItWorksIconRow(
                    systemImage: "text.bubble.fill",
                    title: "More Detail = Better Estimate",
                    body: "For jewelry, rugs, art, and luxury items, adding specifics — weight, maker, pattern name, condition — significantly improves accuracy."
                ),
                HowItWorksIconRow(
                    systemImage: "exclamationmark.triangle",
                    title: "Some Items Need a Professional",
                    body: "For high-value or rare items, the AI will tell you what additional information is needed and may suggest a formal appraisal."
                )
            ]
        ),

        // MARK: - Legacy & Beneficiaries

        HowItWorksPage(
            title: "Legacy Items & Beneficiaries",
            body: """
Some possessions belong with specific people. Assigning beneficiaries turns your inventory into a clear record of your intentions.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "person.3.fill",
                    title: "Assign a Beneficiary",
                    body: "Open any item and add a beneficiary from your list. You can assign the same person to multiple items."
                ),
                HowItWorksIconRow(
                    systemImage: "person.badge.plus",
                    title: "Add People First",
                    body: "Beneficiaries are managed in the Beneficiaries section. Add them once and they're available for any item."
                ),
                HowItWorksIconRow(
                    systemImage: "waveform",
                    title: "Add a Personal Message",
                    body: "Record a short audio message or add a written note explaining why this item belongs with this person. These details make the difference between a list and a legacy."
                )
            ]
        ),

        // MARK: - Selling & Liquidating

        HowItWorksPage(
            title: "Selling & Liquidating",
            body: """
Items without a beneficiary are assumed to be sold or donated. The system helps you choose the right approach for each item or group of items.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "sparkles",
                    title: "Get a Liquidation Brief",
                    body: "On any item marked for sale, tap Liquidate to get an AI-generated brief explaining which selling path makes the most sense and why."
                ),
                HowItWorksIconRow(
                    systemImage: "storefront.fill",
                    title: "Local Help",
                    body: "For items best handled by a local business — consignment shops, auction houses, estate sale companies — the system can identify nearby options."
                ),
                HowItWorksIconRow(
                    systemImage: "shippingbox.fill",
                    title: "Specialist Marketplaces",
                    body: "For luxury items like watches, designer handbags, and fine jewelry, specialist online platforms often return significantly better prices than local options."
                ),
                HowItWorksIconRow(
                    systemImage: "checklist",
                    title: "Follow the Checklist",
                    body: "Once you choose a selling path, the system generates a step-by-step checklist to help you or an executor carry it out."
                )
            ]
        ),

        // MARK: - Estate Reports

        HowItWorksPage(
            title: "Estate Reports & Exports",
            body: """
When you're ready to share, the system can generate organized documentation from your inventory. Exports reflect the catalog exactly as it exists at the time you generate them.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "doc.plaintext.fill",
                    title: "Estate Snapshot",
                    body: "A one-page summary of your estate — total value, category breakdown, and disposition overview. Good for an initial conversation with an attorney or advisor."
                ),
                HowItWorksIconRow(
                    systemImage: "list.bullet.rectangle.fill",
                    title: "Detailed Inventory",
                    body: "A complete item-by-item report with categories, values, and disposition decisions. Designed to be useful for executors and attorneys."
                ),
                HowItWorksIconRow(
                    systemImage: "person.text.rectangle.fill",
                    title: "Beneficiary Packet",
                    body: "A report for a specific beneficiary showing their assigned items, values, and any personal messages you've included."
                ),
                HowItWorksIconRow(
                    systemImage: "envelope.fill",
                    title: "Outreach Packet",
                    body: "A professional summary you can share with dealers, auction houses, or estate sale companies when seeking help with liquidation."
                )
            ]
        ),

        // MARK: - Privacy

        HowItWorksPage(
            title: "Your Privacy",
            body: """
Your inventory stays on your device. Legacy Treasure Chest does not store your estate information in the cloud, operate a marketplace, or manage transactions on your behalf.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "iphone",
                    title: "Stored on Your Device",
                    body: "All item data, photos, documents, and audio recordings are kept locally. Nothing is uploaded to a server."
                ),
                HowItWorksIconRow(
                    systemImage: "sparkles",
                    title: "AI Requests Are Stateless",
                    body: "When you use AI features, only the information needed for that specific request is sent for analysis. The system does not retain a history of your requests."
                ),
                HowItWorksIconRow(
                    systemImage: "hand.raised.fill",
                    title: "Advisor, Not Operator",
                    body: "The system provides guidance and generates documentation. All decisions and actions remain with you."
                )
            ]
        )
    ]
}
