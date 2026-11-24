import AVFoundation
import Foundation

/// Streaming mono sample-rate / sample-format conversion. One instance per stream: the converter keeps its filter
/// state between calls, so consecutive chunks join without clicks. Not real-time safe — worker queues only.
public final class StreamResampler {
    public enum Sample { case float32, int16 }

    public let inputRate: Double
    public let outputRate: Double
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    /// True while audio has been converted since the last finish/reset, i.e. the converter may be holding samples.
    private var streaming = false

    public init(inputRate: Double, input: Sample, outputRate: Double, output: Sample) throws {
        func format(_ rate: Double, _ sample: Sample) -> AVAudioFormat? {
            AVAudioFormat(
                commonFormat: sample == .float32 ? .pcmFormatFloat32 : .pcmFormatInt16,
                sampleRate: rate, channels: 1, interleaved: false)
        }
        guard let inputFormat = format(inputRate, input), let outputFormat = format(outputRate, output),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { throw AudioEngineError("resampler", "unsupported conversion \(inputRate) Hz -> \(outputRate) Hz") }
        // No priming: do not hold back the first samples of a stream to pre-fill the filter.
        converter.primeMethod = .none
        self.inputRate = inputRate
        self.outputRate = outputRate
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    /// Float32 in, Int16 out (capture path: device rate -> 16 kHz PCM for the gateway).
    public func convert(float samples: UnsafePointer<Float>, count: Int) -> [Int16] {
        guard count > 0, let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count))
        else { return [] }
        input.frameLength = AVAudioFrameCount(count)
        input.floatChannelData![0].update(from: samples, count: count)
        guard let output = run(input) else { return [] }
        return Array(UnsafeBufferPointer(start: output.int16ChannelData![0], count: Int(output.frameLength)))
    }

    /// Int16 in, Float32 out (playback path: synthesized PCM -> device rate).
    public func convert(int16 samples: UnsafePointer<Int16>, count: Int) -> [Float] {
        guard count > 0, let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count))
        else { return [] }
        input.frameLength = AVAudioFrameCount(count)
        input.int16ChannelData![0].update(from: samples, count: count)
        guard let output = run(input) else { return [] }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    /// Ends the stream: returns the samples the converter was still holding for its filter (tens of milliseconds
    /// that would otherwise be cut off the end of a turn and leak into the start of the next), then clears its state.
    public func finishFloat() -> [Float] {
        guard streaming else { return [] }
        streaming = false
        defer { converter.reset() }
        guard let output = run(nil) else { return [] }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    /// Forget filter history without emitting it (a cancelled turn: the held samples must not be heard).
    public func reset() {
        streaming = false
        converter.reset()
    }

    private func run(_ input: AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
        let expected = input.map { Double($0.frameLength) * outputRate / inputRate } ?? outputRate / 4
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(expected) + 64)
        else { return nil }
        var provided = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let input, !provided else {
                // Mid-stream, more audio will come in a later call, so the converter keeps its state (.noDataNow).
                // With no input at all this is the final drain (.endOfStream).
                inputStatus.pointee = input == nil ? .endOfStream : .noDataNow
                return nil
            }
            provided = true
            self.streaming = true
            inputStatus.pointee = .haveData
            return input
        }
        return status == .error ? nil : output
    }
}

/// Mixes interleaved multi-channel Float32 down to mono in place of a destination buffer. Real-time safe.
@inline(__always)
func downmixToMono(
    _ source: UnsafePointer<Float>, frames: Int, channels: Int, into destination: UnsafeMutablePointer<Float>
) {
    if channels == 1 {
        destination.update(from: source, count: frames)
        return
    }
    let scale = 1 / Float(channels)
    for frame in 0..<frames {
        var sum: Float = 0
        for channel in 0..<channels { sum += source[frame * channels + channel] }
        destination[frame] = sum * scale
    }
}

/// Level of a block of samples in dBFS (RMS), floored at −120.
public func levelDb(_ samples: UnsafePointer<Int16>, count: Int) -> Double {
    guard count > 0 else { return -120 }
    var sum = 0.0
    for i in 0..<count {
        let s = Double(samples[i]) / 32768
        sum += s * s
    }
    let rms = (sum / Double(count)).squareRoot()
    return rms > 0 ? max(-120, 20 * log10(rms)) : -120
}
