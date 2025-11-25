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
    
    // MARK: - Published State
    
    /// True while a sign-in or sign-out operation is in progress.
    @Published var isBusy: Bool = false
    
    /// True when the user is currently signed in.
    @Published var isSignedIn: Bool = false
    
    /// A user-facing error message, if the last operation failed.
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let authService: AuthenticationServiceProtocol
    
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
            errorMessage = wrappedErrorMessage(from: error)
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
            errorMessage = wrappedErrorMessage(from: error)
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
            errorMessage = wrappedErrorMessage(from: error)
            print("❌ Delete account failed: \(error)")
        }
        
        isBusy = false
    }
    
    // MARK: - Helpers
    
    private func wrappedErrorMessage(from error: Error) -> String {
        if let appError = error as? LocalizedError,
           let description = appError.errorDescription {
            return description
        }
        return "Something went wrong. Please try again."
    }
}
