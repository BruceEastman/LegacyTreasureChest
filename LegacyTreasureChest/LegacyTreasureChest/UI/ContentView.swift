//
//  ContentView.swift
//  LegacyTreasureChest
//
//  Root view that initializes the local user at launch and routes to
//  Home based on AuthenticationViewModel.launchState.
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
            switch viewModel.launchState {
            case .initializing:
                ProgressView()
                    .task {
                        await viewModel.initializeLocalUserIfNeeded()
                    }
            case .ready:
                HomeView(
                    openItemsAfterOnboarding: $openItemsAfterOnboarding,
                    onDataResetCompleted: {
                        hasSeenStartHere = false
                        showStartHere = true
                    }
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
            case .failed:
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(viewModel.errorMessage ?? "Legacy Treasure Chest couldn't open your local data. Please close and reopen the app.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
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
