@preconcurrency import AVFoundation
@preconcurrency import Speech
import UIKit

// The real microphone, recogniser, voice and audio session behind `HandsFreeController`. None of this runs in the
// simulator in any useful way; the controller's logic is tested with fakes.

/// The commands are English, so recognise English: the phone's own English (en-AU, en-GB...) if it is set to one,
/// otherwise US English.
private let commandLocale: Locale = Locale.current.language.languageCode == .english ? Locale.current : Locale(identifier: "en-US")

/// The request is fed from the audio thread and ended from the main actor; it is documented as safe for that.
private final class RequestBox: @unchecked Sendable {
    let request = SFSpeechAudioBufferRecognitionRequest()
}

@MainActor
final class LiveSpeechListener: SpeechListening {
    private lazy var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: commandLocale)
    private var engine: AVAudioEngine?
    private var box: RequestBox?
    private var task: SFSpeechRecognitionTask?
    /// Bumped by every start and stop, so callbacks from an old task are ignored.
    private var generation = 0

    var supportsOnDeviceRecognition: Bool { recognizer?.supportsOnDeviceRecognition == true }

    func start(onResult: @escaping @MainActor (String, Bool) -> Void, onEnd: @escaping @MainActor (Error?) -> Void) throws {
        stop()
        guard let recognizer, recognizer.supportsOnDeviceRecognition else { throw HandsFreeError.unsupported }
        guard recognizer.isAvailable else { throw HandsFreeError.unavailable }
        generation += 1
        let current = generation

        let box = RequestBox()
        box.request.shouldReportPartialResults = true
        box.request.requiresOnDeviceRecognition = true          // never send audio to Apple's servers
        box.request.addsPunctuation = false
        box.request.taskHint = .search
        box.request.contextualStrings = ["next step", "go back", "previous", "repeat", "ingredients", "what do I need", "how much",
                                         "set a timer for", "start the timer", "stop listening"]

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw HandsFreeError.noInput }
        Self.installTap(on: input, format: format, box: box)
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }

        let deliver: @Sendable (Event) -> Void = { [weak self] event in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                switch event {
                case .result(let text, let isFinal):
                    onResult(text, isFinal)
                    if isFinal { self.stop(); onEnd(nil) }
                case .ended(let error):
                    self.stop(); onEnd(error)
                }
            }
        }
        self.engine = engine
        self.box = box
        task = Self.recognise(with: recognizer, box: box, deliver: deliver)
    }

    func stop() {
        generation += 1
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        box?.request.endAudio()
        task?.cancel()
        engine = nil; box = nil; task = nil
    }

    private enum Event: Sendable { case result(String, Bool), ended(SendableError?) }

    // Built outside the main actor on purpose: these closures run on the audio thread and the Speech queue, and a
    // main-actor closure there would trap under Swift 6's isolation checks.
    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, box: RequestBox) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in box.request.append(buffer) }
    }

    nonisolated private static func recognise(with recognizer: SFSpeechRecognizer, box: RequestBox,
                                              deliver: @escaping @Sendable (Event) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: box.request) { result, error in
            if let result { deliver(.result(result.bestTranscription.formattedString, result.isFinal)) }
            if let error, result?.isFinal != true { deliver(.ended(SendableError(error))) }
        }
    }
}

enum HandsFreeError: Error { case unsupported, unavailable, noInput }

/// An error's description, carried across actors.
struct SendableError: Error, Sendable {
    let message: String
    init(_ error: Error) { message = (error as NSError).localizedDescription }
}

@MainActor
final class LiveSpeaker: NSObject, SpeechSpeaking, AVSpeechSynthesizerDelegate {
    /// Made on first use: cook mode's view is rebuilt often and most cooks never turn hands-free on.
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true   // speak through the session LiveHandsFreeAudio set up
        return synthesizer
    }()
    private var onDone: (@MainActor () -> Void)?

    func speak(_ text: String, onDone: @escaping @MainActor () -> Void) {
        self.onDone = onDone
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: commandLocale.identifier(.bcp47))
        // With VoiceOver on, use the voice and rate the cook already chose there.
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        let done = onDone
        onDone = nil
        done?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}

/// The audio session for hands-free.
///
/// `.playAndRecord` because it records and speaks. Options:
/// - `.mixWithOthers`: the cook's music or podcast keeps playing; Spoonmate never takes over Now Playing.
/// - `.defaultToSpeaker`: `.playAndRecord` would otherwise speak through the earpiece, which nobody hears at the stove.
/// - `.allowBluetoothA2DP`: speech goes to AirPods or a speaker in full quality. Not `.allowBluetoothHFP`: that would
///   switch them to the call profile and make the music sound like a phone call; the phone's own microphone listens.
/// - `.duckOthers`, only while speaking: the music dips under a step being read, then comes back. Ducking only ends
///   when the session deactivates, so the session is cycled (deactivate with notify-others, reactivate) on the way
///   back to listening.
/// Haptics and system sounds are allowed while recording, which iOS mutes by default: the command haptic, and
/// notification-fallback timer sounds in the foreground. AlarmKit alarms are system alarms and ring regardless; an
/// interruption (call, Siri, alarm) pauses hands-free and it resumes afterwards.
@MainActor
final class LiveHandsFreeAudio: HandsFreeAudio {
    private var current: AudioUse?
    private var observers: [NSObjectProtocol] = []
    /// Set by `HandsFreeController.init`.
    var onInterruptionBegan: (@MainActor () -> Void)?
    var onInterruptionEnded: (@MainActor () -> Void)?
    var onRouteChange: (@MainActor () -> Void)?

    func prepare(for use: AudioUse) throws {
        let session = AVAudioSession.sharedInstance()
        if current != use {
            if current == .speaking {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)   // un-duck the music
            }
            var options: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
            if use == .speaking { options.insert(.duckOthers) }
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        }
        try session.setActive(true)
        current = use
        observe()
    }

    func release() {
        current = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                if type == .began { self?.current = nil; self?.onInterruptionBegan?() }
                else if type == .ended { self?.onInterruptionEnded?() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.onRouteChange?() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            // Everything audio was torn down: set the session up again from scratch.
            MainActor.assumeIsolated { self?.current = nil; self?.onInterruptionBegan?(); self?.onInterruptionEnded?() }
        })
    }
}

@MainActor
final class LivePermissions: HandsFreePermissions {
    var status: PermissionStatus {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        if speech == .authorized && mic == .granted { return .granted }
        if speech == .denied || speech == .restricted || mic == .denied { return .denied }
        return .undetermined
    }

    func request() async -> Bool {
        guard await Self.requestSpeech() == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Nonisolated: the callback arrives on a background queue.
    nonisolated private static func requestSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
