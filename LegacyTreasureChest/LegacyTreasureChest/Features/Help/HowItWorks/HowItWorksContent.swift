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
        HowItWorksPage(
            title: "Start Here",
            body: """
Legacy Treasure Chest helps you organize and plan the future of the possessions in your home.

Most households accumulate a lifetime of possessions — furniture, collections, jewelry, tools, clothing, and thousands of everyday items.

When the time comes to downsize or settle an estate, families are often left guessing:
• what exists
• what items are worth
• who should receive them
• how items should be sold

Legacy Treasure Chest brings structure and clarity to the physical estate.

The system guides you through a simple journey:
Capture → Understand → Decide → Execute → Document

Along the way it helps answer four important questions:
• What do we have?
• What is it worth?
• What should happen to it?
• What does the executor need?

Start by adding a few items and exploring the system.
""",
            iconRows: []
        ),

        HowItWorksPage(
            title: "The Estate Journey",
            body: """
Legacy Treasure Chest is designed around a simple process for understanding and planning the future of the possessions in your home.

Capture
Photograph and record items in your household.

Understand
AI helps identify items and provides resale-oriented value ranges. These are advisory estimates, not formal appraisals.

Decide
Choose what should happen to each item:
• keep it in the estate
• assign a beneficiary
• sell or liquidate it (or donate it)

Execute
If you decide to sell an item, the system helps you plan how to do it. For many items, the best approach is to sell it yourself locally or online. For higher-value or specialized items, other strategies may be more appropriate. Once you choose a strategy, the system generates a checklist.

Document
Generate clear reports that make the estate easier for others to understand and manage.
""",
            iconRows: []
        ),

        HowItWorksPage(
            title: "Building Your Inventory",
            body: """
Your inventory is the foundation of the system.

Start by photographing items or adding them manually. The system can help suggest categories and estimated resale ranges.

As you catalog items, you can organize them into Sets or groupings so the estate is easier to understand (collections, matched pieces, room groupings, and similar groupings).

You can also attach documents, additional photos, and audio recordings so important details are not lost.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "photo",
                    title: "Add with Photos",
                    body: "Photograph an item and let the app help identify it and preserve visual detail."
                ),
                HowItWorksIconRow(
                    systemImage: "plus",
                    title: "Add Items",
                    body: "Use the + button to create an item manually when you do not have a photo."
                ),
                HowItWorksIconRow(
                    systemImage: "sparkles",
                    title: "Improve with AI",
                    body: "AI can help refine categories, descriptions, and value guidance."
                ),
                HowItWorksIconRow(
                    systemImage: "waveform",
                    title: "Record Audio",
                    body: "Capture the story, history, or meaning of an item in your own voice."
                )
            ]
        ),

        HowItWorksPage(
            title: "Legacy & Beneficiaries",
            body: """
Some possessions belong with specific people.

Legacy Treasure Chest allows you to assign beneficiaries to items or collections so that your intentions are clearly recorded.

You can include notes or record short audio messages in your own voice describing the story or significance of the item. This helps turn a simple inventory into meaningful guidance for the next generation.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "person.3.fill",
                    title: "Assign Beneficiaries",
                    body: "Record who should receive important items or collections."
                ),
                HowItWorksIconRow(
                    systemImage: "waveform",
                    title: "Add Personal Context",
                    body: "Use audio to explain why an item matters or share its history in your own words."
                )
            ]
        ),

        HowItWorksPage(
            title: "Selling & Liquidating",
            body: """
If you decide to sell an item, Legacy Treasure Chest helps determine the most practical way to do it.

For many items, the best approach is simply to sell the item yourself locally or online. The system can help you organize the steps required to complete the sale.

For higher-value or specialized items, other strategies may be more appropriate, including dealers, consignment shops, auction houses, or estate sale groupings.

Once you choose a strategy, the system generates a checklist to help you carry it out.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "sparkles",
                    title: "Get AI Guidance",
                    body: "Use AI guidance to understand which selling path is most practical for the item."
                ),
                HowItWorksIconRow(
                    systemImage: "person.2.wave.2",
                    title: "Find Local Help",
                    body: "When needed, identify local businesses that may be able to help with the sale."
                )
            ]
        ),

        HowItWorksPage(
            title: "Estate Reports",
            body: """
As your inventory grows and decisions are made, the system can generate organized documentation describing the physical estate.

These reports help others understand the estate clearly and may include:
• estate summaries
• detailed inventories
• beneficiary reports
• outreach packets for professionals
• executor documentation

Exports reflect the catalog exactly as it exists at the time you generate them.
""",
            iconRows: [
                HowItWorksIconRow(
                    systemImage: "square.and.arrow.up",
                    title: "Share or Export",
                    body: "Generate reports and packets when you are ready to share clear documentation with others."
                )
            ]
        ),

        HowItWorksPage(
            title: "Privacy",
            body: """
Legacy Treasure Chest is designed as a private advisory system.

Your inventory remains stored on your device. The application does not operate as a marketplace and does not manage transactions.

When AI assistance is used, only the information required for that specific request is sent for analysis according to the provider’s data handling policies.

The goal is to help you organize and understand your household possessions while keeping control of your information.
""",
            iconRows: []
        )
    ]
}
