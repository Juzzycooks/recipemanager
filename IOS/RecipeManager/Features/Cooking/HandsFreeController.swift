import Foundation
import Observation

/// One recognition task's worth of listening. The live one is `LiveSpeechListener` (on-device `SFSpeechRecognizer`);
/// tests drive a fake. After `stop()` the listener must not call back.
@MainActor protocol SpeechListening: AnyObject {
    /// True when this phone can recognise speech on the device for the command language. Hands-free never falls
    /// back to server recognition.
    var supportsOnDeviceRecognition: Bool { get }
    /// Starts one task. `onResult` gets the whole transcript so far (partial or final); `onEnd` fires once when the
    /// task ends by itself (time limit, silence, final result or error).
    func start(onResult: @escaping @MainActor (_ transcript: String, _ isFinal: Bool) -> Void,
               onEnd: @escaping @MainActor (_ error: Error?) -> Void) throws
    func stop()
}

/// Reads text aloud. `onDone` fires once, when the speech finishes or is stopped.
@MainActor protocol SpeechSpeaking: AnyObject {
    func speak(_ text: String, onDone: @escaping @MainActor () -> Void)
    func stop()
}

/// The audio session, per phase: listening mixes with music; speaking also ducks it. See `LiveHandsFreeAudio`.
enum AudioUse: Sendable { case listening, speaking }

@MainActor protocol HandsFreeAudio: AnyObject {
    func prepare(for use: AudioUse) throws
    func release()
}

/// Microphone + Speech Recognition permission.
enum PermissionStatus: Sendable { case granted, denied, undetermined }

@MainActor protocol HandsFreePermissions: AnyObject {
    var status: PermissionStatus { get }
    /// Asks for whatever hasn't been asked yet; true when both are granted.
    func request() async -> Bool
}

/// Hands-free cook mode: listens for `VoiceCommand`s while cook mode is on screen, reads steps aloud, and keeps the
/// recogniser running (restarting it when a task ends, after errors and after interruptions such as a call or Siri).
///
/// States: `.off` → `.listening` ⇄ `.speaking` (recognition is stopped while speaking so it doesn't hear itself),
/// `.paused` while the audio session is interrupted. Leaving cook mode, backgrounding or turning it off stops everything.
@MainActor @Observable
final class HandsFreeController {
    enum Phase: Equatable { case off, listening, speaking, paused }
    enum Notice: Identifiable, Equatable {
        case denied, unsupported, couldNotStart, voiceOverWarning
        var id: Self { self }
    }

    static let enabledKey = "handsFree"
    static let readStepsKey = "handsFreeReadSteps"

    private(set) var phase: Phase = .off
    /// The cook's choice, remembered across launches. Turning it on asks for permission first.
    private(set) var isEnabled: Bool
    /// Speak each new step automatically (only while hands-free is on).
    var readsStepsAloud: Bool { didSet { defaults.set(readsStepsAloud, forKey: Self.readStepsKey) } }
    /// The last command heard ("Next step"), shown briefly.
    private(set) var caption: String?
    /// Bumped on every command: the haptic trigger.
    private(set) var commandCount = 0
    var notice: Notice?

    /// Called for each recognised command except "stop listening", which the controller handles itself.
    var onCommand: ((VoiceCommand) -> Void)?

    // Tunables (tests shorten them).
    var settleDelay: Duration = .milliseconds(700)
    var restartDelay: Duration = .milliseconds(250)
    var maxRestartDelay: Duration = .seconds(8)
    var captionDuration: Duration = .seconds(2.5)

    private let listener: SpeechListening
    private let speaker: SpeechSpeaking
    private let audio: HandsFreeAudio
    private let permissions: HandsFreePermissions
    private let defaults: UserDefaults

    private var visible = false
    private var foreground = true
    private var interrupted = false
    /// Words of the current task's transcript already used (by a command or ended by a pause).
    private var consumed = 0
    private var lastWords: [String] = []
    private var failures = 0
    /// Consecutive failures to start at all (microphone busy, no input): after a few, give up and say so.
    private var startFailures = 0
    private var speakToken = 0
    private var settleTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var captionTask: Task<Void, Never>?

    init(listener: SpeechListening? = nil, speaker: SpeechSpeaking? = nil, audio: HandsFreeAudio? = nil,
         permissions: HandsFreePermissions? = nil, defaults: UserDefaults = .standard) {
        self.listener = listener ?? LiveSpeechListener()
        self.speaker = speaker ?? LiveSpeaker()
        self.audio = audio ?? LiveHandsFreeAudio()
        self.permissions = permissions ?? LivePermissions()
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        readsStepsAloud = defaults.bool(forKey: Self.readStepsKey)
        if let live = self.audio as? LiveHandsFreeAudio {
            live.onInterruptionBegan = { [weak self] in self?.interruptionBegan() }
            live.onInterruptionEnded = { [weak self] in self?.interruptionEnded() }
            live.onRouteChange = { [weak self] in self?.routeChanged() }
        }
    }

    /// Cook mode is on screen and the app is in front, and the cook wants it.
    private var shouldRun: Bool { isEnabled && visible && foreground }

    // MARK: Turning it on and off

    /// The toggle. Turning on asks for Speech + Microphone the first time; a refusal (or a phone without on-device
    /// recognition) turns it back off with a notice.
    func setEnabled(_ on: Bool) async {
        guard on else { disable(); return }
        guard listener.supportsOnDeviceRecognition else { disable(); notice = .unsupported; return }
        guard await permissions.request() else { disable(); notice = .denied; return }
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        if shouldRun { startListening() }
    }

    private func disable() {
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        stopAll()
    }

    /// Cook mode appeared. Starts listening if the cook left hands-free on (and permission still stands).
    func appear() {
        visible = true
        resumeIfWanted()
    }

    /// Cook mode closed: stop listening and speaking, release the microphone.
    func disappear() {
        visible = false
        stopAll()
    }

    /// The scene went to the background (or came back).
    func setForeground(_ active: Bool) {
        guard active != foreground else { return }
        foreground = active
        if active { resumeIfWanted() } else { stopAll() }
    }

    private func resumeIfWanted() {
        guard shouldRun, phase == .off || phase == .paused else { return }
        if permissions.status != .granted || !listener.supportsOnDeviceRecognition {
            // Permission was withdrawn in Settings since last time.
            disable()
            notice = permissions.status == .denied ? .denied : listener.supportsOnDeviceRecognition ? nil : .unsupported
            return
        }
        startListening()
    }

    private func stopAll() {
        settleTask?.cancel(); restartTask?.cancel()
        listener.stop()
        if phase == .speaking { speakToken += 1; speaker.stop() }
        if phase != .off { audio.release() }
        phase = .off
        interrupted = false
        failures = 0
        startFailures = 0
    }

    // MARK: Listening

    private func startListening() {
        restartTask?.cancel(); settleTask?.cancel()
        guard shouldRun, !interrupted else { return }
        consumed = 0; lastWords = []
        do {
            try audio.prepare(for: .listening)
            try listener.start(onResult: { [weak self] text, isFinal in self?.heard(text, isFinal: isFinal) },
                               onEnd: { [weak self] error in self?.taskEnded(error) })
            phase = .listening
            startFailures = 0
        } catch {
            listener.stop()
            startFailures += 1
            if startFailures >= 3 { disable(); notice = .couldNotStart; return }
            phase = .listening    // still on: try again with back-off
            taskEnded(error)
        }
    }

    /// A task ended by itself (the ~1 minute limit, silence, an error): start a fresh one. Errors back off so a
    /// broken microphone doesn't spin.
    private func taskEnded(_ error: Error?) {
        guard phase == .listening, shouldRun else { return }
        listener.stop()
        if error != nil { failures += 1 } else { failures = 0 }
        let delay = failures == 0 ? restartDelay : min(restartDelay * (1 << min(failures, 6)), maxRestartDelay)
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.phase == .listening else { return }
            self.startListening()
        }
    }

    /// A transcript update. The utterance is the words since the last command or pause; it is parsed once it has
    /// settled (no new words for `settleDelay`), or at once when the recogniser says it is final.
    func heard(_ transcript: String, isFinal: Bool) {
        guard phase == .listening else { return }
        failures = 0
        let words = VoiceCommand.words(transcript)
        lastWords = words
        if consumed > words.count { consumed = words.count }   // the recogniser revised earlier words away
        settleTask?.cancel()
        if isFinal { settle(); return }
        settleTask = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func settle() {
        guard phase == .listening, consumed < lastWords.count else { return }
        let utterance = lastWords[consumed...].joined(separator: " ")
        if let command = VoiceCommand.parse(utterance) {
            consumed = lastWords.count
            fire(command)
        } else if !VoiceCommand.isIncomplete(utterance) {
            consumed = lastWords.count      // a pause ends ordinary talk; the next utterance starts fresh
        }
    }

    private func fire(_ command: VoiceCommand) {
        commandCount += 1
        show(command.caption)
        if command == .stopListening { disable(); return }
        // A fresh task, so the next command starts from an empty transcript.
        listener.stop()
        onCommand?(command)
        if phase == .listening { startListening() }
    }

    private func show(_ text: String) {
        caption = text
        captionTask?.cancel()
        captionTask = Task { [weak self, captionDuration] in
            try? await Task.sleep(for: captionDuration)
            guard !Task.isCancelled else { return }
            self?.caption = nil
        }
    }

    // MARK: Speaking

    /// Reads `text` aloud with recognition paused, then listens again. Does nothing while hands-free isn't running.
    func say(_ text: String) {
        guard shouldRun, phase == .listening || phase == .speaking, !text.isEmpty else { return }
        settleTask?.cancel(); restartTask?.cancel()
        listener.stop()
        speakToken += 1
        let token = speakToken
        if phase == .speaking { speaker.stop() }
        phase = .speaking
        try? audio.prepare(for: .speaking)
        speaker.speak(text) { [weak self] in self?.finishedSpeaking(token) }
    }

    private func finishedSpeaking(_ token: Int) {
        guard token == speakToken, phase == .speaking else { return }
        phase = .listening
        startListening()
    }

    // MARK: Interruptions (a call, Siri, an alarm)

    func interruptionBegan() {
        guard phase != .off else { return }
        interrupted = true
        settleTask?.cancel(); restartTask?.cancel()
        listener.stop()
        if phase == .speaking { speakToken += 1; speaker.stop() }
        phase = .paused
    }

    func interruptionEnded() {
        guard interrupted else { return }
        interrupted = false
        guard phase == .paused else { return }
        phase = .off
        resumeIfWanted()
    }

    /// Headphones plugged in or out: the input format changes, so start a new task on the new route.
    func routeChanged() {
        guard phase == .listening else { return }
        listener.stop()
        startListening()
    }
}
