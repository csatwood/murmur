import AVFoundation
import AppKit
import SwiftUI

/// First-run setup: welcome → permissions → recognition engine → hotkey →
/// mic test → done. Shown once (`Settings.hasCompletedOnboarding`), then
/// replaced by the normal main window. Every choice here applies for real
/// the moment it's made — same as `SettingsPage` — so there's nothing to
/// save on Continue, only somewhere further to go.
struct OnboardingRoot: View {
    @ObservedObject var app: AppDelegate
    let onFinish: () -> Void

    @State private var step: Step = .welcome

    private enum Step: Int, CaseIterable {
        case welcome, permissions, engine, hotkey, micTest, done
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 20)
            progress
            Group {
                switch step {
                case .welcome: welcomeStep
                case .permissions: permissionsStep
                case .engine: engineStep
                case .hotkey: hotkeyStep
                case .micTest: micTestStep
                case .done: doneStep
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panel)
    }

    // MARK: - Chrome

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Palette.accentText : Palette.border)
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 44)
        .animation(.murmurEase(), value: step)
    }

    private var footer: some View {
        HStack {
            Button("Back") { move(-1) }
                .buttonStyle(GhostButtonStyle())
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    Text(primaryLabel)
                    MurmurIconView(icon: .arrowRight).frame(width: 12, height: 12)
                }
                .font(.manrope(13.5, .bold))
                .foregroundStyle(Palette.accentInk)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 26)
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return "Get started"
        case .permissions: return "Continue"
        case .engine: return app.engine == "apple" ? "Continue" : "Download & continue"
        case .hotkey: return "Continue"
        case .micTest: return "Continue"
        case .done: return "Open Murmur"
        }
    }

    private func primaryAction() {
        if step == .done {
            onFinish()
            return
        }
        move(1)
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.murmurEase()) { step = next }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.manrope(24, .bold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(.manrope(13.5))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430, alignment: .leading)
        }
        .padding(.bottom, 26)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .padding(.bottom, 22)
            Text("WELCOME TO MURMUR")
                .font(.manrope(11, .bold))
                .kerning(1.4)
                .foregroundStyle(Palette.accentText)
                .padding(.bottom, 14)
            Text("Everything you say, turned into text — without leaving your Mac.")
                .font(.manrope(30, .bold))
                .tracking(-0.4)
                .lineSpacing(3)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440, alignment: .leading)
                .padding(.bottom, 12)
            Text("Murmur listens only while you hold a key, transcribes on-device, and drops the result wherever your cursor already is.")
                .font(.manrope(14))
                .foregroundStyle(Palette.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430, alignment: .leading)
                .padding(.bottom, 28)
            HStack(alignment: .top, spacing: 26) {
                fact(.lock, "Private & on-device — audio never leaves this Mac")
                fact(.apps, "Works in any app you already use")
                fact(.check, "Formats itself — yours to correct anytime")
            }
        }
    }

    private func fact(_ icon: MurmurIcon, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MurmurIconView(icon: icon)
                .frame(width: 18, height: 18)
                .foregroundStyle(Palette.accentText)
            Text(text)
                .font(.manrope(11.5, .medium))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 122, alignment: .leading)
    }

    // MARK: - Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader(
                "Let's get you set up",
                "Two permissions, and Murmur is ready. Nothing you say ever leaves this Mac either way.")
            VStack(spacing: 10) {
                PermissionRow(
                    icon: .mic, title: "Microphone",
                    detail: "Captures your voice while you hold the hotkey — never listens otherwise.",
                    granted: app.micAuthorized
                ) {
                    Task { app.micAuthorized = await AudioRecorder.requestMicrophoneAccess() }
                }
                PermissionRow(
                    icon: .fingerprint, title: "Accessibility",
                    detail: "Lets Murmur paste text into the app you're using and detect your hotkey system-wide.",
                    granted: app.axTrusted
                ) {
                    app.refreshPermissions(promptAccessibility: true)
                }
            }
            Text("You can change either of these later in System Settings → Privacy & Security.")
                .font(.manrope(11.5))
                .foregroundStyle(Palette.inkFaint)
                .padding(.top, 16)
        }
    }

    // MARK: - Engine + model

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader(
                "How should Murmur listen?",
                "Pick a recognition engine. You can change this anytime in Settings.")
            VStack(spacing: 10) {
                EngineOptionRow(
                    title: "Apple — instant",
                    detail: "Instant, built into macOS. Runs locally.",
                    selected: app.engine == "apple") { app.setEngine("apple") }
                EngineOptionRow(
                    title: "Whisper — precise",
                    detail: "Best accuracy on accents and jargon; your vocabulary is fed to the model. Runs locally.",
                    selected: app.engine == "whisper") { app.setEngine("whisper") }
                EngineOptionRow(
                    title: "whisper.cpp — precise, Metal",
                    detail: "The same Whisper models, run on the GPU via Metal instead of the Neural Engine — faster, at some cost to battery life. Runs locally.",
                    selected: app.engine == "whispercpp") { app.setEngine("whispercpp") }
            }
            if app.engine == "apple" {
                Text("Nothing to download — Apple's engine is already on your Mac.")
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.top, 16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MODEL SIZE")
                        .font(.manrope(10.5, .bold))
                        .kerning(0.6)
                        .foregroundStyle(Palette.inkFaint)
                    VStack(spacing: 7) {
                        ForEach(currentModels, id: \.id) { model in
                            ModelSizeRow(label: model.label, selected: currentModelID == model.id) {
                                setCurrentModel(model.id)
                            }
                        }
                    }
                }
                .padding(.top, 18)
                Text(engineStatusNote)
                    .font(.manrope(11.5))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.top, 14)
            }
        }
    }

    private var currentModels: [(id: String, label: String)] {
        app.engine == "whispercpp" ? WhisperCppEngine.availableModels : WhisperEngine.availableModels
    }

    private var currentModelID: String {
        app.engine == "whispercpp" ? app.whisperCppModel : app.whisperModel
    }

    private func setCurrentModel(_ id: String) {
        if app.engine == "whispercpp" {
            app.setWhisperCppModel(id)
        } else {
            app.setWhisperModel(id)
        }
    }

    /// Matches `SettingsPage`'s `whisperModelDetail` / `whisperCppModelDetail`
    /// wording exactly — the same fact shown in two places should read the
    /// same in both.
    private var engineStatusNote: String {
        if app.engine == "whispercpp" {
            if app.whisperCppReady {
                return "Model loaded — whisper.cpp is transcribing your dictations."
            }
            if app.whisperCppEngine.isModelDownloaded(app.whisperCppModel) {
                return "Model downloaded — loading. Apple engine covers dictations until it's ready."
            }
            return "Downloading in the background. Apple engine covers dictations until it's ready."
        }
        if app.whisperReady {
            return "Model loaded — Whisper is transcribing your dictations."
        }
        if app.whisperEngine.isModelDownloaded(app.whisperModel) {
            return "Model downloaded — loading. Apple engine covers dictations until it's ready."
        }
        return "Downloading in the background. Apple engine covers dictations until it's ready."
    }

    // MARK: - Hotkey

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader(
                "Pick your hotkey",
                "Hold it anywhere to dictate, release to stop. Tap twice quickly to go hands-free — tap once more to stop.")
            VStack(spacing: 8) {
                ForEach(HotkeyMonitor.Hotkey.allCases, id: \.self) { key in
                    HotkeyOptionRow(hotkey: key, selected: app.hotkey == key) {
                        app.setHotkey(key)
                    }
                }
            }
        }
    }

    // MARK: - Mic test

    private var micTestStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader("Let's test your microphone", "Say something out loud — the waveform should react.")
            HStack(spacing: 10) {
                MurmurIconView(icon: .mic)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Palette.inkSoft)
                Text(defaultInputName)
                    .font(.manrope(12.5, .semibold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.border, lineWidth: 1))
            .frame(maxWidth: 300, alignment: .leading)
            Spacer(minLength: 24)
            HStack {
                Spacer(minLength: 0)
                CaptureWaveform(active: true, color: Palette.inkSoft)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 24)
        }
    }

    private var defaultInputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "System Default"
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle().fill(Palette.accentSoft).frame(width: 56, height: 56)
                MurmurIconView(icon: .check)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Palette.accentText)
            }
            .padding(.bottom, 22)
            Text("You're all set.")
                .font(.manrope(24, .bold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 8)
            Text("Murmur is running quietly in your menu bar.")
                .font(.manrope(13.5))
                .foregroundStyle(Palette.inkSoft)
                .padding(.bottom, 20)
            HStack(spacing: 14) {
                Keycap(text: app.hotkey.shortSymbol)
                Text("Hold **\(app.hotkey.displayName)** anywhere to start dictating — release when you're done.")
                    .font(.manrope(12.5))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.border, lineWidth: 1))
            .frame(maxWidth: 420, alignment: .leading)
        }
    }
}

// MARK: - Rows

private struct RadioDot: View {
    let selected: Bool
    var body: some View {
        Circle()
            .strokeBorder(selected ? Palette.accentText : Palette.border, lineWidth: 1.5)
            .frame(width: 18, height: 18)
            .overlay {
                if selected {
                    Circle().fill(Palette.accentText).frame(width: 9, height: 9)
                }
            }
    }
}

private struct PermissionRow: View {
    let icon: MurmurIcon
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            MurmurIconView(icon: icon)
                .frame(width: 17, height: 17)
                .foregroundStyle(granted ? Palette.accentText : Palette.inkSoft)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(granted ? Palette.accentSoft : Palette.cardHover))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.manrope(14, .bold)).foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.manrope(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if granted {
                HStack(spacing: 5) {
                    MurmurIconView(icon: .check).frame(width: 11, height: 11)
                    Text("Allowed").font(.manrope(12, .bold))
                }
                .foregroundStyle(Palette.accentText)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(granted ? Palette.accentSoft : Palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(granted ? Color.clear : Palette.border, lineWidth: 1))
    }
}

private struct EngineOptionRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RadioDot(selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.manrope(14, .bold)).foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.manrope(12))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(selected ? Palette.accentSoft : Palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(selected ? Palette.accentText : Palette.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ModelSizeRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RadioDot(selected: selected)
                Text(label)
                    .font(.manrope(12.5, selected ? .bold : .medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(selected ? Palette.accentSoft : Palette.panel))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(selected ? Palette.accentText : Palette.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct HotkeyOptionRow: View {
    let hotkey: HotkeyMonitor.Hotkey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Keycap(
                    text: hotkey.shortSymbol,
                    tint: selected ? Palette.accentInk : Palette.inkSoft,
                    background: selected ? Palette.accent : Palette.cardHover,
                    borderColor: selected ? Palette.accent : Palette.border)
                Text(hotkey.displayName)
                    .font(.manrope(13.5, .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                RadioDot(selected: selected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(selected ? Palette.accentSoft : Palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(selected ? Palette.accentText : Palette.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}
