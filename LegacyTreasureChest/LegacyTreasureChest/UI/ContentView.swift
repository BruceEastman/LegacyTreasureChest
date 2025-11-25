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

    var body: some View {
        NavigationStack {
            if viewModel.isSignedIn {
                // User is signed in → show Home
                HomeView {
                    // Sign-out action
                    Task {
                        await viewModel.signOut()
                    }
                }
            } else {
                // Not signed in → show authentication screen
                AuthenticationView(viewModel: viewModel)
            }
        }
    }
}

#Preview {
    // Simple preview stub – not using real auth service here.
    let mockService = PreviewAuthService()
    let vm = AuthenticationViewModel(authService: mockService)

    return ContentView(viewModel: vm)
}
// MARK: - Preview Support

/// Lightweight preview auth service so Xcode previews compile.
/// This is not used in the real app.
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
