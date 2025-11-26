//
//  ItemAudioSection.swift
//  LegacyTreasureChest
//
//  Audio stories section for an LTCItem.
//  - Record short voice stories
//  - Play/pause individual recordings
//  - Delete recordings (SwiftData + file deletion via MediaStorage)
//  Styled with Theme.swift for consistent branding.
//

import SwiftUI
import SwiftData
import AVFoundation
import Combine

// MARK: - Audio Manager

/// Manages AVAudioSession, AVAudioRecorder, and AVAudioPlayer.
/// Kept as a @StateObject in the view so we avoid global singletons.
@MainActor
final class AudioManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {

    @Published var isRecording: Bool = false
    @Published var isPlaying: Bool = false
    @Published var currentlyPlayingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?

    /// Begin recording to a new file URL under Media/Audio.
    /// Returns the URL being recorded to, or throws on failure.
    func startRecording() throws -> URL {
        let session = AVAudioSession.sharedInstance()

        // Configure session for record + playback through speaker.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: [])

        let url = MediaStorage.newAudioRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = false
        recorder.record()

        audioRecorder = recorder
        isRecording = true

        return url
    }

    /// Stop recording, returning the URL and duration (seconds).
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder else { return nil }

        // Capture duration BEFORE stopping; some implementations reset currentTime on stop.
        let recordedURL = recorder.url
        let duration = recorder.currentTime

        recorder.stop()
        audioRecorder = nil
        isRecording = false

        // Deactivate the session for recording; playback may reactivate as needed.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        return (recordedURL, duration)
    }

    /// Toggle playback for a given URL. Only one recording plays at a time.
    func togglePlayback(for url: URL) {
        // If this URL is currently playing, pause/stop it.
        if isPlaying, let currentURL = currentlyPlayingURL, currentURL == url {
            stopPlayback()
            return
        }

        // Stop any existing playback first.
        stopPlayback()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            audioPlayer = player
            currentlyPlayingURL = url
            isPlaying = true
            player.play()

            // Ensure session is active for playback.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try? session.setActive(true, options: [])
        } catch {
            print("❌ Failed to start playback: \(error)")
            stopPlayback()
        }
    }

    /// Stop any active playback.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentlyPlayingURL = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Reset state when playback completes.
        stopPlayback()
    }
}

// MARK: - ItemAudioSection

struct ItemAudioSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: LTCItem

    @StateObject private var audioManager = AudioManager()

    // URL of the file currently being recorded (if any).
    @State private var currentRecordingURL: URL?

    // Simple alert for user-facing errors.
    @State private var alertMessage: String?
    @State private var isShowingAlert: Bool = false

    private var sortedRecordings: [AudioRecording] {
        item.audioRecordings.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Section(header: Text("Audio Stories").ltcSectionHeaderStyle()) {
            if sortedRecordings.isEmpty {
                emptyStateView
            } else {
                recordingsListView
            }
        }
        .alert("Audio Error", isPresented: $isShowingAlert, presenting: alertMessage) { _ in
            Button("OK", role: .cancel) {
                isShowingAlert = false
            }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            HStack(spacing: Theme.spacing.small) {
                Image(systemName: "waveform.and.mic")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.accent)

                Text("Record a short story or memory about this item.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button(action: handleRecordButtonTap) {
                HStack {
                    Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "mic")
                    Text(audioManager.isRecording ? "Stop Recording" : "Record Story")
                }
                .font(Theme.bodyFont)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(.vertical, Theme.spacing.small)
    }

    private var recordingsListView: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            // Record / stop button at top, even when recordings exist.
            Button(action: handleRecordButtonTap) {
                HStack {
                    Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "mic")
                    Text(audioManager.isRecording ? "Stop Recording" : "Record New Story")
                }
                .font(Theme.bodyFont)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.bottom, Theme.spacing.small)

            ForEach(sortedRecordings, id: \.audioRecordingId) { recording in
                recordingRow(for: recording)
                    .padding(.vertical, Theme.spacing.xs)
            }
        }
        .padding(.vertical, Theme.spacing.small)
    }

    private func recordingRow(for recording: AudioRecording) -> some View {
        let url = MediaStorage.audioURL(from: recording.filePath)
        let isPlayingThis = isPlaying(recording: recording, url: url)

        return HStack(spacing: Theme.spacing.small) {
            Button {
                handlePlayPause(for: recording, url: url)
            } label: {
                Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                Text(title(for: recording))
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)

                Text(formattedDuration(recording.duration))
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button(role: .destructive) {
                handleDelete(recording: recording)
            } label: {
                Image(systemName: "trash")
                    .font(Theme.secondaryFont)
            }
            .buttonStyle(.borderless)
            .tint(Theme.destructive)
        }
    }

    // MARK: - Actions

    private func handleRecordButtonTap() {
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .undetermined:
            // Ask for permission, then start recording if granted.
            session.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        startRecording()
                    } else {
                        presentAlert("Microphone access is required to record audio stories. You can enable microphone access in Settings.")
                    }
                }
            }

        case .denied:
            presentAlert("Microphone access is currently denied. Please enable microphone access for Legacy Treasure Chest in Settings to record audio stories.")

        case .granted:
            // Toggle record / stop.
            if audioManager.isRecording {
                stopRecordingAndSave()
            } else {
                startRecording()
            }

        @unknown default:
            presentAlert("Unable to use the microphone due to an unknown permission state.")
        }
    }

    private func startRecording() {
        do {
            let url = try audioManager.startRecording()
            currentRecordingURL = url
        } catch {
            print("❌ Failed to start recording: \(error)")
            presentAlert("Unable to start recording. Please try again.")
            currentRecordingURL = nil
        }
    }

    private func stopRecordingAndSave() {
        guard let result = audioManager.stopRecording() else {
            presentAlert("Recording did not complete successfully.")
            return
        }

        let url = result.url
        let duration = result.duration

        // Convert URL -> relative file path under Media/Audio.
        let relativePath = MediaStorage.relativeAudioPath(from: url)

        let recording = AudioRecording(
            filePath: relativePath,
            duration: duration,
            transcription: nil,
            createdAt: .now,
            updatedAt: .now
        )
        recording.item = item
        modelContext.insert(recording)

        // Optionally bump the item's updatedAt.
        item.updatedAt = .now

        currentRecordingURL = nil
    }

    private func handlePlayPause(for recording: AudioRecording, url: URL) {
        guard MediaStorage.fileExists(at: recording.filePath) else {
            presentAlert("The audio file for this recording can’t be found. It may have been removed.")
            return
        }

        audioManager.togglePlayback(for: url)
    }

    private func handleDelete(recording: AudioRecording) {
        // Stop playback if this recording is playing.
        let url = MediaStorage.audioURL(from: recording.filePath)
        if isPlaying(recording: recording, url: url) {
            audioManager.stopPlayback()
        }

        // Try to delete the underlying file (soft-fail).
        do {
            try MediaStorage.deleteFile(at: recording.filePath)
        } catch {
            print("⚠️ Failed to delete audio file at \(recording.filePath): \(error)")
        }

        modelContext.delete(recording)
    }

    // MARK: - Helpers

    private func isPlaying(recording: AudioRecording, url: URL) -> Bool {
        audioManager.isPlaying && audioManager.currentlyPlayingURL == url
    }

    private func title(for recording: AudioRecording) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateString = formatter.string(from: recording.createdAt)
        return "Story from \(dateString)"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds > 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func presentAlert(_ message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}

// MARK: - Preview

private let itemAudioPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample = LTCItem(
        name: "Preview Item with Audio",
        itemDescription: "This is a preview item for the audio section.",
        category: "Collectibles",
        value: 0
    )

    context.insert(sample)

    return container
}()

#Preview("Item Audio Section – Empty") {
    let container = itemAudioPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<LTCItem>()
    let items = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = items.first {
            Form {
                ItemAudioSection(item: first)
            }
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
