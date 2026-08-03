//
//  AuthenticationViewModel.swift
//  LegacyTreasureChest
//
//  View model for handling Sign in with Apple flow.
//  Bridges AuthenticationServiceProtocol to SwiftUI views.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthenticationViewModel: ObservableObject {

    // MARK: - Launch State

    /// Explicit local-user initialization state for app launch.
    enum LaunchState: Equatable {
        case initializing
        case ready
        case failed
    }

    // MARK: - Published State

    /// True while a sign-in or sign-out operation is in progress.
    @Published var isBusy: Bool = false

    /// True when the user is currently signed in.
    @Published var isSignedIn: Bool = false

    /// A user-facing error message, if the last operation failed.
    @Published var errorMessage: String?

    /// State of the one-time local-user initialization performed at launch.
    @Published private(set) var launchState: LaunchState = .initializing

    // MARK: - Dependencies

    private let authService: AuthenticationServiceProtocol

    /// Guards resolveLocalUser() from being invoked more than once, even if
    /// initializeLocalUserIfNeeded() is called repeatedly (e.g. from SwiftUI
    /// view recomputation).
    private var didAttemptLocalUserInitialization = false

    // MARK: - Init

    init(authService: AuthenticationServiceProtocol) {
        self.authService = authService

        // Initialize state based on existing session, if any.
        if authService.currentUserId != nil {
            isSignedIn = true
        } else {
            isSignedIn = false
        }
    }

    // MARK: - Intent(s)

    /// Resolves the local user exactly once per app launch. Safe to call
    /// repeatedly — only the first call performs work; later calls are
    /// no-ops. Not currently called from any view.
    func initializeLocalUserIfNeeded() async {
        guard !didAttemptLocalUserInitialization else { return }
        didAttemptLocalUserInitialization = true

        do {
            _ = try authService.resolveLocalUser()
            isSignedIn = true
            launchState = .ready
        } catch {
            launchState = .failed
            errorMessage = userFacingMessage(for: .localUserInitialization)
            print("❌ Local user initialization failed: \(error)")
        }
    }

    /// Trigger Sign in with Apple.
    func signIn() async {
        guard !isBusy else { return }
        
        isBusy = true
        errorMessage = nil
        
        do {
            _ = try await authService.signInWithApple()
            isSignedIn = true
        } catch {
            isSignedIn = false
            errorMessage = userFacingMessage(for: .signIn)
            print("❌ Sign in failed: \(error)")
        }
        
        isBusy = false
    }
    
    /// Sign out the current user (local only).
    func signOut() async {
        guard !isBusy else { return }
        
        isBusy = true
        errorMessage = nil
        
        do {
            try await authService.signOut()
            isSignedIn = false
        } catch {
            errorMessage = userFacingMessage(for: .signOut)
            print("❌ Sign out failed: \(error)")
        }
        
        isBusy = false
    }
    
    /// Delete the current user's account and all related data.
    func deleteAccount() async {
        guard !isBusy else { return }
        
        isBusy = true
        errorMessage = nil
        
        do {
            try await authService.deleteAccount()
            isSignedIn = false
        } catch {
            errorMessage = userFacingMessage(for: .deleteAccount)
            print("❌ Delete account failed: \(error)")
        }
        
        isBusy = false
    }
    
    // MARK: - Helpers
    
    private enum AuthAction {
        case signIn
        case signOut
        case deleteAccount
        case localUserInitialization
    }

    private func userFacingMessage(for action: AuthAction) -> String {
        switch action {
        case .signIn:
            return "Sorry, we couldn’t sign you in. Please try again."
        case .signOut:
            return "Sorry, we couldn’t sign you out. Please try again."
        case .deleteAccount:
            return "Sorry, we couldn’t delete your account. Please try again."
        case .localUserInitialization:
            return "Legacy Treasure Chest couldn't open your local data. Please close and reopen the app."
        }
    }
}
