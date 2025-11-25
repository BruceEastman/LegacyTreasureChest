//
//  ItemAudioSection.swift
//  LegacyTreasureChest
//
//  Placeholder section for audio stories about the item.
//  UI only for now – no real recording or playback yet.
//  Later we’ll hook this up to audio recording, transcription, and AudioRecording records.
//

import SwiftUI
import SwiftData

struct ItemAudioSection: View {
    @Bindable var item: LTCItem

    var body: some View {
        Section(header: Text("Audio Stories")) {
            if item.audioRecordings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.and.mic")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text("Record a short story or memory about this item.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        // Placeholder – will be wired to audio recording in a future update.
                    } label: {
                        HStack {
                            Image(systemName: "mic")
                            Text("Record Story")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .opacity(0.6)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio recordings attached:")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    ForEach(item.audioRecordings.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundStyle(.secondary)
                            Text("Recording \(index + 1)")
                                .font(.subheadline)
                        }
                    }

                    Text("Playback and transcription will be added in a future update.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
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
