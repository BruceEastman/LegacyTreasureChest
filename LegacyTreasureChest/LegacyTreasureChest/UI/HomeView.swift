//
//  HomeView.swift
//  LegacyTreasureChest
//
//  Simple home screen shown after successful sign-in.
//  Now includes navigation into the Items list.
//  Phase 1C baseline.
//

import SwiftUI

struct HomeView: View {
    /// Called when the user taps "Sign Out".
    let onSignOut: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App icon / visual anchor
                Image(systemName: "shippingbox.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .padding(.top, 60)

                // Headline
                Text("Welcome to Legacy Treasure Chest")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Subheadline
                Text("Next we’ll start cataloging your items, photos, and audio stories.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // MARK: – Navigation into Items

                NavigationLink {
                    ItemsListView()
                } label: {
                    Text("View Your Items")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)

                // MARK: – Sign Out

                Button {
                    onSignOut()
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HomeView(onSignOut: { })
    }
}
