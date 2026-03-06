//
//  ContentView.swift
//  LegacyTreasureChest
//
//  Root view that switches between Authentication and Home
//  based on the AuthenticationViewModel state.
//

import SwiftUI

struct ContentView: View {
    /// Shared authentication view model injected from the App entry point.
    @ObservedObject var viewModel: AuthenticationViewModel

    // First-launch onboarding gate (shown only after sign-in).
    @AppStorage("hasSeenStartHere") private var hasSeenStartHere: Bool = false
    @State private var showStartHere: Bool = false
    @State private var openItemsAfterOnboarding: Bool = false

    var body: some View {
        NavigationStack {
            if viewModel.isSignedIn {
                HomeView(
                    onSignOut: {
                        Task {
                            await viewModel.signOut()
                        }
                    },
                    openItemsAfterOnboarding: $openItemsAfterOnboarding
                )
                .onAppear {
                    if !hasSeenStartHere {
                        showStartHere = true
                    }
                }
                .onChange(of: viewModel.isSignedIn) { _, isSignedIn in
                    if isSignedIn && !hasSeenStartHere {
                        showStartHere = true
                    }
                }
                .fullScreenCover(isPresented: $showStartHere) {
                    StartHereOnboardingView(
                        onFinish: {
                            hasSeenStartHere = true
                            showStartHere = false
                        },
                        onAddFirstItem: {
                            hasSeenStartHere = true
                            openItemsAfterOnboarding = true
                            showStartHere = false
                        }
                    )
                }
            } else {
                AuthenticationView(viewModel: viewModel)
                    .onAppear {
                        showStartHere = false
                        openItemsAfterOnboarding = false
                    }
            }
        }
    }
}

#Preview {
    let mockService = PreviewAuthService()
    let vm = AuthenticationViewModel(authService: mockService)

    return ContentView(viewModel: vm)
}

// MARK: - Preview Support

final class PreviewAuthService: AuthenticationServiceProtocol {
    var currentUserId: UUID? = UUID()

    func signInWithApple() async throws -> UUID {
        let id = UUID()
        currentUserId = id
        return id
    }

    func signOut() async throws {
        currentUserId = nil
    }

    func deleteAccount() async throws {
        currentUserId = nil
    }
}
