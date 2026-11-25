import CoreAudio
import Foundation

public struct EngineConfig: Sendable {
    public enum Mode: String, Sendable { case captions, incoming, bidirectional }

    public var gatewayURL: URL
    public var accessToken: String
    public var micUid: String
    public var headphonesUid: String
    public var virtualMicUid: String?
    public var sourcePids: [pid_t]
    /// The owner's language and the remote participant's language: codes from the protocol's language table
    /// (packages/protocol/src/languages.ts). The gateway refuses a code it does not know.
    public var myLang: String
    public var targetLang: String
    public var mode: Mode
    /// "manual" (push-to-talk), "vad" or "turn_prediction".
    public var outCommit: String
    public var translationModel: String?
    /// Linear gain applied to everything this session plays. Diagnostics use a tiny value for inaudible runs.
    public var outputGain: Float = 1
    /// Diagnostics only: feed a generated tone instead of opening the microphone.
    public var syntheticMic = false
    /// Diagnostics only, with `syntheticMic`: 16 kHz mono s16le speech played from its start each time
    /// push-to-talk goes down (silence once it runs out), instead of the tone.
    public var syntheticMicAudio: Data?

    public init?(dictionary: [String: Any]) {
        guard let url = (dictionary["gatewayUrl"] as? String).flatMap(URL.init(string:)), url.scheme?.hasPrefix("http") == true,
            let token = dictionary["accessToken"] as? String, !token.isEmpty,
            let mic = dictionary["micUid"] as? String,
            let headphones = dictionary["headphonesUid"] as? String,
            let target = dictionary["targetLang"] as? String, Self.isLanguageCode(target),
            case let my = dictionary["myLang"] as? String ?? "uz", Self.isLanguageCode(my), my != target,
            let mode = (dictionary["mode"] as? String).flatMap(Mode.init(rawValue:)),
            let commit = dictionary["outCommit"] as? String, ["manual", "vad", "turn_prediction"].contains(commit)
        else { return nil }
        gatewayURL = url
        accessToken = token
        micUid = mic
        headphonesUid = headphones
        virtualMicUid = dictionary["virtualMicUid"] as? String
        sourcePids = (dictionary["sourcePids"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.int32Value }
        myLang = my
        targetLang = target
        self.mode = mode
        outCommit = commit
        translationModel = (dictionary["translationModel"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func isLanguageCode(_ code: String) -> Bool {
        code.range(of: "^[a-z]{2,3}$", options: .regularExpression) != nil
    }
}

/// Owns the audio devices, both playback queues and the gateway connection for one call.
///
/// Every public method is safe to call from any thread; work runs on one private serial queue, and `onEvent`
/// (maps shaped per docs/bridge-contract.md) is delivered on that queue.
public final class Engine: @unchecked Sendable {
    public var onEvent: (([String: Any]) -> Void)?

    private typealias Direction = AudioFrame.Direction
    private enum Phase: String { case idle, connecting, ready, active, degraded, stopping }

    private struct PlayingTurn {
        let id: UInt32
        /// Sink sample position where this turn's audio starts / ends (nil until its last frame arrived).
        let start: Int64
        var end: Int64?
        var started = false
    }

    private static let maxReconnectAttempts = 5

    private let queue = DispatchQueue(label: "livebridge.engine", qos: .userInteractive)
    private var phase = Phase.idle
    private var config: EngineConfig?
    private var transport: GatewayTransport?
    private var mic: CaptureSource?
    private var syntheticMic: DispatchSourceTimer?
    private var syntheticMicOffset = 0
    private var tap: ProcessTap?
    private var tapCapture: CaptureSource?
    private var sinks: [Direction: PlaybackSink] = [:]

    private var generation: [Direction: UInt32] = [.out: 1, .in: 1]
    private var captureSequence: [Direction: UInt32] = [.out: 0, .in: 0]
    private var directionReady: [Direction: Bool] = [.out: false, .in: false]
    private var synthRate = 24_000.0
    private var playing: [Direction: [PlayingTurn]] = [.out: [], .in: []]
    private var inCaptureStarted = false
    private var outCaptureOpen = false
    private var pttHeld = false
    private var outgoingMuted = false
    private var incomingAudioMuted = false
    private var bypass = false
    private var mock = false
    private var statusMessage: String?
    private var reconnectAttempt = 0
    /// When push-to-talk was last released, until the turn it produced becomes audible (end-to-end latency probe).
    private var releasedAtUs: UInt64?
    private var endToEndMs: [UInt32: Int] = [:]
    /// The gateway numbers turns from 1 in every connection. The UI needs ids that stay unique for as long as the
    /// app runs, so each new connection's ids are offset by the highest id already shown.
    private var turnBase: [Direction: Int] = [.out: 0, .in: 0]
    private var highestTurn: [Direction: Int] = [.out: 0, .in: 0]
    private var lastBacklogWarningUs: UInt64 = 0
    /// Automatic turn modes only: the microphone is not forwarded while translated incoming speech is playing (and
    /// for a moment after), so that speech coming out of loudspeakers is not picked up and translated back.
    private var echoHoldUntilUs: UInt64 = 0
    private static let echoTailUs: UInt64 = 400_000

    private let micLevel = AtomicValue(-1200)
    private let sourceLevel = AtomicValue(-1200)
    private var meterMic: CaptureSource?
    private var meterTap: ProcessTap?
    private var meterTapCapture: CaptureSource?
    private var meterTimer: DispatchSourceTimer?
    private var playbackTimer: DispatchSourceTimer?
    private var watchTimer: DispatchSourceTimer?
    private var tonePlayers: [PlaybackSink] = []
    private var stopObservingDevices: (() -> Void)?

    public init() {
        stopObservingDevices = AudioDevices.observeChanges(queue: queue) { [weak self] in self?.devicesChanged() }
    }

    deinit { stopObservingDevices?() }

    // MARK: Public commands

    public func start(_ config: EngineConfig) { queue.async { self.startSession(config) } }
    public func stop() { queue.async { self.stopSession(message: nil) } }
    public func pttDown() { queue.async { self.pushToTalk(down: true) } }
    public func pttUp() { queue.async { self.pushToTalk(down: false) } }
    public func setOutgoingMuted(_ muted: Bool) { queue.async { self.muteOutgoing(muted) } }
    public func setBypass(_ enabled: Bool) { queue.async { self.applyBypass(enabled) } }

    public func setIncomingAudioMuted(_ muted: Bool) {
        queue.async {
            self.incomingAudioMuted = muted
            self.sinks[.in]?.isMuted = muted
            self.emitState()
        }
    }

    /// Stops everything now: queued audio is discarded, the virtual microphone goes silent, the session is closed.
    public func panic() {
        queue.async {
            // Silence first — before any teardown work — so nothing already queued is heard.
            for sink in self.sinks.values {
                sink.isMuted = true
                sink.flush()
            }
            self.stopSession(message: "Panic stop: all audio discarded")
        }
    }

    /// Level meters for the setup screen. Nothing leaves the machine.
    public func startMeters(micUid: String?, sourcePids: [pid_t]) {
        queue.async {
            self.stopMeterSources()
            guard self.phase == .idle else { return }
            do {
                if let micUid, let device = AudioDevices.device(uid: micUid), device.inputChannels > 0 {
                    let source = try CaptureSource(deviceID: device.id, label: "meter-mic")
                    source.onFrame = { [micLevel = self.micLevel] _, level in micLevel.value = Int64(level * 10) }
                    try source.start()
                    self.meterMic = source
                }
                if !sourcePids.isEmpty {
                    let tap = try ProcessTap(pids: sourcePids)
                    let source = try CaptureSource(deviceID: tap.deviceID, label: "meter-tap")
                    source.onFrame = { [sourceLevel = self.sourceLevel] _, level in sourceLevel.value = Int64(level * 10) }
                    try source.start()
                    self.meterTap = tap
                    self.meterTapCapture = source
                }
            } catch {
                self.emitError(error, fatal: false)
            }
            self.startMeterTimer()
        }
    }

    public func stopMeters() {
        queue.async {
            self.stopMeterSources()
            if self.phase == .idle { self.stopMeterTimer() }
        }
    }

    /// Plays a quiet one-second 440 Hz tone on an output device so the user can confirm the route.
    public func testTone(uid: String) {
        queue.async {
            guard let device = AudioDevices.device(uid: uid), device.outputChannels > 0,
                let sink = try? PlaybackSink(deviceID: device.id), (try? sink.start()) != nil
            else { return self.emit(["type": "error", "code": "device", "message": "cannot open that output device", "fatal": false]) }
            let rate = 24_000.0
            let samples = (0..<Int(rate)).map { Int16(0.05 * 32767 * sin(2 * .pi * 440 * Double($0) / rate)) }
            sink.write(pcm16: samples.withUnsafeBufferPointer { Data(buffer: $0) }, rate: rate)
            sink.endInput()
            self.tonePlayers.append(sink)
            self.queue.asyncAfter(deadline: .now() + 1.5) {
                sink.stop()
                self.tonePlayers.removeAll { $0 === sink }
            }
        }
    }

    // MARK: Session lifecycle

    private func startSession(_ config: EngineConfig) {
        guard phase == .idle else { return emit(["type": "error", "code": "busy", "message": "a session is already running", "fatal": false]) }
        stopMeterSources()
        do {
            if let reason = unsafeRouteReason(micUid: config.micUid, headphonesUid: config.headphonesUid, virtualMicUid: config.virtualMicUid) {
                throw AudioEngineError("unsafe_route", reason)
            }
            let incomingEnabled = !config.sourcePids.isEmpty
            if config.mode == .bidirectional {
                guard let uid = config.virtualMicUid, let device = AudioDevices.device(uid: uid), device.outputChannels > 0 else {
                    throw AudioEngineError("no_virtual_mic", "bidirectional speech needs the virtual microphone (BlackHole 2ch)")
                }
                sinks[.out] = try PlaybackSink(deviceID: device.id, gain: config.outputGain)
            }
            if config.mode != .captions && incomingEnabled {
                guard let device = AudioDevices.device(uid: config.headphonesUid), device.outputChannels > 0, !device.isVirtual else {
                    throw AudioEngineError("no_headphones", "choose a physical output device for incoming audio")
                }
                sinks[.in] = try PlaybackSink(deviceID: device.id, gain: config.outputGain)
            }
            for sink in sinks.values { try sink.start() }

            if config.syntheticMic {
                startSyntheticMic()
            } else {
                guard let device = AudioDevices.device(uid: config.micUid), device.inputChannels > 0 else {
                    throw AudioEngineError("no_microphone", "the selected microphone is not available")
                }
                let source = try CaptureSource(deviceID: device.id, label: "mic")
                source.onFrame = { [weak self, micLevel] data, level in
                    micLevel.value = Int64(level * 10)
                    self?.queue.async { self?.captured(data, direction: .out) }
                }
                try source.start()
                mic = source
            }
            if incomingEnabled {
                let tap = try ProcessTap(pids: config.sourcePids)
                let source = try CaptureSource(deviceID: tap.deviceID, label: "tap")
                source.onFrame = { [weak self, sourceLevel] data, level in
                    sourceLevel.value = Int64(level * 10)
                    self?.queue.async { self?.captured(data, direction: .in) }
                }
                try source.start()
                self.tap = tap
                tapCapture = source
            }
        } catch {
            releaseAudio()
            return emitError(error, fatal: true)
        }

        self.config = config
        phase = .connecting
        statusMessage = nil
        reconnectAttempt = 0
        startMeterTimer()
        startSessionTimers()
        emitState()
        connect()
    }

    private func connect() {
        guard let config else { return }
        let transport = GatewayTransport(queue: queue)
        transport.onMessage = { [weak self] in self?.received($0) }
        transport.onFrame = { [weak self] in self?.receivedFrame($0) }
        transport.onClosed = { [weak self] reason in self?.connectionLost(reason) }
        self.transport = transport
        transport.connect(baseURL: config.gatewayURL, accessToken: config.accessToken) { [weak self] result in
            guard let self, self.transport === transport else { return }
            switch result {
            case .failure(let error):
                // First connection: fail loudly. Later ones are retries of a session that was already running.
                if self.phase == .connecting {
                    self.emitError(error, fatal: true)
                    self.stopSession(message: nil)
                } else {
                    self.connectionLost(error.message)
                }
            case .success:
                let incomingEnabled = !config.sourcePids.isEmpty
                var configure: [String: Any] = [
                    "type": "session.configure",
                    "capture_format": ["encoding": "pcm_s16le", "sample_rate": 16000, "channels": 1],
                    "directions": [
                        "out": [
                            "enabled": true, "source_lang": config.myLang, "target_lang": config.targetLang,
                            "speak": config.mode == .bidirectional, "commit": config.outCommit,
                        ],
                        "in": [
                            "enabled": incomingEnabled, "source_lang": config.targetLang, "target_lang": config.myLang,
                            "speak": config.mode != .captions, "commit": "vad",
                        ],
                    ],
                ]
                if let model = config.translationModel { configure["translation_model"] = model }
                transport.send(configure)
            }
        }
    }

    private func connectionLost(_ reason: String) {
        guard phase != .idle, phase != .stopping else { return }
        transport?.close()
        transport = nil
        // Nothing captured or synthesized before the drop may be replayed after it.
        fenceAll()
        directionReady = [.out: false, .in: false]
        inCaptureStarted = false
        outCaptureOpen = false
        pttHeld = false
        reconnectAttempt += 1
        guard reconnectAttempt <= Self.maxReconnectAttempts else {
            emit(["type": "error", "code": "gateway_unreachable", "message": "connection lost and could not be restored: \(reason)", "fatal": true])
            return stopSession(message: nil)
        }
        phase = .degraded
        statusMessage = "Connection lost — reconnecting (attempt \(reconnectAttempt) of \(Self.maxReconnectAttempts))"
        emitState()
        let delay = min(8, 0.5 * pow(2, Double(reconnectAttempt - 1))) * Double.random(in: 0.5...1)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.phase == .degraded, self.transport == nil else { return }
            self.connect()
        }
    }

    private func stopSession(message: String?) {
        guard phase != .idle else {
            if let message { statusMessage = message }
            return emitState()
        }
        phase = .stopping
        emitState()
        fenceAll()
        transport?.close()
        transport = nil
        releaseAudio()
        stopSessionTimers()
        stopMeterTimer()
        config = nil
        directionReady = [.out: false, .in: false]
        inCaptureStarted = false
        outCaptureOpen = false
        pttHeld = false
        outgoingMuted = false
        incomingAudioMuted = false
        bypass = false
        mock = false
        releasedAtUs = nil
        endToEndMs.removeAll()
        phase = .idle
        statusMessage = message
        emitState()
    }

    /// Stops every device this session opened. After this the virtual microphone carries silence.
    private func releaseAudio() {
        mic?.stop()
        mic = nil
        syntheticMic?.cancel()
        syntheticMic = nil
        tapCapture?.stop()
        tapCapture = nil
        tap = nil
        for sink in sinks.values { sink.stop() }
        sinks.removeAll()
    }

    /// Moves both directions to a new generation and empties both playback queues.
    private func fenceAll() {
        for direction in [Direction.out, .in] {
            generation[direction]! += 1
            captureSequence[direction] = 0
            playing[direction] = []
            sinks[direction]?.flush()
        }
        releasedAtUs = nil
        endToEndMs.removeAll()
        turnBase = highestTurn
    }

    /// Cancels whatever is in flight for one direction, locally and on the gateway.
    private func cancel(_ direction: Direction) {
        generation[direction]! += 1
        captureSequence[direction] = 0
        playing[direction] = []
        sinks[direction]?.flush()
        if direction == .out {
            releasedAtUs = nil
            outCaptureOpen = false
        }
        transport?.send(["type": "turn.cancel", "direction": direction.name, "generation": Int(generation[direction]!)])
    }

    // MARK: Controls

    private func pushToTalk(down: Bool) {
        guard let config, config.outCommit == "manual" else { return }
        if down {
            guard phase == .ready || phase == .active, directionReady[.out] == true, !outgoingMuted, !bypass, !pttHeld else { return }
            pttHeld = true
            syntheticMicOffset = 0
            transport?.send(["type": "capture.start", "direction": "out", "generation": Int(generation[.out]!)])
        } else {
            guard pttHeld else { return }
            pttHeld = false
            // Frames are sent in order on the same socket, so the commit always follows the last captured frame.
            transport?.send(["type": "turn.commit", "direction": "out"])
            transport?.send(["type": "capture.pause", "direction": "out"])
            releasedAtUs = monotonicMicroseconds()
        }
        emitState()
    }

    private func muteOutgoing(_ muted: Bool) {
        outgoingMuted = muted
        if muted {
            pttHeld = false
            if phase != .idle { cancel(.out) }
        }
        openHandsFreeCaptureIfNeeded()
        emitState()
    }

    private func applyBypass(_ enabled: Bool) {
        guard enabled != bypass else { return }
        if enabled {
            guard sinks[.out] != nil else {
                return emit(["type": "error", "code": "no_virtual_mic", "message": "bypass needs the virtual microphone", "fatal": false])
            }
            // Translated speech stops; from here the physical microphone goes to the call directly, with no server.
            pttHeld = false
            cancel(.out)
            bypass = true
        } else {
            bypass = false
            sinks[.out]?.flush()
            openHandsFreeCaptureIfNeeded()
        }
        emitState()
    }

    /// In the automatic turn modes the outgoing capture window is open whenever it is allowed to be.
    private func openHandsFreeCaptureIfNeeded() {
        guard let config, config.outCommit != "manual", !outCaptureOpen, directionReady[.out] == true, !outgoingMuted, !bypass
        else { return }
        outCaptureOpen = true
        transport?.send(["type": "capture.start", "direction": "out", "generation": Int(generation[.out]!)])
    }

    private func displayTurn(_ direction: Direction, _ gatewayTurn: Int) -> Int {
        let id = turnBase[direction]! + gatewayTurn
        highestTurn[direction] = max(highestTurn[direction]!, id)
        return id
    }

    // MARK: Capture -> gateway

    private func captured(_ pcm: Data, direction: Direction) {
        guard phase == .ready || phase == .active else { return }
        if direction == .out {
            if bypass {
                sinks[.out]?.write(pcm16: pcm, rate: CaptureSource.outputRate)
                return
            }
            // Nothing leaves the machine unless the talk button is held (or an automatic turn mode is open).
            guard (pttHeld || outCaptureOpen), !outgoingMuted, directionReady[.out] == true else { return }
            if outCaptureOpen, !pttHeld {
                let now = monotonicMicroseconds()
                if let incoming = sinks[.in], incoming.queuedMs > 0, !incoming.isMuted { echoHoldUntilUs = now + Self.echoTailUs }
                if now < echoHoldUntilUs { return }
            }
        } else {
            guard inCaptureStarted, directionReady[.in] == true else { return }
        }
        let frame = AudioFrame(
            kind: .capture, direction: direction, generation: generation[direction]!,
            sequence: captureSequence[direction]!, timestampUs: monotonicMicroseconds(), payload: pcm)
        captureSequence[direction]! += 1
        guard let data = try? FrameCodec.encode(frame), let transport else { return }
        if !transport.send(frame: data) {
            let now = monotonicMicroseconds()
            if now - lastBacklogWarningUs > 1_000_000 {
                lastBacklogWarningUs = now
                emit([
                    "type": "error", "code": "capture_backlog", "direction": direction.name, "fatal": false,
                    "message": "the network is not keeping up; some captured audio was dropped",
                ])
            }
        }
    }

    private func startSyntheticMic() {
        var phase = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let frameBytes = CaptureSource.frameSamples * 2
            if let audio = self.config?.syntheticMicAudio {
                var frame = Data(count: frameBytes)
                let available = max(0, min(frameBytes, audio.count - self.syntheticMicOffset))
                if available > 0 {
                    frame.replaceSubrange(0..<available, with: audio.subdata(in: self.syntheticMicOffset..<self.syntheticMicOffset + available))
                }
                self.syntheticMicOffset += frameBytes
                self.captured(frame, direction: .out)
                return
            }
            var samples = [Int16](repeating: 0, count: CaptureSource.frameSamples)
            for i in samples.indices {
                samples[i] = Int16(0.3 * 32767 * sin(2 * .pi * 220 * Double(phase) / CaptureSource.outputRate))
                phase += 1
            }
            self.micLevel.value = -105
            self.captured(samples.withUnsafeBufferPointer { Data(buffer: $0) }, direction: .out)
        }
        timer.resume()
        syntheticMic = timer
    }

    // MARK: Gateway -> playback / UI

    private func received(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        let direction = (message["direction"] as? String).flatMap(Direction.init(name:))
        // Anything tagged with an older generation belongs to a cancelled turn.
        if let direction, let tagged = message["generation"] as? Int, UInt32(tagged) != generation[direction] { return }
        let turnId = message["turn_id"] as? Int ?? 0

        switch type {
        case "session.ready":
            let directions = message["directions"] as? [String: [String: Any]] ?? [:]
            for direction in [Direction.out, .in] {
                let info = directions[direction.name] ?? [:]
                directionReady[direction] = (info["enabled"] as? Bool ?? false) && (info["ready"] as? Bool ?? false)
                if let rate = info["synth_sample_rate"] as? Double { synthRate = rate }
            }
            mock = (message["providers"] as? [String: Any])?["mock"] as? Bool ?? false
            reconnectAttempt = 0
            statusMessage = nil
            if directionReady[.in] == true, !inCaptureStarted {
                inCaptureStarted = true
                transport?.send(["type": "capture.start", "direction": "in", "generation": Int(generation[.in]!)])
            }
            openHandsFreeCaptureIfNeeded()
            phase = inCaptureStarted || outCaptureOpen ? .active : .ready
            emitState()
        case "caption.partial", "caption.final", "translation.delta", "translation.final":
            guard let direction else { return }
            let kinds = ["caption.partial": "partial", "caption.final": "final", "translation.delta": "translationDelta", "translation.final": "translationFinal"]
            emit(["type": "caption", "direction": direction.name, "turnId": displayTurn(direction, turnId), "kind": kinds[type]!, "text": message["text"] as? String ?? ""])
        case "turn.skipped":
            // The turn's caption stays; it was not translated or spoken (same language, or our own speech coming back).
            guard let direction else { return }
            emit([
                "type": "caption", "direction": direction.name, "turnId": displayTurn(direction, turnId), "kind": "skipped",
                "text": "", "reason": message["reason"] as? String ?? "",
            ])
        case "metrics":
            guard let direction else { return }
            var event: [String: Any] = ["type": "metrics", "direction": direction.name, "turnId": displayTurn(direction, turnId)]
            let names = [
                "stt_commit_ms": "sttCommitMs", "translate_first_ms": "translateFirstMs", "translate_total_ms": "translateTotalMs",
                "tts_first_audio_ms": "ttsFirstAudioMs", "tts_total_ms": "ttsTotalMs", "audio_ms": "audioMs",
            ]
            for (key, name) in names { if let value = message[key] as? Int { event[name] = value } }
            if let model = message["model"] as? String { event["model"] = model }
            if direction == .out, let e2e = endToEndMs.removeValue(forKey: UInt32(turnId)) { event["e2eMs"] = e2e }
            emit(event)
        case "error":
            let fatal = message["fatal"] as? Bool ?? false
            var event: [String: Any] = [
                "type": "error", "code": message["code"] as? String ?? "error",
                "message": message["message"] as? String ?? "", "fatal": fatal,
            ]
            if let direction { event["direction"] = direction.name }
            emit(event)
            if fatal { stopSession(message: nil) }
        default:
            break
        }
    }

    private func receivedFrame(_ data: Data) {
        guard let frame = try? FrameCodec.decode(data), frame.kind == .synthesized,
            frame.generation == generation[frame.direction], let sink = sinks[frame.direction]
        else { return }
        // Muted or bypassed outgoing speech is discarded on arrival, never queued for later.
        if frame.direction == .out, outgoingMuted || bypass { return }

        if !frame.payload.isEmpty {
            if playing[frame.direction]?.last?.id != frame.turnId {
                playing[frame.direction]!.append(PlayingTurn(id: frame.turnId, start: sink.written))
            }
            if !sink.write(pcm16: frame.payload, rate: synthRate) {
                emit([
                    "type": "error", "code": "playback_overflow", "direction": frame.direction.name, "fatal": false,
                    "message": "translated audio queue is full; this turn was dropped",
                ])
                return cancel(frame.direction)
            }
        }
        if frame.isEndOfTurn {
            sink.endInput()
            if let index = playing[frame.direction]!.lastIndex(where: { $0.id == frame.turnId }) {
                playing[frame.direction]![index].end = sink.written
            }
        }
    }

    /// Runs every 20 ms: reports when a turn actually becomes audible and when it has finished playing.
    private func observePlayback() {
        for direction in [Direction.out, .in] {
            guard let sink = sinks[direction], var turns = playing[direction], !turns.isEmpty else { continue }
            let consumed = sink.consumed
            for index in turns.indices where !turns[index].started && consumed > turns[index].start {
                turns[index].started = true
                transport?.send(["type": "playback.start", "direction": direction.name, "turn_id": Int(turns[index].id), "generation": Int(generation[direction]!)])
                if direction == .out, let released = releasedAtUs {
                    releasedAtUs = nil
                    let ms = Int((monotonicMicroseconds() - released) / 1000)
                    endToEndMs[turns[index].id] = ms
                    // The gateway's metrics message for a turn usually arrives after its audio started; if it
                    // came first, publish the client-side figure on its own.
                    emit(["type": "metrics", "direction": "out", "turnId": displayTurn(.out, Int(turns[index].id)), "e2eMs": ms])
                }
            }
            turns.removeAll { turn in
                guard let end = turn.end, consumed >= end else { return false }
                transport?.send(["type": "playback.end", "direction": direction.name, "turn_id": Int(turn.id), "generation": Int(generation[direction]!)])
                return true
            }
            playing[direction] = turns
        }
    }

    // MARK: Device and source supervision

    private func devicesChanged() {
        emit(["type": "devicesChanged"])
        guard let config, phase != .idle, phase != .stopping else { return }
        let present = Set(AudioDevices.all().map(\.uid))
        let inUse = [config.syntheticMic ? nil : config.micUid, sinks[.in] != nil ? config.headphonesUid : nil, sinks[.out] != nil ? config.virtualMicUid : nil]
        guard inUse.compactMap({ $0 }).contains(where: { !present.contains($0) }) else { return }
        // Never re-route silently to whatever the new default is: stop and let the user choose again.
        emit(["type": "error", "code": "device_removed", "message": "an audio device in use was disconnected; the session was stopped", "fatal": true])
        stopSession(message: nil)
    }

    private func watchSources() {
        guard let tap, !tap.isAlive else { return }
        tapCapture?.stop()
        tapCapture = nil
        self.tap = nil
        directionReady[.in] = false
        sourceLevel.value = -1200
        if inCaptureStarted { transport?.send(["type": "capture.stop", "direction": "in"]) }
        inCaptureStarted = false
        emit([
            "type": "error", "code": "source_gone", "direction": "in", "fatal": false,
            "message": "the meeting app quit; incoming translation is off until you restart the session",
        ])
        emitState()
    }

    // MARK: Timers and events

    private func makeTimer(milliseconds: Int, _ handler: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(milliseconds), repeating: .milliseconds(milliseconds))
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }

    private func startSessionTimers() {
        playbackTimer = makeTimer(milliseconds: 20) { [weak self] in self?.observePlayback() }
        watchTimer = makeTimer(milliseconds: 1000) { [weak self] in self?.watchSources() }
    }

    private func stopSessionTimers() {
        playbackTimer?.cancel()
        playbackTimer = nil
        watchTimer?.cancel()
        watchTimer = nil
    }

    private func startMeterTimer() {
        guard meterTimer == nil else { return }
        meterTimer = makeTimer(milliseconds: 100) { [weak self] in
            guard let self else { return }
            self.emit([
                "type": "meters", "mic": Double(self.micLevel.value) / 10, "source": Double(self.sourceLevel.value) / 10,
                "outQueueMs": self.sinks[.out]?.queuedMs ?? 0, "inQueueMs": self.sinks[.in]?.queuedMs ?? 0,
            ])
        }
    }

    private func stopMeterTimer() {
        meterTimer?.cancel()
        meterTimer = nil
        micLevel.value = -1200
        sourceLevel.value = -1200
    }

    private func stopMeterSources() {
        meterMic?.stop()
        meterMic = nil
        meterTapCapture?.stop()
        meterTapCapture = nil
        meterTap = nil
    }

    private func emitState() {
        var event: [String: Any] = [
            "type": "state", "state": phase.rawValue,
            "outReady": directionReady[.out] ?? false, "inReady": directionReady[.in] ?? false,
            "capturing": pttHeld || outCaptureOpen || inCaptureStarted || bypass,
            "mock": mock, "bypass": bypass, "outgoingMuted": outgoingMuted, "incomingAudioMuted": incomingAudioMuted,
        ]
        if let statusMessage { event["message"] = statusMessage }
        if let config {
            // Session shape for the numbers-only analytics log (no device names, addresses or text).
            event["mode"] = config.mode.rawValue
            event["myLang"] = config.myLang
            event["targetLang"] = config.targetLang
            event["outCommit"] = config.outCommit
        }
        emit(event)
    }

    private func emitError(_ error: Error, fatal: Bool) {
        let known = error as? AudioEngineError
        emit(["type": "error", "code": known?.code ?? "error", "message": known?.message ?? "\(error)", "fatal": fatal])
    }

    private func emit(_ event: [String: Any]) { onEvent?(event) }
}
