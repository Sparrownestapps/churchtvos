import SwiftUI
import ChurchTVCore

// MARK: - Play now

/// Starts the saved deck on a TV (the Remote's Play now command with kind 'deck').
struct DeckPlayNowSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deckId: UUID
    let name: String
    @State private var screenId: UUID?
    @State private var minutes = 60
    @State private var sending = false
    private let durations = [15, 30, 60, 90, 120, 240, 480]

    var body: some View {
        NavigationStack {
            Form {
                Section("TV") {
                    if model.screens.isEmpty {
                        Text("No TVs found for this church.").foregroundStyle(.secondary)
                    } else {
                        Picker("Play on", selection: $screenId) {
                            ForEach(model.screens) { s in Text(s.screen.displayName).tag(UUID?.some(s.id)) }
                        }
                        .pickerStyle(.inline).labelsHidden()
                    }
                }
                Section {
                    Picker("Play for", selection: $minutes) { ForEach(durations, id: \.self) { Text(Formatting.minutes($0)).tag($0) } }
                } footer: { Text("After that the TV returns to its schedule.") }
                if let e = model.commandError { Section { Banner(text: e, style: .error) } }
            }
            .navigationTitle("Play “\(name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Start") { start() }.disabled(screenId == nil || sending) }
            }
            .onAppear {
                model.commandError = nil
                if screenId == nil { screenId = model.selectedScreenId ?? model.screens.first?.id }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func start() {
        guard let screen = model.screens.first(where: { $0.id == screenId }) else { return }
        sending = true
        Task {
            let ok = await model.send(.start(kind: .deck, id: deckId, minutes: minutes), to: screen)
            sending = false
            if ok { dismiss() }
        }
    }
}
