//
//  MediaStorage.swift
//  LegacyTreasureChest
//
//  Centralized media file management.
//  Handles storage and retrieval of images, audio recordings, and documents.
//

import Foundation
import UIKit

/// MediaStorage is responsible for organizing and managing all
/// file-based media used by the app (images, audio, documents).
///
/// Design:
/// - SwiftData stores only metadata (relative file paths, durations, etc.)
/// - The file system stores the actual binary data.
/// - All paths exposed to the rest of the app are *relative* paths,
///   so the physical root can change if needed without schema changes.
enum MediaStorage {
    
    // MARK: - Directory Structure
    
    /// Base directory for all app media under Application Support.
    static let baseDirectory: URL = {
        let fm = FileManager.default
        
        let appSupport = fm.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask).first!
        
        let appDirectory = appSupport.appendingPathComponent(
            "LegacyTreasureChest",
            isDirectory: true
        )
        
        // Create base directory if needed.
        if !fm.fileExists(atPath: appDirectory.path) {
            do {
                try fm.createDirectory(at: appDirectory,
                                       withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create base media directory: \(error)")
            }
        }
        
        return appDirectory
    }()
    
    /// Subdirectories for different media types.
    /// These are `internal` so MediaCleaner can reuse them.
    static let imagesDirectory =
        baseDirectory.appendingPathComponent("Media/Images", isDirectory: true)
    
    static let audioDirectory =
        baseDirectory.appendingPathComponent("Media/Audio", isDirectory: true)
    
    static let documentsDirectory =
        baseDirectory.appendingPathComponent("Media/Documents", isDirectory: true)
    
    /// Call once on app startup to ensure all directories exist.
    static func initializeIfNeeded() {
        let fm = FileManager.default
        let dirs = [imagesDirectory, audioDirectory, documentsDirectory]
        
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir,
                                           withIntermediateDirectories: true)
                } catch {
                    print("❌ Failed to create media directory \(dir.path): \(error)")
                }
            }
        }
        
        print("✅ Media directories ready:")
        print("   • Images    = \(imagesDirectory.path)")
        print("   • Audio     = \(audioDirectory.path)")
        print("   • Documents = \(documentsDirectory.path)")
    }
    
    // MARK: - Image Storage
    
    /// Save a UIImage as JPEG and return a **relative** file path
    /// (e.g., "Media/Images/<uuid>.jpg").
    static func saveImage(_ image: UIImage,
                          quality: CGFloat = 0.8) throws -> String {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw AppError.imageProcessingError("Failed to compress image to JPEG.")
        }
        
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        
        try ensureParentDirectoryExists(for: fileURL)
        try data.write(to: fileURL, options: .atomic)
        
        return "Media/Images/\(filename)"
    }
    
    /// Load a UIImage from a **relative** file path.
    static func loadImage(from relativePath: String) -> UIImage? {
        let url = absoluteURL(from: relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Audio Storage
    
    /// Returns a **file URL** for a new audio recording target.
    /// Caller is responsible for writing/recording audio data into it.
    static func newAudioRecordingURL() -> URL {
        let filename = "\(UUID().uuidString).m4a"
        let url = audioDirectory.appendingPathComponent(filename)
        try? ensureParentDirectoryExists(for: url)
        return url
    }
    
    /// Convert an audio file URL into a **relative** path suitable for SwiftData.
    static func relativeAudioPath(from url: URL) -> String {
        "Media/Audio/\(url.lastPathComponent)"
    }
    
    /// Get a full file URL from a **relative** audio path.
    static func audioURL(from relativePath: String) -> URL {
        absoluteURL(from: relativePath)
    }
    
    // MARK: - Document Storage
    
    /// Save document data with a suggested filename.
    /// Prevents filename collisions by prepending a UUID.
    /// Returns a **relative** path (e.g., "Media/Documents/<uuid>_myFile.pdf").
    static func saveDocument(_ data: Data,
                             suggestedFilename: String) throws -> String {
        let sanitizedName = suggestedFilename.isEmpty
            ? "\(UUID().uuidString).dat"
            : suggestedFilename
        
        // Prevent filename collisions by prepending UUID
        let uniqueName = "\(UUID().uuidString)_\(sanitizedName)"
        let fileURL = documentsDirectory.appendingPathComponent(uniqueName)
        
        try ensureParentDirectoryExists(for: fileURL)
        try data.write(to: fileURL, options: .atomic)
        
        return "Media/Documents/\(uniqueName)"
    }
    
    /// Load document data from a **relative** path.
    static func loadDocument(from relativePath: String) throws -> Data {
        let url = absoluteURL(from: relativePath)
        return try Data(contentsOf: url)
    }
    
    // MARK: - File Management
    
    /// Delete a file at the given **relative** path.
    static func deleteFile(at relativePath: String) throws {
        let url = absoluteURL(from: relativePath)
        try FileManager.default.removeItem(at: url)
    }
    
    /// Check if a file exists at the given **relative** path.
    static func fileExists(at relativePath: String) -> Bool {
        let url = absoluteURL(from: relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Get file size (bytes) for a **relative** path.
    static func fileSize(at relativePath: String) -> Int64? {
        let url = absoluteURL(from: relativePath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }
    
    // MARK: - Helpers
    
    /// Convert a relative path (e.g. "Media/Images/foo.jpg") into
    /// an absolute URL under the base directory.
    static func absoluteURL(from relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }
    
    /// Ensure the parent directory for a file URL exists.
    static func ensureParentDirectoryExists(for fileURL: URL) throws {
        let dirURL = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: dirURL.path) {
            try fm.createDirectory(at: dirURL,
                                   withIntermediateDirectories: true)
        }
    }
}
