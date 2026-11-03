import Foundation
import Testing
@testable import RecipeManager

struct VoiceCommandTests {
    private func parse(_ s: String) -> VoiceCommand? { VoiceCommand.parse(s) }
    private func timer(_ s: String) -> Int? {
        if case .setTimer(let seconds)? = parse(s) { return seconds }
        return nil
    }

    @Test func simpleCommandsIgnoreCasePunctuationAndFillers() {
        #expect(parse("next") == .next)
        #expect(parse("Next step.") == .next)
        #expect(parse("Okay, next step please") == .next)
        #expect(parse("continue") == .next)
        #expect(parse("Back") == .back)
        #expect(parse("go back") == .back)
        #expect(parse("Previous!") == .back)
        #expect(parse("repeat") == .repeatStep)
        #expect(parse("Read it again") == .repeatStep)
        #expect(parse("What's the step?") == .repeatStep)
        #expect(parse("what’s the step") == .repeatStep)
        #expect(parse("Ingredients") == .ingredients)
        #expect(parse("What do I need?") == .ingredients)
        #expect(parse("Stop listening") == .stopListening)
        #expect(parse("start the timer") == .startStepTimer)
    }

    @Test func ordinaryTalkIsNotACommand() {
        #expect(parse("we'll do that next") == nil)
        #expect(parse("put it back in the fridge") == nil)
        #expect(parse("I need to repeat myself") == nil)
        #expect(parse("") == nil)
        #expect(parse("um") == nil)
        #expect(parse("cancel the timer") == nil)
        #expect(parse("set a timer") == nil)          // no time yet: waits for more
    }

    @Test func howMuchFindsTheIngredientName() {
        #expect(parse("how much butter") == .howMuch("butter"))
        #expect(parse("How much brown sugar do I need?") == .howMuch("brown sugar"))
        #expect(parse("how many eggs") == .howMuch("eggs"))
        #expect(parse("how much of the flour") == .howMuch("flour"))
        #expect(parse("how much do I need") == .ingredients)
    }

    @Test func timersInDigitsAndWords() {
        #expect(timer("Set a timer for 10 minutes") == 600)
        #expect(timer("set a timer for ten minutes") == 600)
        #expect(timer("set a timer for twenty five minutes") == 1500)
        #expect(timer("set a timer for twenty-five minutes") == 1500)
        #expect(timer("timer for an hour") == 3600)
        #expect(timer("set a timer for an hour and a half") == 5400)
        #expect(timer("set a timer for half an hour") == 1800)
        #expect(timer("set a timer for one and a half hours") == 5400)
        #expect(timer("set a timer for 1.5 hours") == 5400)
        #expect(timer("set a timer for 1 hour 20 minutes") == 4800)
        #expect(timer("set a timer for an hour and twenty minutes") == 4800)
        #expect(timer("set a timer for a quarter of an hour") == 900)
        #expect(timer("set a timer for three quarters of an hour") == 2700)
        #expect(timer("set a timer for a minute and a half") == 90)
        #expect(timer("set a timer for 90 seconds") == 90)
        #expect(timer("set a timer for 2 hours") == 7200)
        #expect(timer("Set a 10-minute timer.") == 600)
        #expect(timer("start a five minute timer please") == 300)
        #expect(timer("set a timer for 5") == 300)                     // bare number: minutes
        #expect(timer("set a timer for a couple of minutes") == 120)
        #expect(timer("set a timer for 0 minutes") == nil)
        #expect(timer("set a timer for 20 hours") == nil)             // over ten hours: misheard
    }

    @Test func unfinishedCommandsWaitForMore() {
        #expect(VoiceCommand.isIncomplete("set a timer for"))
        #expect(VoiceCommand.isIncomplete("set a timer"))
        #expect(VoiceCommand.isIncomplete("how much"))
        #expect(VoiceCommand.isIncomplete("set a timer for an hour and"))
        #expect(!VoiceCommand.isIncomplete("we're nearly there"))
        #expect(!VoiceCommand.isIncomplete("next"))
    }

    @Test func spokenDurationsAndText() {
        #expect(VoiceCommand.spokenDuration(600) == "10 minutes")
        #expect(VoiceCommand.spokenDuration(5400) == "1 hour 30 minutes")
        #expect(VoiceCommand.spokenDuration(90) == "1 minute 30 seconds")
        #expect(VoiceCommand.spoken("1 ½ cups flour") == "1 and a half cups flour")
        #expect(VoiceCommand.spoken("½ cup milk") == "half cup milk")
        #expect(VoiceCommand.spoken("250 g butter") == "250 grams butter")
        #expect(VoiceCommand.spoken("250g butter") == "250 grams butter")
        #expect(VoiceCommand.spoken("Bake at 180°C") == "Bake at 180 degrees Celsius")
        #expect(VoiceCommand.spoken("2 tbsp oil and 1 tsp salt") == "2 tablespoons oil and 1 teaspoons salt")
        #expect(VoiceCommand.spoken("2 large eggs") == "2 large eggs")
    }

    @Test func howMuchMatchesScaledLines() {
        let lines = ["500 g plain flour", "100 g brown sugar", "50 g caster sugar", "2 eggs", "1 ½ cups milk"]
        #expect(VoiceCommand.lines(matching: "brown sugar", in: lines) == ["100 g brown sugar"])
        #expect(VoiceCommand.lines(matching: "sugar", in: lines) == ["100 g brown sugar", "50 g caster sugar"])
        #expect(VoiceCommand.lines(matching: "egg", in: lines) == ["2 eggs"])
        #expect(VoiceCommand.lines(matching: "the milk", in: lines) == ["1 ½ cups milk"])
        #expect(VoiceCommand.lines(matching: "saffron", in: lines).isEmpty)
    }
}

// MARK: The controller, with the microphone, voice and audio session faked

@MainActor private final class FakeListener: SpeechListening {
    var supportsOnDeviceRecognition = true
    var starts = 0
    var stops = 0
    var failNextStarts = 0
    private(set) var isRunning = false
    private var onResult: (@MainActor (String, Bool) -> Void)?
    private var onEnd: (@MainActor (Error?) -> Void)?

    func start(onResult: @escaping @MainActor (String, Bool) -> Void, onEnd: @escaping @MainActor (Error?) -> Void) throws {
        if failNextStarts > 0 { failNextStarts -= 1; throw HandsFreeError.noInput }
        starts += 1; isRunning = true
        self.onResult = onResult; self.onEnd = onEnd
    }
    func stop() { stops += 1; isRunning = false; onResult = nil; onEnd = nil }

    func say(_ text: String, final: Bool = false) { onResult?(text, final) }
    func end(_ error: Error? = nil) {
        let end = onEnd
        isRunning = false; onResult = nil; onEnd = nil
        end?(error)
    }
}

@MainActor private final class FakeSpeaker: SpeechSpeaking {
    var spoken: [String] = []
    private var onDone: (@MainActor () -> Void)?
    var isSpeaking: Bool { onDone != nil }
    func speak(_ text: String, onDone: @escaping @MainActor () -> Void) { spoken.append(text); self.onDone = onDone }
    func stop() { finish() }
    func finish() { let done = onDone; onDone = nil; done?() }
}

@MainActor private final class FakeAudio: HandsFreeAudio {
    var uses: [AudioUse] = []
    var releases = 0
    func prepare(for use: AudioUse) throws { uses.append(use) }
    func release() { releases += 1 }
}

@MainActor private final class FakePermissions: HandsFreePermissions {
    var status: PermissionStatus = .undetermined
    var grant = true
    var requests = 0
    func request() async -> Bool { requests += 1; status = grant ? .granted : .denied; return grant }
}

@MainActor
struct HandsFreeControllerTests {
    fileprivate let listener = FakeListener()
    fileprivate let speaker = FakeSpeaker()
    fileprivate let audio = FakeAudio()
    fileprivate let permissions = FakePermissions()
    let defaults = UserDefaults(suiteName: "handsfree-\(UUID().uuidString)")!

    private func make() -> HandsFreeController {
        let c = HandsFreeController(listener: listener, speaker: speaker, audio: audio, permissions: permissions, defaults: defaults)
        c.settleDelay = .milliseconds(20)
        c.restartDelay = .milliseconds(5)
        c.maxRestartDelay = .milliseconds(20)
        return c
    }

    /// Waits (briefly) for the controller's sleeps to run.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func offByDefaultAndRemembered() async {
        let c = make()
        #expect(!c.isEnabled)
        c.appear()
        #expect(c.phase == .off && listener.starts == 0)
        await c.setEnabled(true)
        #expect(permissions.requests == 1)
        #expect(c.isEnabled && c.phase == .listening && audio.uses == [.listening])
        #expect(make().isEnabled)                      // a new cook mode remembers
    }

    @Test func deniedPermissionTurnsItOffWithAnExplanation() async {
        permissions.grant = false
        let c = make()
        c.appear()
        await c.setEnabled(true)
        #expect(!c.isEnabled && c.phase == .off && c.notice == .denied && listener.starts == 0)
    }

    @Test func noOnDeviceRecognitionMeansNotAvailable() async {
        listener.supportsOnDeviceRecognition = false
        let c = make()
        c.appear()
        await c.setEnabled(true)
        #expect(!c.isEnabled && c.notice == .unsupported && permissions.requests == 0)
    }

    @Test func oneUtteranceFiresOnceAfterItSettles() async {
        let c = make()
        var heard: [VoiceCommand] = []
        c.onCommand = { heard.append($0) }
        c.appear()
        await c.setEnabled(true)
        listener.say("next")
        listener.say("next step")          // partials of the same utterance
        await until { !heard.isEmpty }
        try? await Task.sleep(for: .milliseconds(60))
        #expect(heard == [.next])
        #expect(c.caption == "Next step" && c.commandCount == 1)
        #expect(listener.starts == 2)      // a fresh task after the command, so the transcript starts empty
    }

    @Test func talkIsSkippedAndTheNextUtteranceStillWorks() async {
        let c = make()
        var heard: [VoiceCommand] = []
        c.onCommand = { heard.append($0) }
        c.appear()
        await c.setEnabled(true)
        listener.say("we'll do that")
        try? await Task.sleep(for: .milliseconds(60))
        listener.say("we'll do that next", final: false)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(heard == [.next])          // "next" said after a pause is its own utterance
        listener.say("set a timer for")
        try? await Task.sleep(for: .milliseconds(60))
        listener.say("set a timer for ten minutes", final: true)
        #expect(heard == [.next, .setTimer(seconds: 600)])
    }

    @Test func listeningSpeakingListening() async {
        let c = make()
        c.onCommand = { _ in c.say("Step 2. Add the onions.") }
        c.appear()
        await c.setEnabled(true)
        listener.say("next", final: true)
        #expect(c.phase == .speaking && !listener.isRunning)          // doesn't hear itself
        #expect(speaker.spoken == ["Step 2. Add the onions."] && audio.uses.last == .speaking)
        speaker.finish()
        #expect(c.phase == .listening && listener.isRunning && audio.uses.last == .listening)
    }

    @Test func restartsWhenATaskEndsAndBacksOffOnErrors() async {
        let c = make()
        c.appear()
        await c.setEnabled(true)
        listener.end()                                   // the ~1 minute limit
        await until { listener.isRunning }
        #expect(listener.starts == 2 && c.phase == .listening)
        listener.end(HandsFreeError.unavailable)        // an error
        await until { listener.isRunning }
        #expect(listener.starts == 3)
    }

    @Test func givesUpAfterRepeatedStartFailures() async {
        let c = make()
        c.appear()
        listener.failNextStarts = 5
        await c.setEnabled(true)
        await until { c.notice != nil }
        #expect(c.notice == .couldNotStart && !c.isEnabled && c.phase == .off)
    }

    @Test func interruptionsPauseAndResume() async {
        let c = make()
        c.appear()
        await c.setEnabled(true)
        c.say("Step 1.")
        c.interruptionBegan()                            // a call or Siri
        #expect(c.phase == .paused && !listener.isRunning && !speaker.isSpeaking)
        c.interruptionEnded()
        #expect(c.phase == .listening && listener.isRunning)
    }

    @Test func leavingBackgroundingAndStopListeningStopEverything() async {
        let c = make()
        c.appear()
        await c.setEnabled(true)
        c.setForeground(false)
        #expect(c.phase == .off && !listener.isRunning && audio.releases == 1)
        c.setForeground(true)
        #expect(c.phase == .listening)
        c.disappear()
        #expect(c.phase == .off && !listener.isRunning)
        c.say("ignored")
        #expect(speaker.spoken.isEmpty)                  // nothing speaks once cook mode is closed

        c.appear()
        #expect(c.phase == .listening)                   // still on: it was left on
        listener.say("stop listening", final: true)
        #expect(!c.isEnabled && c.phase == .off && c.caption == "Stopped listening")
        #expect(!make().isEnabled)
    }

    @Test func withdrawnPermissionIsNoticedOnReturn() async {
        let c = make()
        c.appear()
        await c.setEnabled(true)
        c.disappear()
        permissions.status = .denied                     // turned off in Settings meanwhile
        c.appear()
        #expect(!c.isEnabled && c.notice == .denied && c.phase == .off)
    }
}
