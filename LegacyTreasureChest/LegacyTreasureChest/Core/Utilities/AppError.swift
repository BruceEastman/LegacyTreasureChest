//
//  AppError.swift
//  LegacyTreasureChest
//
//  Standard error types for consistent error handling across the app.
//

import Foundation

enum AppError: LocalizedError, Sendable {
    case authenticationFailed(String)
    case dataError(String)
    case networkError(String)
    case cloudKitError(String)
    case audioError(String)
    case transcriptionError(String)
    case imageProcessingError(String)
    case validationError(String)
    case permissionDenied(String)
    case resourceNotFound(String)
    case marketplaceError(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Sign in failed: \(message)"
        case .dataError(let message):
            return "Unable to process data: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .cloudKitError(let message):
            return "iCloud sync error: \(message)"
        case .audioError(let message):
            return "Audio error: \(message)"
        case .transcriptionError(let message):
            return "Transcription failed: \(message)"
        case .imageProcessingError(let message):
            return "Image processing failed: \(message)"
        case .validationError(let message):
            return "Invalid input: \(message)"
        case .permissionDenied(let message):
            return "Access denied: \(message)"
        case .resourceNotFound(let message):
            return "Not found: \(message)"
        case .marketplaceError(let message):
            return "Marketplace error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authenticationFailed:
            return "Please try signing in again."
        case .permissionDenied:
            return "Please grant the required permissions in Settings."
        case .networkError:
            return "Please check your internet connection."
        case .audioError:
            return "Please check microphone permissions."
        case .transcriptionError:
            return "Transcription requires supported hardware and iOS 18+."
        default:
            return "Please try again or contact support if the problem persists."
        }
    }
}
