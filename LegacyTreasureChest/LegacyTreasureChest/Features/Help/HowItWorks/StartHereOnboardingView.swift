//
//  StartHereOnboardingView.swift
//  LegacyTreasureChest
//
//  First-launch orientation (mental model builder).
//  Skippable. Always re-accessible from Help → How It Works → Start Here.
//

import SwiftUI

struct StartHereOnboardingView: View {

    let onFinish: () -> Void
    let onAddFirstItem: () -> Void

    @State private var pageIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {

            headerBar

            TabView(selection: $pageIndex) {

                situationPage
                    .tag(0)

                fourQuestionsPage
                    .tag(1)

                journeyPage
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            footerBar
        }
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Start Here")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)

            Spacer()

            Button("Skip") {
                onFinish()
            }
            .font(Theme.secondaryFont.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.spacing.xl)
        .padding(.vertical, Theme.spacing.medium)
    }

    // MARK: - Pages

    private var situationPage: some View {
        StartHerePageView(
            title: "What happens to everything in your home?",
            bodyText: """
Most households accumulate a lifetime of possessions — furniture, collections, jewelry, tools, clothing, and thousands of everyday items.

When the time comes to downsize or settle an estate, families are often left guessing:
• what exists
• what items are worth
• who should receive them
• how items should be sold

Legacy Treasure Chest was built to bring structure and clarity to the physical estate.
""",
            systemImage: "house.fill"
        )
    }

    private var fourQuestionsPage: some View {
        StartHerePageView(
            title: "Four questions we help you answer",
            bodyText: """
What do we have?
Capture possessions using photos and simple notes.

What is it worth?
Receive advisory resale value ranges based on real-world markets.

What should happen to it?
Choose whether items stay in the family or are sold (or donated).

What does the executor need?
Generate clear reports for family members, executors, and professionals.
""",
            systemImage: "questionmark.circle"
        )
    }

    private var journeyPage: some View {
        StartHerePageView(
            title: "From inventory to action",
            bodyText: """
Legacy Treasure Chest guides you through a simple journey:

Capture → Understand → Decide → Execute → Document

Everything remains privately stored on your device. The system acts as an advisor, not an operator.

Start by adding a few items to begin building your inventory.
""",
            systemImage: "arrow.triangle.branch",
            showsPrimaryAction: true,
            onPrimaryAction: onAddFirstItem
        )
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: Theme.spacing.medium) {

            Button {
                withAnimation {
                    pageIndex = max(0, pageIndex - 1)
                }
            } label: {
                Text("Back")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(pageIndex == 0 ? Theme.textSecondary : Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing.medium)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(pageIndex == 0)
            .opacity(pageIndex == 0 ? 0.55 : 1.0)

            Button {
                if pageIndex < 2 {
                    withAnimation {
                        pageIndex += 1
                    }
                } else {
                    onFinish()
                }
            } label: {
                Text(pageIndex < 2 ? "Next" : "Explore the App")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing.medium)
                    .background(Theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, Theme.spacing.xl)
        .padding(.vertical, Theme.spacing.large)
    }
}

private struct StartHerePageView: View {

    let title: String
    let bodyText: String
    let systemImage: String
    var showsPrimaryAction: Bool = false
    var onPrimaryAction: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.spacing.small)

                Text(title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)

                Text(bodyText)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                if showsPrimaryAction, let onPrimaryAction {
                    Button {
                        onPrimaryAction()
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Your First Item")
                        }
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing.medium)
                        .background(Theme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, Theme.spacing.small)
                }

                Spacer(minLength: Theme.spacing.large)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.large)
        }
    }
}
