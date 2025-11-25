//
//  MediaCleaner.swift
//  LegacyTreasureChest
//
//  Removes orphaned media files that are no longer referenced
//  by any SwiftData entities.
//

import Foundation
import SwiftData

/// MediaCleaner scans the media directories and compares the files
/// on disk with the file paths referenced in SwiftData.
/// Any files on disk that are not referenced are deleted.
enum MediaCleaner {
    
    /// Scan all media directories and remove orphaned files.
    ///
    /// - Parameter modelContext: A `ModelContext` connected to the app's
    ///   `ModelContainer`. Typically called from a background task.
    static func cleanOrphanedFiles(using modelContext: ModelContext) throws {
        print("🧹 Starting media cleanup...")
        
        let referencedPaths = try referencedFilePaths(using: modelContext)
        var removedCount = 0
        
        // Images
        removedCount += try cleanDirectory(
            MediaStorage.imagesDirectory,
            prefix: "Media/Images/",
            referencedPaths: referencedPaths
        )
        
        // Audio
        removedCount += try cleanDirectory(
            MediaStorage.audioDirectory,
            prefix: "Media/Audio/",
            referencedPaths: referencedPaths
        )
        
        // Documents
        removedCount += try cleanDirectory(
            MediaStorage.documentsDirectory,
            prefix: "Media/Documents/",
            referencedPaths: referencedPaths
        )
        
        print("✅ Media cleanup complete. Removed \(removedCount) orphaned files.")
    }
    
    /// Gather the set of all file paths currently referenced in SwiftData.
    private static func referencedFilePaths(using modelContext: ModelContext) throws -> Set<String> {
        var paths = Set<String>()
        
        // Images
        let imageFetch = FetchDescriptor<ItemImage>()
        let images = try modelContext.fetch(imageFetch)
        paths.formUnion(images.map { $0.filePath })
        
        // Audio
        let audioFetch = FetchDescriptor<AudioRecording>()
        let audioRecordings = try modelContext.fetch(audioFetch)
        paths.formUnion(audioRecordings.map { $0.filePath })
        
        // Documents
        let docFetch = FetchDescriptor<Document>()
        let documents = try modelContext.fetch(docFetch)
        paths.formUnion(documents.map { $0.filePath })
        
        return paths
    }
    
    /// Clean a specific directory by deleting files not present in
    /// the `referencedPaths` set.
    ///
    /// - Parameters:
    ///   - directory: The folder containing media files.
    ///   - prefix: The relative prefix used in SwiftData
    ///             (e.g., "Media/Images/").
    ///   - referencedPaths: The set of all file paths referenced
    ///             in SwiftData.
    /// - Returns: The number of files removed.
    private static func cleanDirectory(
        _ directory: URL,
        prefix: String,
        referencedPaths: Set<String>
    ) throws -> Int {
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: directory.path) else {
            return 0
        }
        
        let filenames = try fm.contentsOfDirectory(atPath: directory.path)
        var removedCount = 0
        
        for filename in filenames {
            let relativePath = prefix + filename
            
            // If the file is not referenced anywhere in SwiftData, delete it.
            guard !referencedPaths.contains(relativePath) else {
                continue
            }
            
            let fileURL = directory.appendingPathComponent(filename)
            do {
                try fm.removeItem(at: fileURL)
                removedCount += 1
                print("   🗑️ Removed orphaned file: \(relativePath)")
            } catch {
                print("   ⚠️ Failed to remove file \(relativePath): \(error)")
            }
        }
        
        return removedCount
    }
    
    // MARK: - Utility / Diagnostics
    
    /// Compute the total size of all media files on disk (in bytes).
    static func totalMediaSizeInBytes() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        
        let directories = [
            MediaStorage.imagesDirectory,
            MediaStorage.audioDirectory,
            MediaStorage.documentsDirectory
        ]
        
        for directory in directories {
            guard fm.fileExists(atPath: directory.path) else { continue }
            if let filenames = try? fm.contentsOfDirectory(atPath: directory.path) {
                for filename in filenames {
                    let fileURL = directory.appendingPathComponent(filename)
                    if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                       let size = attrs[.size] as? NSNumber {
                        total += size.int64Value
                    }
                }
            }
        }
        
        return total
    }
    
    /// Format a byte count as a human-readable file size string.
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
