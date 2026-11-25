import Foundation
import LiveBridgeAudioCore

/// Runs a whole session without the Flutter UI: connects to a gateway, presses push-to-talk a few times and prints
/// every engine event as a JSON line, then a summary. Used for end-to-end and latency checks.
///
///   lbaudio session --gateway http://127.0.0.1:8201 --token TOKEN
///       [--mic UID] [--headphones UID] [--virtual-mic UID] [--pid PID ...]
///       [--my-lang uz] [--target en]    the owner's and the remote participant's language codes
///       [--mode bidirectional|incoming|captions] [--commit manual|vad|turn_prediction]
///       [--turns 3] [--hold 1.5]        number of push-to-talk turns and how long each is held (seconds)
///       [--synthetic-mic]               send a generated tone instead of opening the microphone
///       [--mic-file speech.pcm]         send this 16 kHz mono s16le recording on every turn instead (implies
///                                       --synthetic-mic; each turn is held for the recording's length)
///       [--gain-db -70]                 attenuate everything played (inaudible hardware runs)
///       [--panic-during-turn N]         call panic while turn N is playing and measure how fast playback stops
func runSession() throws {
    guard let gateway = value("gateway"), let token = value("token") else { fail("session needs --gateway and --token") }
    let devices = AudioDevices.all()
    var settings: [String: Any] = [
        "gatewayUrl": gateway,
        "accessToken": token,
        "micUid": value("mic") ?? devices.first(where: \.isDefaultInput)?.uid ?? "",
        "headphonesUid": value("headphones") ?? devices.first(where: \.isDefaultOutput)?.uid ?? "",
        "sourcePids": values("pid").compactMap { Int($0) },
        "myLang": value("my-lang") ?? "uz",
        "targetLang": value("target") ?? "en",
        "mode": value("mode") ?? "bidirectional",
        "outCommit": value("commit") ?? "manual",
    ]
    if let virtualMic = value("virtual-mic") { settings["virtualMicUid"] = virtualMic }
    guard var config = EngineConfig(dictionary: settings) else { fail("invalid session options") }
    config.syntheticMic = flag("synthetic-mic")
    var micFileSeconds: Double?
    if let path = value("mic-file") {
        guard let audio = FileManager.default.contents(atPath: path), audio.count >= 3200 else { fail("cannot read --mic-file \(path)") }
        config.syntheticMic = true
        config.syntheticMicAudio = audio
        micFileSeconds = Double(audio.count) / 32_000
    }
    config.outputGain = Float(pow(10, number("gain-db", default: 0) / 20))

    let turns = Int(number("turns", default: 3))
    // With a recording, release right as the speech ends — that is the "end of speech" the latency is measured from.
    let hold = micFileSeconds ?? number("hold", default: 1.5)
    let panicTurn = Int(number("panic-during-turn", default: 0))

    final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var state = "idle"
        var outReady = false
        var endToEnd: [Int] = []
        var stages: [[String: Any]] = []
        var errors: [String] = []
        var counts: [String: Int] = [:]
        var lastOutQueueMs = 0.0
        func sync<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }
    }
    let recorder = Recorder()
    let engine = Engine()
    engine.onEvent = { event in
        let type = event["type"] as? String ?? "?"
        recorder.sync {
            recorder.counts[type, default: 0] += 1
            switch type {
            case "state":
                recorder.state = event["state"] as? String ?? "?"
                recorder.outReady = event["outReady"] as? Bool ?? false
            case "metrics":
                if let ms = event["e2eMs"] as? Int, event["sttCommitMs"] == nil { recorder.endToEnd.append(ms) }
                if event["translateTotalMs"] != nil { recorder.stages.append(event.filter { $0.key != "type" }) }
            case "error":
                recorder.errors.append("\(event["code"] ?? "?"): \(event["message"] ?? "")")
            case "meters":
                recorder.lastOutQueueMs = event["outQueueMs"] as? Double ?? 0
            default: break
            }
        }
        if type != "meters", let line = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) {
            print(String(data: line, encoding: .utf8)!)
        }
    }

    func waitUntil(_ timeout: Double, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if recorder.sync(condition) { return true }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return false
    }

    engine.start(config)
    guard waitUntil(10, { recorder.outReady && ["ready", "active"].contains(recorder.state) }) else {
        engine.stop()
        Thread.sleep(forTimeInterval: 0.3)
        fail("session did not become ready: \(recorder.sync { recorder.errors })")
    }

    var panicStopMs: Double?
    for turn in 1...max(1, turns) {
        let before = recorder.sync { recorder.endToEnd.count }
        engine.pttDown()
        Thread.sleep(forTimeInterval: hold)
        engine.pttUp()
        guard config.mode == .bidirectional else {
            Thread.sleep(forTimeInterval: 1)
            continue
        }
        guard waitUntil(10, { recorder.endToEnd.count > before }) else {
            recorder.sync { recorder.errors.append("turn \(turn): no audible translation within 10 s") }
            continue
        }
        if turn == panicTurn {
            // Let some audio queue up, then measure from the panic call to an empty, silent playback queue.
            Thread.sleep(forTimeInterval: 0.15)
            let started = Date()
            engine.panic()
            _ = waitUntil(2, { recorder.state == "idle" })
            panicStopMs = Date().timeIntervalSince(started) * 1000
            break
        }
        // Wait for the gateway's stage timings and for the turn to finish playing before the next one.
        _ = waitUntil(10, { recorder.stages.count >= turn })
        Thread.sleep(forTimeInterval: 0.25)
        _ = waitUntil(8, { recorder.lastOutQueueMs == 0 })
        Thread.sleep(forTimeInterval: 0.2)
    }

    if panicStopMs == nil {
        engine.stop()
        _ = waitUntil(3, { recorder.state == "idle" })
    }
    Thread.sleep(forTimeInterval: 0.2)

    let summary: [String: Any] = recorder.sync {
        var summary: [String: Any] = [
            "eventCounts": recorder.counts,
            "endToEndMs": recorder.endToEnd,
            "serverStages": recorder.stages,
            "errors": recorder.errors,
            "finalState": recorder.state,
        ]
        if let panicStopMs { summary["panicToIdleMs"] = (panicStopMs * 10).rounded() / 10 }
        return summary
    }
    print("--- summary ---")
    printJSON(summary)
    if !recorder.sync({ recorder.errors.isEmpty }) { exit(2) }
}
