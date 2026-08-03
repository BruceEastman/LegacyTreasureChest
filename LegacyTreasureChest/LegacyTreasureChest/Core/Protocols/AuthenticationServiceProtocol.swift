//
//  AuthenticationServiceProtocol.swift
//  LegacyTreasureChest
//
//  Abstraction for the authentication service.
//  Implemented by AuthenticationService and used by view models.
//

import Foundation

/// Authentication service handles Sign in with Apple and user lifecycle.
protocol AuthenticationServiceProtocol: AnyObject {
    /// The currently authenticated user's ID, if any.
    var currentUserId: UUID? { get }
    
    /// Perform Sign in with Apple and return the user's UUID.
    func signInWithApple() async throws -> UUID
    
    /// Sign out the current user (local only).
    func signOut() async throws
    
    /// Delete the current user's account and all related data.
    func deleteAccount() async throws

    /// Resolve a local user without requiring Sign in with Apple.
    /// Reuses an existing LTCUser if one exists, otherwise creates one.
    func resolveLocalUser() throws -> UUID
}

// MARK: - Default Implementation

extension AuthenticationServiceProtocol {
    /// Default implementation for conformers that don't provide their own
    /// (e.g. preview/mock services). Returns the existing currentUserId if
    /// one is already set; otherwise throws rather than fabricating a user,
    /// since a default implementation has no way to create or persist one.
    /// AuthenticationService.resolveLocalUser() overrides this with the
    /// real fetch-or-create implementation.
    func resolveLocalUser() throws -> UUID {
        if let currentUserId {
            return currentUserId
        }
        throw AppError.authenticationFailed("No local user available")
    }
}
