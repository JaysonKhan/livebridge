import CoreAudio
import Foundation

/// Samples the IO thread may handle per callback. HAL buffers are far smaller (typically 512 frames).
private let scratchFrames = 16_384

func monotonicMicroseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1000 }

private func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw AudioEngineError("coreaudio", "\(what) failed (OSStatus \(status))") }
}

/// Captures one HAL device (a physical microphone, or the private aggregate device that carries a process tap)
/// and delivers 20 ms frames of 16 kHz mono s16le on a worker queue.
///
/// Real-time thread: downmix + one lock-free ring write. Everything else (resampling, framing, metering,
/// callbacks) happens on the worker queue, which polls the ring every 10 ms.
public final class CaptureSource: @unchecked Sendable {
    public static let frameSamples = 320  // 20 ms at 16 kHz
    public static let outputRate = 16_000.0

    public let deviceID: AudioObjectID
    public let sampleRate: Double
    /// Called on the worker queue with one 20 ms frame and its level in dBFS.
    public var onFrame: ((Data, Double) -> Void)?
    /// Callbacks where the ring was full because the worker fell behind (captured audio was lost).
    public var overruns: Int64 { overrunCount.value }

    private let ring: RingBuffer
    private let overrunCount = AtomicValue()
    private let scratch: UnsafeMutablePointer<Float>
    private let drain: UnsafeMutablePointer<Float>
    private let drainCapacity: Int
    private let resampler: StreamResampler
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var procID: AudioDeviceIOProcID?
    private var pending: [Int16] = []

    public init(deviceID: AudioObjectID, label: String) throws {
        self.deviceID = deviceID
        guard let rate = HAL.value(deviceID, kAudioDevicePropertyNominalSampleRate, default: Float64(0)), rate > 0
        else { throw AudioEngineError("device", "cannot read the sample rate of the \(label) device") }
        sampleRate = rate
        // 500 ms of capture may wait for the worker; beyond that audio is dropped and counted, never queued forever.
        ring = RingBuffer(capacity: Int(rate / 2))
        scratch = .allocate(capacity: scratchFrames)
        drainCapacity = Int(rate / 2)
        drain = .allocate(capacity: drainCapacity)
        resampler = try StreamResampler(inputRate: rate, input: .float32, outputRate: Self.outputRate, output: .int16)
        queue = DispatchQueue(label: "livebridge.capture.\(label)", qos: .userInteractive)
    }

    deinit {
        scratch.deallocate()
        drain.deallocate()
    }

    public func start() throws {
        guard procID == nil else { return }
        let ring = ring
        let scratch = scratch
        let overrunCount = overrunCount
        var newProc: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&newProc, deviceID, nil) { _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                for buffer in buffers {
                    let channels = Int(buffer.mNumberChannels)
                    guard channels > 0, let data = buffer.mData else { continue }
                    let frames = min(Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels), scratchFrames)
                    downmixToMono(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels, into: scratch)
                    if ring.write(scratch, count: frames) < frames { overrunCount.add(1) }
                    break
                }
            }, "create capture IO proc")
        procID = newProc
        do {
            try check(AudioDeviceStart(deviceID, newProc), "start capture device")
        } catch {
            stop()
            throw error
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.pump() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
        queue.sync {
            ring.flush()
            pending.removeAll(keepingCapacity: true)
        }
    }

    private func pump() {
        let count = ring.read(into: drain, count: drainCapacity)
        guard count > 0 else { return }
        pending.append(contentsOf: resampler.convert(float: drain, count: count))
        while pending.count >= Self.frameSamples {
            let frame = pending.prefix(Self.frameSamples)
            let level = frame.withUnsafeBufferPointer { levelDb($0.baseAddress!, count: $0.count) }
            let data = frame.withUnsafeBufferPointer { Data(buffer: $0) }
            pending.removeFirst(Self.frameSamples)
            onFrame?(data, level)
        }
    }
}

/// Plays mono PCM on one HAL output device (the physical headphones, or the virtual-microphone device) through a
/// bounded jitter buffer. Each direction owns its own sink; they share nothing.
///
/// Producer side (`write`, `endInput`, `flush`) must be called from a single thread. The IO thread only reads
/// atomics and the lock-free ring.
public final class PlaybackSink: @unchecked Sendable {
    public let deviceID: AudioObjectID
    public let sampleRate: Double
    /// Mid-stream starvations (the network did not deliver audio in time). End-of-turn drains are not counted.
    public var underruns: Int64 { underrunCount.value }
    /// Device-rate samples accepted so far / consumed by the device so far. A turn's audio is audible once
    /// `consumed` passes the `written` value recorded before it was queued.
    public var written: Int64 { ring.written }
    public var consumed: Int64 { ring.consumed }
    public var queuedMs: Double { Double(ring.availableToRead) / sampleRate * 1000 }
    /// While muted the device keeps draining the queue but emits silence, so muted speech is discarded in real time.
    public var isMuted: Bool {
        get { muted.flag }
        set { muted.flag = newValue }
    }

    private let ring: RingBuffer
    private let gateOpen = AtomicValue()
    private let inputEnded = AtomicValue(1)
    private let muted = AtomicValue()
    private let underrunCount = AtomicValue()
    private let scratch: UnsafeMutablePointer<Float>
    private let prebufferSamples: Int
    private let gain: Float
    private var resamplers: [Double: StreamResampler] = [:]
    private var procID: AudioDeviceIOProcID?

    /// - Parameters:
    ///   - prebufferMs: audio queued before playback of a turn starts, absorbing network jitter.
    ///   - gain: linear output gain (1 = unchanged). The CLI uses a tiny gain for inaudible hardware tests.
    public init(deviceID: AudioObjectID, prebufferMs: Double = 80, gain: Float = 1) throws {
        self.deviceID = deviceID
        guard let rate = HAL.value(deviceID, kAudioDevicePropertyNominalSampleRate, default: Float64(0)), rate > 0
        else { throw AudioEngineError("device", "cannot read the output device sample rate") }
        sampleRate = rate
        // 30 s: a whole long turn fits, and nothing can grow without bound.
        ring = RingBuffer(capacity: Int(rate * 30))
        prebufferSamples = Int(rate * prebufferMs / 1000)
        self.gain = gain
        scratch = .allocate(capacity: scratchFrames)
    }

    deinit { scratch.deallocate() }

    public func start() throws {
        guard procID == nil else { return }
        let ring = ring
        let scratch = scratch
        let gateOpen = gateOpen
        let inputEnded = inputEnded
        let muted = muted
        let underrunCount = underrunCount
        let prebuffer = prebufferSamples
        let gain = gain
        var newProc: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&newProc, deviceID, nil) { _, _, _, output, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(output)
                var wanted = 0
                for buffer in buffers where buffer.mNumberChannels > 0 {
                    wanted = max(wanted, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels)))
                }
                wanted = min(wanted, scratchFrames)
                var got = 0
                if !gateOpen.flag {
                    let available = ring.availableToRead
                    // Start once the jitter buffer is primed — or immediately when the whole (short) turn is here.
                    if available >= prebuffer || (available > 0 && inputEnded.flag) { gateOpen.flag = true }
                }
                if gateOpen.flag {
                    got = ring.read(into: scratch, count: wanted)
                    if got < wanted {
                        gateOpen.flag = false
                        if !inputEnded.flag { underrunCount.add(1) }
                    }
                }
                let silent = muted.flag
                for buffer in buffers {
                    let channels = Int(buffer.mNumberChannels)
                    guard channels > 0, let data = buffer.mData else { continue }
                    let out = data.assumingMemoryBound(to: Float.self)
                    let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                    for frame in 0..<frames {
                        // Mono is copied to every channel; samples are clamped so resampler overshoot cannot clip.
                        let sample: Float = (!silent && frame < got) ? max(-1, min(1, scratch[frame] * gain)) : 0
                        for channel in 0..<channels { out[frame * channels + channel] = sample }
                    }
                }
            }, "create playback IO proc")
        procID = newProc
        do {
            try check(AudioDeviceStart(deviceID, newProc), "start playback device")
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
        flush()
    }

    /// Queues s16le mono PCM recorded at `rate`. Returns false when the 30 s queue is full and audio was dropped.
    @discardableResult
    public func write(pcm16 data: Data, rate: Double) -> Bool {
        guard data.count >= 2 else { return true }
        let resampler: StreamResampler
        if let existing = resamplers[rate] {
            resampler = existing
        } else {
            guard let created = try? StreamResampler(inputRate: rate, input: .int16, outputRate: sampleRate, output: .float32)
            else { return false }
            resamplers[rate] = created
            resampler = created
        }
        let samples: [Float] = data.withUnsafeBytes { raw in
            resampler.convert(int16: raw.bindMemory(to: Int16.self).baseAddress!, count: data.count / 2)
        }
        inputEnded.flag = false
        return samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) == $0.count }
    }

    /// End of a turn: queues the audio the resamplers were still holding, then lets the tail play without waiting
    /// to prebuffer.
    public func endInput() {
        for resampler in resamplers.values {
            let tail = resampler.finishFloat()
            tail.withUnsafeBufferPointer { _ = ring.write($0.baseAddress ?? UnsafePointer(bitPattern: 1)!, count: $0.count) }
        }
        inputEnded.flag = true
    }

    /// Drops everything queued. The device plays silence from its next IO cycle (~10 ms).
    public func flush() {
        ring.flush()
        inputEnded.flag = true
        for resampler in resamplers.values { resampler.reset() }
    }
}
