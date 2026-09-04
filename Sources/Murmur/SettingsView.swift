import AppKit
import Speech
import SwiftUI

// MARK: - Settings

struct SettingsPage: View {
    @ObservedObject var app: AppDelegate
    @State private var supportedLocaleIDs: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Settings",
                subtitle: "Appearance, permissions, dictation key, recognition engine.")

            SectionHead(title: "Appearance")
            Card(flat: true) {
                FieldRow(
                    label: "Theme",
                    detail: appearanceDetail,
                    isLast: true
                ) {
                    SegmentedPicker(
                        options: AppearanceSetting.allCases,
                        label: { $0.label },
                        selection: Binding(
                            get: { app.appearance },
                            set: { newValue in
                                withAnimation(.murmurEase(0.18)) {
                                    app.setAppearance(newValue)
                                }
                            }))
                }
            }

            SectionHead(title: "Permissions")
            Card(flat: true) {
                permissionRow(
                    granted: app.micAuthorized,
                    title: "Microphone",
                    detail: "Required to hear your dictation.",
                    pane: "Privacy_Microphone",
                    isLast: false)
                permissionRow(
                    granted: app.axTrusted,
                    title: "Accessibility",
                    detail: "Required for the global hotkey and pasting. "
                        + "Relaunch Murmur after granting.",
                    pane: "Privacy_Accessibility",
                    isLast: app.axTrusted)
                if !app.axTrusted {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Toggle on in System Settings but still red here? The saved grant "
                             + "belongs to an older build. Click Reset Grant — the app relaunches, "
                             + "macOS asks once more, and the new grant sticks for all future updates.")
                            .font(.manrope(11.5))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Reset Grant & Relaunch") { app.resetAccessibilityGrant() }
                                .buttonStyle(GhostButtonStyle())
                            Button("Relaunch") { app.relaunch() }
                                .buttonStyle(GhostButtonStyle())
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 12)
                }
            }

            SectionHead(title: "Dictation")
            Card(flat: true) {
                FieldRow(label: "Dictation key") {
                    FieldSelect(
                        options: HotkeyMonitor.Hotkey.allCases,
                        label: { $0.displayName },
                        selection: Binding(
                            get: { app.hotkey },
                            set: { app.setHotkey($0) }))
                }
                FieldRow(label: "Language") {
                    FieldSelect(
                        options: pickerLocaleIDs,
                        label: { Locale.current.localizedString(forIdentifier: $0) ?? $0 },
                        selection: Binding(
                            get: { app.localeID },
                            set: { app.setLocale($0) }))
                }
                FieldRow(
                    label: "Recognition engine",
                    detail: engineDetail,
                    isLast: app.engine != "whisper" && app.engine != "whispercpp"
                        && app.engine != "parakeet"
                ) {
                    FieldSelect(
                        options: ["apple", "whisper", "whispercpp", "parakeet"],
                        label: engineLabel,
                        selection: Binding(
                            get: { app.engine },
                            set: { app.setEngine($0) }))
                }
                if app.engine == "whisper" {
                    FieldRow(
                        label: "Whisper model",
                        detail: whisperModelDetail,
                        isLast: true
                    ) {
                        FieldSelect(
                            options: WhisperEngine.availableModels.map(\.id),
                            label: { id in
                                WhisperEngine.availableModels.first { $0.id == id }?.label ?? id
                            },
                            selection: Binding(
                                get: { app.whisperModel },
                                set: { app.setWhisperModel($0) }))
                    }
                }
                if app.engine == "whispercpp" {
                    FieldRow(
                        label: "whisper.cpp model",
                        detail: whisperCppModelDetail,
                        isLast: true
                    ) {
                        FieldSelect(
                            options: WhisperCppEngine.availableModels.map(\.id),
                            label: { id in
                                WhisperCppEngine.availableModels.first { $0.id == id }?.label ?? id
                            },
                            selection: Binding(
                                get: { app.whisperCppModel },
                                set: { app.setWhisperCppModel($0) }))
                    }
                }
                if app.engine == "parakeet" {
                    FieldRow(
                        label: "Parakeet model",
                        detail: parakeetModelDetail,
                        isLast: true
                    ) {
                        FieldSelect(
                            options: ParakeetEngine.availableModels.map(\.id),
                            label: { id in
                                ParakeetEngine.availableModels.first { $0.id == id }?.label ?? id
                            },
                            selection: Binding(
                                get: { app.parakeetModel },
                                set: { app.setParakeetModel($0) }))
                    }
                }
            }
        }
        .onAppear(perform: loadLocales)
    }

    private func engineLabel(_ id: String) -> String {
        switch id {
        case "whisper": return "Whisper — precise"
        // whisper.cpp runs the same Whisper models through a different,
        // Metal-accelerated engine — benchmarked ~3-4x faster than the
        // WhisperKit/Neural-Engine path above on Apple Silicon, likely
        // because it uses the GPU rather than the power-efficient Neural
        // Engine. A speed/battery tradeoff worth letting you pick, not one
        // engine replacing the other.
        case "whispercpp": return "whisper.cpp — precise, Metal"
        case "parakeet": return "Parakeet — precise, fast"
        default: return "Apple — instant"
        }
    }

    private var engineDetail: String {
        switch app.engine {
        case "whisper":
            return "Whisper: best accuracy on accents and jargon; your vocabulary is fed "
                + "to the model. Runs locally."
        case "whispercpp":
            return "whisper.cpp: the same Whisper models, run on the GPU via Metal instead "
                + "of the Neural Engine — faster, at some cost to battery life. Runs locally."
        case "parakeet":
            return "Parakeet: NVIDIA's model, run on the Neural Engine — notably fast, "
                + "strong accuracy. Your dictionary isn't fed to it yet, unlike the "
                + "Whisper engines above. Runs locally."
        default:
            return "Apple: instant, built into macOS. Runs locally."
        }
    }

    /// Says what the current choice actually does, rather than restating
    /// the option's own name back at the reader.
    private var appearanceDetail: String {
        switch app.appearance {
        case .system:
            return "Follows your Mac — including switching automatically if macOS is set to Auto."
        case .light:
            return "Always light, whatever your Mac is set to."
        case .dark:
            return "Always dark, whatever your Mac is set to."
        }
    }

    private var whisperModelDetail: String {
        if app.whisperReady {
            return "Model loaded — Whisper is transcribing your dictations."
        }
        if app.whisperEngine.isModelDownloaded(app.whisperModel) {
            return "Model downloaded — loading. Apple engine covers dictations until it's ready."
        }
        return "Downloading in the background. Apple engine covers dictations until it's ready."
    }

    private var whisperCppModelDetail: String {
        if app.whisperCppReady {
            return "Model loaded — whisper.cpp is transcribing your dictations."
        }
        if app.whisperCppEngine.isModelDownloaded(app.whisperCppModel) {
            return "Model downloaded — loading. Apple engine covers dictations until it's ready."
        }
        return "Downloading in the background. Apple engine covers dictations until it's ready."
    }

    private var parakeetModelDetail: String {
        if app.parakeetReady {
            return "Model loaded — Parakeet is transcribing your dictations."
        }
        if app.parakeetEngine.isModelDownloaded(app.parakeetModel) {
            return "Model downloaded — loading. Apple engine covers dictations until it's ready."
        }
        return "Downloading in the background. Apple engine covers dictations until it's ready."
    }

    private func permissionRow(
        granted: Bool, title: String, detail: String, pane: String, isLast: Bool
    ) -> some View {
        FieldRow(label: title, detail: detail, isLast: isLast) {
            if granted {
                HStack(spacing: 6) {
                    MurmurIconView(icon: .check).frame(width: 13, height: 13)
                    Text("Granted").font(.manrope(12, .semibold))
                }
                .foregroundStyle(Palette.accentText)
            } else {
                Button("Open Settings") {
                    let url = URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var pickerLocaleIDs: [String] {
        var ids = supportedLocaleIDs
        if !ids.contains(app.localeID) { ids.insert(app.localeID, at: 0) }
        return ids
    }

    private func loadLocales() {
        Task {
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocaleIDs = locales
                .map { $0.identifier(.bcp47) }
                .sorted {
                    (Locale.current.localizedString(forIdentifier: $0) ?? $0)
                    < (Locale.current.localizedString(forIdentifier: $1) ?? $1)
                }
        }
    }
}
