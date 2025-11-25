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
}
