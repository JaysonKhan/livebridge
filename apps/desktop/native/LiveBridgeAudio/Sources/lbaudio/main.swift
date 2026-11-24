// lbaudio — diagnostics for the LiveBridge audio engine, usable without the Flutter app.
//
//   lbaudio devices                          list audio devices (stable UIDs, rates, channels)
//   lbaudio processes                        list processes that currently own audio (meeting apps, browser helpers)
//   lbaudio tone  --uid UID [--seconds 1] [--db -20]     play a test tone on an output device
//   lbaudio mic   [--uid UID] [--seconds 2] [--out F.pcm] capture an input device and report levels (optionally save it)
//   lbaudio tap   --pid PID [--pid PID] [--seconds 3]    tap the audio of the given processes and report levels
//   lbaudio loopback --uid UID [--seconds 1]             write a tone to a virtual device and read it back from it
//   lbaudio session --gateway URL --token T [options]    run a whole session headlessly (see `session --help`)
import AVFoundation
import Foundation
import LiveBridgeAudioCore

let arguments = Array(CommandLine.arguments.dropFirst())

func values(_ name: String) -> [String] {
    arguments.indices.filter { arguments[$0] == "--\(name)" && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
}
func value(_ name: String) -> String? { values(name).first }
func number(_ name: String, default fallback: Double) -> Double { value(name).flatMap(Double.init) ?? fallback }
func flag(_ name: String) -> Bool { arguments.contains("--\(name)") }

func printJSON(_ object: Any) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("lbaudio: \(message)\n".utf8))
    exit(1)
}

func device(_ uid: String?, wantInput: Bool) -> AudioDeviceInfo {
    let all = AudioDevices.all()
    if let uid {
        guard let found = all.first(where: { $0.uid == uid }) else { fail("no device with uid \(uid)") }
        return found
    }
    guard let found = all.first(where: { wantInput ? $0.isDefaultInput : $0.isDefaultOutput }) else {
        fail("no default \(wantInput ? "input" : "output") device")
    }
    return found
}

/// 100 ms chunks of a 440 Hz sine as 24 kHz s16le, the format synthesized speech arrives in.
func toneChunks(seconds: Double, amplitude: Double = 0.5) -> [Data] {
    let rate = 24_000.0
    var phase = 0
    return (0..<Int(seconds * 10)).map { _ in
        var samples = [Int16](repeating: 0, count: Int(rate / 10))
        for i in samples.indices {
            samples[i] = Int16(amplitude * 32767 * sin(2 * .pi * 440 * Double(phase) / rate))
            phase += 1
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

final class LevelStats: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var peak = -120.0
    private var sum = 0.0
    func add(_ level: Double) {
        lock.lock()
        frames += 1
        peak = max(peak, level)
        sum += level
        lock.unlock()
    }
    func report(seconds: Double) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return [
            "frames": frames, "expectedFrames": Int(seconds * 50),
            "peakDb": (peak * 10).rounded() / 10,
            "meanDb": frames > 0 ? (sum / Double(frames) * 10).rounded() / 10 : -120,
        ]
    }
}

func microphoneStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "granted"
    case .denied, .restricted: return "denied"
    default: return "undetermined"
    }
}

/// Captures a device for a while and reports levels; with `--out FILE` also saves what was heard as 16 kHz mono s16le.
func capture(deviceID: AudioObjectID, label: String, seconds: Double) throws -> [String: Any] {
    let source = try CaptureSource(deviceID: deviceID, label: label)
    let stats = LevelStats()
    let recordingLock = NSLock()
    var recording = Data()
    let keep = value("out") != nil
    source.onFrame = { frame, level in
        stats.add(level)
        if keep {
            recordingLock.lock()
            recording.append(frame)
            recordingLock.unlock()
        }
    }
    try source.start()
    Thread.sleep(forTimeInterval: seconds)
    source.stop()
    if let path = value("out") { try recording.write(to: URL(fileURLWithPath: path)) }
    var report = stats.report(seconds: seconds)
    report["deviceSampleRate"] = source.sampleRate
    report["overruns"] = source.overruns
    return report
}

do {
    switch arguments.first {
    case "devices":
        printJSON(AudioDevices.all().map(\.dictionary))

    case "processes":
        printJSON(AudioProcesses.all().map(\.dictionary))

    case "tone":
        let target = device(value("uid"), wantInput: false)
        let seconds = number("seconds", default: 1)
        let sink = try PlaybackSink(deviceID: target.id, gain: Float(pow(10, number("db", default: -20) / 20)))
        try sink.start()
        let started = Date()
        for chunk in toneChunks(seconds: seconds, amplitude: 1) {
            sink.write(pcm16: chunk, rate: 24_000)
            Thread.sleep(forTimeInterval: 0.05)  // arrives faster than real time, like synthesized speech
        }
        sink.endInput()
        let queued = sink.written
        while sink.consumed < queued, Date().timeIntervalSince(started) < seconds + 3 { Thread.sleep(forTimeInterval: 0.01) }
        let elapsed = Date().timeIntervalSince(started)
        sink.stop()
        printJSON([
            "device": target.name, "deviceSampleRate": sink.sampleRate, "samplesQueued": queued,
            "samplesPlayed": sink.consumed, "underruns": sink.underruns,
            "elapsedSeconds": (elapsed * 1000).rounded() / 1000,
        ])

    case "mic":
        let target = device(value("uid"), wantInput: true)
        var status = microphoneStatus()
        if status == "undetermined" {
            let answered = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { _ in answered.signal() }
            _ = answered.wait(timeout: .now() + 30)
            status = microphoneStatus()
        }
        var report = try capture(deviceID: target.id, label: "mic", seconds: number("seconds", default: 2))
        report["device"] = target.name
        report["microphonePermission"] = status
        printJSON(report)

    case "tap":
        let pids = values("pid").compactMap { pid_t($0) }
        let tap = try ProcessTap(pids: pids)
        var report = try capture(deviceID: tap.deviceID, label: "tap", seconds: number("seconds", default: 3))
        report["pids"] = pids.map { Int($0) }
        printJSON(report)

    case "loopback":
        // A virtual microphone driver (BlackHole) presents what is written to its output on its input.
        let target = device(value("uid"), wantInput: false)
        guard target.inputChannels > 0, target.outputChannels > 0 else {
            fail("\(target.name) is not a loopback device (needs both input and output channels)")
        }
        let seconds = number("seconds", default: 1)
        let source = try CaptureSource(deviceID: target.id, label: "loopback")
        let stats = LevelStats()
        source.onFrame = { _, level in stats.add(level) }
        let sink = try PlaybackSink(deviceID: target.id)
        try source.start()
        try sink.start()
        for chunk in toneChunks(seconds: seconds) { sink.write(pcm16: chunk, rate: 24_000) }
        sink.endInput()
        Thread.sleep(forTimeInterval: seconds + 0.5)
        sink.stop()
        source.stop()
        var report = stats.report(seconds: seconds + 0.5)
        report["device"] = target.name
        report["expectedPeakDb"] = -9.0
        report["underruns"] = sink.underruns
        printJSON(report)

    case "session":
        try runSession()

    default:
        print("usage: lbaudio devices | processes | tone | mic | tap | loopback | session   (see the header of main.swift)")
        exit(arguments.isEmpty ? 0 : 1)
    }
} catch {
    fail("\(error)")
}
