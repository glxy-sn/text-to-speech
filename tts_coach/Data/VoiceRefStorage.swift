//
//  VoiceRefStorage.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import Foundation

/// Persists voice-reference recordings to a permanent on-disk location
/// (Application Support), since `AudioRecorderService` only ever writes
/// to the system temp directory — temp files can be cleared by the OS at
/// any time and aren't guaranteed to survive past the current run, let
/// alone across app launches. A saved `VoiceProfile` needs its reference
/// audio to outlive that.
enum VoiceReferenceStorage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PronunciationCoach/VoiceReferences", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Copies a freshly-recorded temp file into permanent storage under a
    /// new unique name, returning the new permanent URL. The original temp
    /// file is left untouched — whatever already cleans it up (e.g.
    /// `AudioRecorderService.discardRecording()`) still applies to it.
    static func persist(temporaryFileAt url: URL) throws -> URL {
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// Deletes a previously-persisted reference file — used when its
    /// owning `VoiceProfile` is deleted, so files don't accumulate
    /// indefinitely in Application Support.
    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
