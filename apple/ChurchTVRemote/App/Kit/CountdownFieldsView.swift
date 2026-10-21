import SwiftUI
import ChurchTVCore

/// The countdown form shared by Slides countdown slides and Kids countdown items (same fields on the website's CountdownFields).
/// Put it inside a `Form` or `List`; it contributes its own sections:
/// heading, count down for a set time or to a clock time, if the time has passed, what happens at zero, and optional audio
/// (volume, fade, repeat, "Finish exactly at zero"), plus the "needs TV app 1.4.0+" note.
///
/// ```swift
/// Form { CountdownFieldsView(settings: $countdown, module: .slides) }
/// ```
/// `module` picks the media library the audio comes from ('kids' or 'slides'). Validation text is `settings.problem`.
struct CountdownFieldsView: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: CountdownSettings
    var module: AppModule
    @State private var pickingAudio = false

    private var mode: CountdownMode { settings.effectiveMode }
    private var minutes: Int { settings.effectiveSeconds / 60 }
    private var secs: Int { settings.effectiveSeconds % 60 }

    var body: some View {
        Group {
            Section("Heading") {
                TextField("e.g. Service starts in", text: Binding(get: { settings.title ?? "" }, set: { settings.title = $0 }))
            }

            Section {
                Picker("Count down", selection: Binding(get: { mode }, set: { settings.setMode($0) })) {
                    Text("For a set time").tag(CountdownMode.duration)
                    Text("To a clock time").tag(CountdownMode.until)
                }
                if mode == .duration {
                    Stepper(value: Binding(get: { minutes }, set: { settings.seconds = max(0, $0) * 60 + secs }), in: 0...999) {
                        LabeledContent("Minutes", value: "\(minutes)")
                    }
                    Stepper(value: Binding(get: { secs }, set: { settings.seconds = minutes * 60 + min(59, max(0, $0)) }), in: 0...59) {
                        LabeledContent("Seconds", value: "\(secs)")
                    }
                } else {
                    DatePicker("Counts down to", selection: untilBinding, displayedComponents: .hourAndMinute)
                    Picker("If that time has passed", selection: Binding(get: { settings.effectiveIfPassed }, set: { settings.ifPassed = $0 })) {
                        Text("Show 0:00").tag(CountdownIfPassed.zero)
                        Text("Skip this slide").tag(CountdownIfPassed.skip)
                    }
                }
                Picker("When it reaches zero", selection: Binding(get: { settings.effectiveAtZero }, set: { settings.atZero = $0 })) {
                    Text("Stay on 0:00 until I press Next (recommended)").tag(CountdownAtZero.hold)
                    Text("Go to the next slide automatically").tag(CountdownAtZero.next)
                }
                .pickerStyle(.navigationLink)
            } header: { Text("Time") } footer: {
                Text(mode == .until ? "Today, in your site's time zone." : "Counts down from when the slide appears.")
            }

            Section {
                if let audio = settings.audio {
                    Button { pickingAudio = true } label: {
                        LabeledContent("Track") { Text(trackTitle(audio)).foregroundStyle(.secondary).lineLimit(1) }
                    }.foregroundStyle(.primary)
                    VStack(alignment: .leading) {
                        Text("Volume: \(Int((audio.effectiveVolume * 100).rounded()))%")
                        Slider(value: audioBinding(\.volume, default: CountdownAudio.defaultVolume), in: 0...1, step: 0.05)
                            .accessibilityLabel("Volume")
                    }
                    Stepper(value: Binding(get: { audio.effectiveFadeSeconds }, set: { settings.audio?.fadeSeconds = min(10, max(0, $0)) }), in: 0...10) {
                        LabeledContent("Fade out over the last", value: "\(audio.effectiveFadeSeconds) s")
                    }
                    Toggle("Repeat until zero", isOn: Binding(get: { audio.effectiveLoop }, set: { settings.audio?.loop = $0 }))
                    Toggle("Finish exactly at zero", isOn: Binding(get: { audio.effectiveAlignEnd }, set: { settings.audio?.alignEnd = $0 }))
                    Button("Remove audio", role: .destructive) { settings.audio = nil }
                } else {
                    Button { pickingAudio = true } label: { Label("Choose audio…", systemImage: "music.note") }
                }
            } header: { Text("Audio") } footer: {
                Text(settings.audio != nil
                     ? "Finish exactly at zero starts a shorter track late so it ends right at 0:00; a longer track starts partway through."
                     : "Music that plays during the countdown, from this module's media library (MP3 or M4A).")
            }

            Section {
                Label(CountdownSettings.needsAppNote, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                if let p = settings.problem {
                    Label(p.prefix(1).uppercased() + p.dropFirst(), systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .sheet(isPresented: $pickingAudio) {
            MediaPickerView(module: module, kinds: [.audio], title: "Choose audio", selectedId: settings.audio?.mediaId) { item in
                settings.setAudio(mediaId: item.id.uuidString.lowercased(), url: item.url)
            }
        }
    }

    private var untilBinding: Binding<Date> {
        Binding(get: {
            let p = (settings.until ?? "09:00").split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: p.first ?? 9, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            settings.until = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        })
    }

    private func audioBinding(_ key: WritableKeyPath<CountdownAudio, Double?>, default d: Double) -> Binding<Double> {
        Binding(get: { settings.audio?[keyPath: key] ?? d }, set: { settings.audio?[keyPath: key] = $0 })
    }

    private func trackTitle(_ a: CountdownAudio) -> String {
        model.content.mediaTitle(forId: a.mediaId) ?? URL(string: a.url)?.lastPathComponent.removingPercentEncoding ?? "Audio file"
    }
}
