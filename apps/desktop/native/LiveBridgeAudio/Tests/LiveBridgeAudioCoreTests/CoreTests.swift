import XCTest

@testable import LiveBridgeAudioCore

final class FrameCodecTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Valid: Decodable {
            let name, hex, kind, direction, timestampUs, payloadHex: String
            let flags: UInt8
            let generation, sequence, turnId: UInt32
        }
        struct Invalid: Decodable { let name, hex, error: String }
        let valid: [Valid]
        let invalid: [Invalid]
    }

    /// The same file the TypeScript codec is tested against.
    private func fixtures() throws -> Fixtures {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("packages/protocol/fixtures/frames.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    private func data(hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    func testSharedValidFixturesDecodeAndReencodeByteExactly() throws {
        let fixtures = try fixtures()
        XCTAssertEqual(fixtures.valid.count, 4)
        for fixture in fixtures.valid {
            let bytes = data(hex: fixture.hex)
            let frame = try FrameCodec.decode(bytes)
            XCTAssertEqual(frame.kind, fixture.kind == "capture" ? .capture : .synthesized, fixture.name)
            XCTAssertEqual(frame.direction.name, fixture.direction, fixture.name)
            XCTAssertEqual(frame.flags, fixture.flags, fixture.name)
            XCTAssertEqual(frame.generation, fixture.generation, fixture.name)
            XCTAssertEqual(frame.sequence, fixture.sequence, fixture.name)
            XCTAssertEqual(String(frame.timestampUs), fixture.timestampUs, fixture.name)
            XCTAssertEqual(frame.turnId, fixture.turnId, fixture.name)
            XCTAssertEqual(frame.payload, data(hex: fixture.payloadHex), fixture.name)
            XCTAssertEqual(try FrameCodec.encode(frame), bytes, fixture.name)
        }
    }

    func testSharedInvalidFixturesAreRejectedWithTheSameErrorCode() throws {
        let fixtures = try fixtures()
        XCTAssertEqual(fixtures.invalid.count, 9)
        for fixture in fixtures.invalid {
            XCTAssertThrowsError(try FrameCodec.decode(data(hex: fixture.hex)), fixture.name) { error in
                XCTAssertEqual((error as? FrameError)?.rawValue, fixture.error, fixture.name)
            }
        }
    }

    func testDecodeWorksOnASliceWithNonZeroStartIndex() throws {
        let frame = AudioFrame(kind: .capture, direction: .in, generation: 9, sequence: 3, timestampUs: 77, payload: Data([1, 2, 3, 4]))
        let encoded = try FrameCodec.encode(frame)
        let padded = Data([0xAA, 0xBB, 0xCC]) + encoded
        XCTAssertEqual(try FrameCodec.decode(padded.dropFirst(3)), frame)
    }

    func testEncodeRefusesOversizedAndOddPayloads() {
        func frame(_ size: Int) -> AudioFrame {
            AudioFrame(kind: .capture, direction: .out, generation: 1, sequence: 1, timestampUs: 0, payload: Data(count: size))
        }
        XCTAssertThrowsError(try FrameCodec.encode(frame(AudioFrame.maxPayloadBytes + 2)))
        XCTAssertThrowsError(try FrameCodec.encode(frame(3)))
        XCTAssertNoThrow(try FrameCodec.encode(frame(AudioFrame.maxPayloadBytes)))
    }
}

final class RingBufferTests: XCTestCase {
    private func read(_ ring: RingBuffer, _ count: Int) -> [Float] {
        var out = [Float](repeating: -1, count: count)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: count) }
        return Array(out.prefix(n))
    }

    func testWrapsAroundPreservingOrder() {
        let ring = RingBuffer(capacity: 8)
        XCTAssertEqual(ring.write([1, 2, 3, 4, 5, 6], count: 6), 6)
        XCTAssertEqual(read(ring, 4), [1, 2, 3, 4])
        XCTAssertEqual(ring.write([7, 8, 9, 10, 11], count: 5), 5)
        XCTAssertEqual(read(ring, 20), [5, 6, 7, 8, 9, 10, 11])
        XCTAssertEqual(ring.availableToRead, 0)
    }

    func testIsBoundedAndReportsOverflowInsteadOfGrowing() {
        let ring = RingBuffer(capacity: 4)
        XCTAssertEqual(ring.write([1, 2, 3, 4, 5, 6], count: 6), 4)
        XCTAssertEqual(ring.write([9], count: 1), 0)
        XCTAssertEqual(read(ring, 10), [1, 2, 3, 4])
    }

    func testFlushDiscardsEverythingQueuedButKeepsLaterWrites() {
        let ring = RingBuffer(capacity: 8)
        ring.write([1, 2, 3, 4, 5], count: 5)
        _ = read(ring, 2)
        ring.flush()
        XCTAssertEqual(ring.availableToRead, 0)
        XCTAssertEqual(ring.consumed, 5)
        // The full capacity is usable again immediately, before the consumer has even run.
        XCTAssertEqual(ring.write([6, 7, 8, 9, 10, 11, 12, 13], count: 8), 8)
        XCTAssertEqual(read(ring, 8), [6, 7, 8, 9, 10, 11, 12, 13])
    }

    func testConcurrentProducerAndConsumerLoseNothingAndKeepOrder() {
        let ring = RingBuffer(capacity: 1024)
        let total = 200_000
        let done = expectation(description: "consumer finished")
        var received: [Float] = []
        received.reserveCapacity(total)
        DispatchQueue.global().async {
            var chunk = [Float](repeating: 0, count: 256)
            while received.count < total {
                let n = chunk.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 256) }
                received.append(contentsOf: chunk.prefix(n))
            }
            done.fulfill()
        }
        var next = 0
        while next < total {
            let batch = (next..<min(next + 100, total)).map(Float.init)
            let written = ring.write(batch, count: batch.count)
            next += written
        }
        wait(for: [done], timeout: 20)
        XCTAssertEqual(received.count, total)
        XCTAssertTrue(received.enumerated().allSatisfy { Float($0.offset) == $0.element })
    }
}

final class ResamplerTests: XCTestCase {
    private func sine(rate: Double, hz: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(rate * seconds)).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    func testDownsamplesDeviceRateToSixteenKilohertzWithTheRightLengthAndLevel() throws {
        let resampler = try StreamResampler(inputRate: 48_000, input: .float32, outputRate: 16_000, output: .int16)
        let input = sine(rate: 48_000, hz: 440, seconds: 1)
        var output: [Int16] = []
        // Fed in uneven chunks, the way a device delivers audio.
        var offset = 0
        for chunk in [480, 512, 333, 4096, 1] + Array(repeating: 512, count: 200) where offset < input.count {
            let n = min(chunk, input.count - offset)
            input.withUnsafeBufferPointer { output += resampler.convert(float: $0.baseAddress! + offset, count: n) }
            offset += n
        }
        XCTAssertEqual(Double(output.count), 16_000, accuracy: 200)
        let level = output.withUnsafeBufferPointer { levelDb($0.baseAddress!, count: $0.count) }
        // A 0.5-amplitude sine is −9 dBFS RMS; conversion must not change the level materially.
        XCTAssertEqual(level, -9.03, accuracy: 0.5)
    }

    func testUpsamplesSynthesizedPcmToDeviceRateWithoutClippingOrGaps() throws {
        let resampler = try StreamResampler(inputRate: 24_000, input: .int16, outputRate: 48_000, output: .float32)
        let input = sine(rate: 24_000, hz: 300, seconds: 0.5, amplitude: 0.99).map { Int16($0 * 32767) }
        var output: [Float] = []
        for start in stride(from: 0, to: input.count, by: 4800) {
            let n = min(4800, input.count - start)
            input.withUnsafeBufferPointer { output += resampler.convert(int16: $0.baseAddress! + start, count: n) }
        }
        // Mid-stream the converter holds back its filter tail; finishing the stream must hand it over in full.
        let held = 24_000 - output.count
        output += resampler.finishFloat()
        XCTAssertEqual(Double(output.count), 24_000, accuracy: 80)
        XCTAssertLessThan(held, 2_400, "resampler latency should stay under 50 ms")
        // After finishing, the next stream starts clean: nothing left over to leak into the following turn.
        XCTAssertEqual(resampler.finishFloat().count, 0)
        XCTAssertLessThanOrEqual(output.map(abs).max() ?? 0, 1.05)
        // No chunk-boundary clicks: a 300 Hz sine at 48 kHz never jumps more than ~0.04 between samples.
        let maxStep = zip(output.dropFirst(100), output.dropFirst(101)).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(maxStep, 0.08)
    }

    func testSilenceStaysSilent() throws {
        let resampler = try StreamResampler(inputRate: 44_100, input: .float32, outputRate: 16_000, output: .int16)
        let output = [Float](repeating: 0, count: 44_100).withUnsafeBufferPointer {
            resampler.convert(float: $0.baseAddress!, count: $0.count)
        }
        XCTAssertTrue(output.allSatisfy { $0 == 0 })
        XCTAssertEqual(output.withUnsafeBufferPointer { levelDb($0.baseAddress!, count: $0.count) }, -120)
    }

    func testDownmixAveragesChannels() {
        let stereo: [Float] = [1, 0, 0.5, 0.5, -1, 1, 0.2, 0.4]
        var mono = [Float](repeating: 9, count: 4)
        downmixToMono(stereo, frames: 4, channels: 2, into: &mono)
        XCTAssertEqual(mono[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(mono[1], 0.5, accuracy: 1e-6)
        XCTAssertEqual(mono[2], 0, accuracy: 1e-6)
        XCTAssertEqual(mono[3], 0.3, accuracy: 1e-6)
        var same = [Float](repeating: 0, count: 3)
        downmixToMono([0.1, 0.2, 0.3], frames: 3, channels: 1, into: &same)
        XCTAssertEqual(same, [0.1, 0.2, 0.3])
    }
}

final class RouteSafetyTests: XCTestCase {
    func testVirtualMicCannotBeTheMicrophoneOrTheHeadphones() {
        XCTAssertNil(unsafeRouteReason(micUid: "mic", headphonesUid: "phones", virtualMicUid: "blackhole"))
        XCTAssertNil(unsafeRouteReason(micUid: "mic", headphonesUid: "phones", virtualMicUid: nil))
        XCTAssertNotNil(unsafeRouteReason(micUid: "blackhole", headphonesUid: "phones", virtualMicUid: "blackhole"))
        XCTAssertNotNil(unsafeRouteReason(micUid: "mic", headphonesUid: "blackhole", virtualMicUid: "blackhole"))
    }
}

final class DeviceEnumerationTests: XCTestCase {
    func testEveryListedDeviceHasAStableUidAndIsLive() {
        let devices = AudioDevices.all()
        XCTAssertFalse(devices.isEmpty, "this Mac should have at least one audio device")
        XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count)
        for device in devices {
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertTrue(device.inputChannels + device.outputChannels > 0, device.name)
            XCTAssertGreaterThan(device.sampleRate, 0, device.name)
            XCTAssertEqual(AudioDevices.device(uid: device.uid)?.id, device.id)
        }
        XCTAssertNil(AudioDevices.device(uid: "no-such-device-uid"))
    }

    func testStaleProcessIdIsAnErrorNotASilentTap() {
        XCTAssertThrowsError(try ProcessTap(pids: [999_999])) { error in
            XCTAssertEqual((error as? AudioEngineError)?.code, "source_gone")
        }
        XCTAssertThrowsError(try ProcessTap(pids: []))
    }
}

final class ProcessListTests: XCTestCase {
    func testSystemServicesAreNotOfferedAsMeetingSourcesButBrowsersAndMeetingAppsAre() {
        for bundle in ["com.google.Chrome.helper", "us.zoom.xos", "org.mozilla.firefox", "com.apple.Safari", "com.apple.WebKit.GPU", "com.apple.FaceTime"] {
            XCTAssertTrue(AudioProcesses.isMeetingCandidate(bundleId: bundle), bundle)
        }
        for bundle in ["", "com.apple.assistantd", "com.apple.avconferenced", "com.apple.TelephonyUtilities", "com.apple.audiomxd"] {
            XCTAssertFalse(AudioProcesses.isMeetingCandidate(bundleId: bundle), bundle)
        }
    }
}

final class AnalyticsLogTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("lb-analytics-\(UUID().uuidString)/analytics.jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func state(_ state: String, mock: Bool = false) -> [String: Any] { ["type": "state", "state": state, "mock": mock] }

    /// One push-to-talk turn the way the engine reports it: captions, the client's end-to-end time, then the
    /// gateway's stage timings.
    private func turn(_ log: AnalyticsLog, id: Int, e2e: Int, source: String, translation: String, e2eFirst: Bool = true) {
        log.record(event: ["type": "caption", "direction": "out", "turnId": id, "kind": "final", "text": source])
        log.record(event: ["type": "caption", "direction": "out", "turnId": id, "kind": "translationFinal", "text": translation])
        let local: [String: Any] = ["type": "metrics", "direction": "out", "turnId": id, "e2eMs": e2e]
        var server: [String: Any] = [
            "type": "metrics", "direction": "out", "turnId": id, "sttCommitMs": 300, "translateFirstMs": 600,
            "translateTotalMs": 700, "ttsFirstAudioMs": 250, "audioMs": 2400, "model": "gemini-3.5-flash-lite",
        ]
        if e2eFirst {
            log.record(event: local)
            server["e2eMs"] = e2e
            log.record(event: server)
        } else {
            log.record(event: server)
            log.record(event: local)
        }
    }

    func testRecordsNumbersOnlyAndSummarisesThem() throws {
        let log = AnalyticsLog(fileURL: url)
        let secret = "Maoshim oyiga uch ming dollar"
        log.record(event: state("connecting"))
        log.record(event: state("ready"))
        for (index, e2e) in [1200, 1400, 1300, 2600].enumerated() {
            turn(log, id: index + 1, e2e: e2e, source: secret, translation: "My salary is three thousand dollars a month", e2eFirst: index != 3)
        }
        log.record(event: ["type": "caption", "direction": "out", "turnId": 5, "kind": "partial", "text": ""])
        log.record(event: ["type": "error", "code": "translation_failed", "direction": "out", "fatal": false])
        log.record(event: state("degraded"))
        log.record(event: state("ready"))
        log.rate(direction: "out", turnId: 1, rating: "good")
        log.rate(direction: "out", turnId: 2, rating: "bad")
        log.rate(direction: "out", turnId: 2, rating: "good")
        log.rate(direction: "out", turnId: 3, rating: "bad")
        log.rate(direction: "out", turnId: 3, rating: "none")
        log.record(event: state("idle"))

        let summary = log.summary()
        let written = try String(contentsOf: url, encoding: .utf8)
        // Privacy: lengths are recorded, text never is.
        XCTAssertFalse(written.contains("Maoshim"))
        XCTAssertFalse(written.contains("salary"))
        XCTAssertTrue(written.contains("\"sourceChars\":\(secret.count)"))
        XCTAssertTrue(written.contains("\"model\":\"gemini-3.5-flash-lite\""))

        XCTAssertEqual(summary["sessions"] as? Int, 1)
        XCTAssertEqual(summary["turns"] as? Int, 4)
        XCTAssertEqual(summary["emptyTurns"] as? Int, 1)
        XCTAssertEqual(summary["reconnects"] as? Int, 1)
        XCTAssertEqual(summary["errors"] as? [String: Int], ["translation_failed": 1])
        // Turn 2's last rating is "good"; turn 3's was withdrawn.
        XCTAssertEqual(summary["ratedGood"] as? Int, 2)
        XCTAssertEqual(summary["ratedBad"] as? Int, 0)
        // All four end-to-end times count, including the one observed after the gateway's timings arrived.
        XCTAssertEqual(summary["e2eMs"] as? [String: Int], ["count": 4, "p50": 1300, "p95": 2600, "max": 2600])
        XCTAssertEqual((summary["translateFirstMs"] as? [String: Int])?["p50"], 600)
        XCTAssertEqual(summary["path"] as? String, url.path)
        XCTAssertNotNil(summary["firstAt"])
        XCTAssertGreaterThan(summary["fileSizeBytes"] as? Int ?? 0, 100)
    }

    func testMockSessionsAreKeptOutOfTheFigures() {
        let log = AnalyticsLog(fileURL: url)
        log.record(event: state("connecting"))
        log.record(event: state("ready", mock: true))
        turn(log, id: 1, e2e: 190, source: "x", translation: "y")
        log.record(event: state("idle"))
        let summary = log.summary()
        XCTAssertEqual(summary["sessions"] as? Int, 0)
        XCTAssertEqual(summary["turns"] as? Int, 0)
        XCTAssertNil(summary["e2eMs"])
    }

    func testDisabledLogWritesNothingAndClearRemovesTheFile() {
        let log = AnalyticsLog(fileURL: url)
        log.isEnabled = false
        log.record(event: state("connecting"))
        log.record(event: state("ready"))
        turn(log, id: 1, e2e: 1000, source: "x", translation: "y")
        XCTAssertEqual(log.summary()["turns"] as? Int, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(log.summary()["enabled"] as? Bool, false)

        log.isEnabled = true
        log.record(event: state("idle"))
        log.record(event: state("connecting"))
        log.record(event: state("active"))
        turn(log, id: 1, e2e: 1000, source: "x", translation: "y")
        XCTAssertEqual(log.summary()["turns"] as? Int, 1)
        log.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(log.summary()["turns"] as? Int, 0)
    }
}
