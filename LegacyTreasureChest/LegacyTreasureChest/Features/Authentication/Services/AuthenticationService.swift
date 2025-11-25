//
//  AuthenticationService.swift
//  LegacyTreasureChest
//
//  Implements Sign in with Apple authentication and user provisioning.
//  Creates or fetches LTCUser in SwiftData.
//  iOS 18.0+, Swift 6 concurrency.
//

import Foundation
import AuthenticationServices
import SwiftData

// MARK: - Authentication Service Implementation

@MainActor
final class AuthenticationService: NSObject, AuthenticationServiceProtocol {
    
    private let modelContext: ModelContext
    
    // Currently authenticated user ID (loaded after sign-in)
    private(set) var currentUserId: UUID?
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
    }
    
    // MARK: - Sign in with Apple
    
    func signInWithApple() async throws -> UUID {
        print("🔐 Starting Sign in with Apple…")
        
        let credential = try await performAppleSignInRequest()
        
        let userIdentifier = credential.user
        
        // Try to fetch an existing LTCUser with this Apple ID
        if let existing = try fetchUser(appleUserIdentifier: userIdentifier) {
            print("👤 Existing user found: \(existing.userId)")
            currentUserId = existing.userId
            return existing.userId
        }
        
        // Otherwise create a new LTCUser
        let newUser = LTCUser(
            appleUserIdentifier: userIdentifier,
            email: credential.email,
            name: credential.fullName?.givenName
        )
        
        modelContext.insert(newUser)
        
        do {
            try modelContext.save()
        } catch {
            throw AppError.dataError("Failed to save new user: \(error.localizedDescription)")
        }
        
        print("🆕 Created new LTCUser: \(newUser.userId)")
        currentUserId = newUser.userId
        return newUser.userId
    }
    
    // MARK: - Sign Out
    
    func signOut() async throws {
        print("🚪 Signing out user")
        currentUserId = nil
    }
    
    // MARK: - Delete Account
    
    func deleteAccount() async throws {
        guard let userId = currentUserId else {
            throw AppError.authenticationFailed("No authenticated user")
        }
        
        print("🗑️ Deleting user account…")
        
        let descriptor = FetchDescriptor<LTCUser>(
            predicate: #Predicate { $0.userId == userId }
        )
        
        guard let user = try modelContext.fetch(descriptor).first else {
            throw AppError.resourceNotFound("User not found")
        }
        
        modelContext.delete(user)
        
        do {
            try modelContext.save()
        } catch {
            throw AppError.dataError("Failed to delete user: \(error.localizedDescription)")
        }
        
        currentUserId = nil
        print("🗑️ User deleted successfully")
    }
    
    // MARK: - Private Helpers
    
    private func fetchUser(appleUserIdentifier: String) throws -> LTCUser? {
        let descriptor = FetchDescriptor<LTCUser>(
            predicate: #Predicate { $0.appleUserIdentifier == appleUserIdentifier }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    // MARK: - Apple Sign In Request (async/await)
    
    private func performAppleSignInRequest() async throws -> ASAuthorizationAppleIDCredential {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        
        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            controller.performRequests()
        }
    }
    
    // Temporary continuation holder
    private var signInContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationService: ASAuthorizationControllerDelegate {
    
    @MainActor
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            signInContinuation?.resume(throwing: AppError.authenticationFailed("Invalid credentials received"))
            signInContinuation = nil
            return
        }
        
        signInContinuation?.resume(returning: credential)
        signInContinuation = nil
    }
    
    @MainActor
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        signInContinuation?.resume(throwing: AppError.authenticationFailed(error.localizedDescription))
        signInContinuation = nil
    }
}

