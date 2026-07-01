//
//  PreprocessServices.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import Foundation
import AVFoundation
import Accelerate

/// Configuration mirroring the Python preprocessing notebook
/// (`inference_preprocess.ipynb`) — defaults match its female-voice
/// tuning pass specifically, so cloned-voice output stays consistent
/// with what's already been validated there.
struct AudioPreprocessingConfig {
    /// Spectral denoise strength, 0 = skip denoising entirely.
    ///
    /// Defaults to **0 (disabled)**, not the notebook's 0.2 — basic
    /// spectral-subtraction denoising (the technique this is a port of)
    /// is well known for introducing "musical noise"/robotic artifacts
    /// on voice, and this Swift port couldn't be tuned by ear against
    /// the Python output before being handed over. Trim/resample/loudness
    /// normalize (the other 3 steps) are far lower-risk and stay on by
    /// default. Re-enable this (try a low value like 0.1 first) only if
    /// you're recording somewhere genuinely noisy and want to trade some
    /// clarity for less background noise.
    var denoiseStrength: Float = 0
    /// Target loudness. Female-voice tuning: -18.0 (up from -23.0, for
    /// wider dynamic range). See `normalizeLoudness` for why this is an
    /// RMS-based approximation rather than true LUFS.
    var targetLUFS: Float = -18.0
    /// Silence-trim threshold in dB relative to peak. Female-voice
    /// tuning: -50.0 (down from -40.0, to avoid clipping soft onsets).
    var trimThresholdDB: Float = -50.0
    var padStartMs: Float = 50
    var padEndMs: Float = 100
    /// Matches Qwen3-TTS's expected sample rate (the notebook's
    /// `MODELS["qwen3tts"]["sr"]`).
    var targetSampleRate: Double = 24_000
    var minDuration: Double = 2.0
    var maxDuration: Double = 150.0
    var padEndSeconds: Double = 0.5

    static let `default` = AudioPreprocessingConfig()
}

enum AudioPreprocessingError: LocalizedError {
    case emptyAudio
    case tooShort(actual: Double, minimum: Double)
    case formatSetupFailed

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "Recording appears to be empty."
        case .tooShort(let actual, let minimum):
            let a = String(format: "%.1f", actual)
            let m = String(format: "%.1f", minimum)
            return "Recording is too short (\(a)s, needs at least \(m)s)."
        case .formatSetupFailed:
            return "Couldn't set up audio format for processing."
        }
    }
}

/// On-device port of the Python notebook's preprocessing pipeline —
/// silence trimming, spectral denoising, resampling, and loudness
/// normalization — using only Apple's own frameworks (`AVFoundation` +
/// `Accelerate`). No extra dependencies beyond what `AudioRecorderService`
/// already requires.
///
/// Honesty note on risk: `trimSilence`, `resample`, and
/// `normalizeLoudness` are low-risk, well-trodden operations (threshold
/// comparison, Apple's own `AVAudioConverter`, and a simple RMS
/// calculation). `spectralDenoise` is a hand-port of custom FFT-based
/// spectral subtraction — the one piece here with real potential for a
/// subtle scaling/normalization bug, since it couldn't be tested against
/// the Python output before being handed over. If processed reference
/// clips sound *worse* than raw ones (artifacts, warbling), the first
/// thing to try is setting `denoiseStrength` to `0` to confirm the
/// denoiser is the cause, then flag it for a closer look.
enum AudioPreprocessingService {
    /// Runs the full pipeline on `inputURL` and writes the result to a
    /// fresh temp `.wav` file, returning its URL.
    static func preprocess(
        inputURL: URL,
        config: AudioPreprocessingConfig = .default
    ) throws -> URL {
        var (samples, sampleRate) = try loadMonoSamples(from: inputURL)
        guard !samples.isEmpty else { throw AudioPreprocessingError.emptyAudio }

        samples = trimSilence(
            samples,
            sampleRate: sampleRate,
            thresholdDB: config.trimThresholdDB,
            padStartMs: config.padStartMs,
            padEndMs: config.padEndMs
        )

        if config.denoiseStrength > 0 {
            samples = spectralDenoise(samples, strength: config.denoiseStrength)
        }

        if sampleRate != config.targetSampleRate {
            samples = try resample(samples, from: sampleRate, to: config.targetSampleRate)
            sampleRate = config.targetSampleRate
        }

        samples = normalizeLoudness(samples, targetLUFS: config.targetLUFS)

        let duration = Double(samples.count) / sampleRate
        guard duration >= config.minDuration else {
            throw AudioPreprocessingError.tooShort(actual: duration, minimum: config.minDuration)
        }
        if duration > config.maxDuration {
            samples = Array(samples.prefix(Int(config.maxDuration * sampleRate)))
        }

        if config.padEndSeconds > 0 {
            samples.append(contentsOf: [Float](repeating: 0, count: Int(config.padEndSeconds * sampleRate)))
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try writeWav(samples: samples, sampleRate: sampleRate, to: outputURL)
        return outputURL
    }

    // MARK: - Load

    private static func loadMonoSamples(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioPreprocessingError.formatSetupFailed
        }
        try file.read(into: buffer)

        let channelCount = Int(format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData, frameLength > 0, channelCount > 0 else {
            return ([], format.sampleRate)
        }

        if channelCount == 1 {
            return (Array(UnsafeBufferPointer(start: channelData[0], count: frameLength)), format.sampleRate)
        }

        // Average all channels down to mono — matches the Python
        // version's `np.mean(audio, axis=1)`.
        var mono = [Float](repeating: 0, count: frameLength)
        for channel in 0..<channelCount {
            let channelPointer = channelData[channel]
            for i in 0..<frameLength {
                mono[i] += channelPointer[i]
            }
        }
        let scale: Float = 1.0 / Float(channelCount)
        for i in 0..<frameLength {
            mono[i] *= scale
        }
        return (mono, format.sampleRate)
    }

    // MARK: - Trim silence

    private static func trimSilence(
        _ samples: [Float],
        sampleRate: Double,
        thresholdDB: Float,
        padStartMs: Float,
        padEndMs: Float
    ) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let hop = max(1, Int(0.02 * sampleRate))

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > 1e-10 else { return samples }

        let threshold = peak * pow(10, thresholdDB / 20)
        let frameCount = samples.count / hop
        guard frameCount > 0 else { return samples }

        func frameMax(_ frame: Int) -> Float {
            let start = frame * hop
            let length = min(hop, samples.count - start)
            var m: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                vDSP_maxmgv(ptr.baseAddress! + start, 1, &m, vDSP_Length(length))
            }
            return m
        }

        var first = 0
        for i in 0..<frameCount where frameMax(i) > threshold {
            first = i
            break
        }
        var last = frameCount - 1
        for i in stride(from: frameCount - 1, through: 0, by: -1) where frameMax(i) > threshold {
            last = i
            break
        }

        let start = max(0, first * hop - Int(padStartMs / 1000 * Float(sampleRate)))
        let end = min(samples.count, (last + 1) * hop + Int(padEndMs / 1000 * Float(sampleRate)))
        guard start < end else { return samples }
        return Array(samples[start..<end])
    }

    // MARK: - Spectral denoise
    //
    // Direct port of the notebook's STFT spectral-subtraction approach:
    // window each overlapping frame, estimate a noise profile from the
    // quietest ~10% of frames, subtract `strength` × that profile from
    // every frame's magnitude (floored to keep 1% of the original so it
    // doesn't zero out entirely), then overlap-add back with the same
    // window applied on the synthesis side too (standard OLA practice).
    //
    // Uses the modern `vDSP.FFT<DSPSplitComplex>` complex-to-complex
    // transform rather than the legacy packed-real `vDSP_fft_zrip` API —
    // mathematically equivalent for real input (a real signal's spectrum
    // is conjugate-symmetric, and a magnitude-only edit preserves that
    // symmetry automatically), and meaningfully less error-prone to spell
    // out correctly than the packed-real format's special-cased bins.

    private static func spectralDenoise(_ samples: [Float], strength: Float, nFFT: Int = 2048) -> [Float] {
        guard strength > 0, samples.count > nFFT else { return samples }
        let hop = nFFT / 4
        let frameCount = (samples.count - nFFT) / hop + 1
        guard frameCount >= 4 else { return samples }

        let log2n = vDSP_Length(log2(Double(nFFT)))
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            return samples
        }

        var window = [Float](repeating: 0, count: nFFT)
        // `.HANN_DENORM` matches NumPy's `np.hanning` exactly (peak 1.0,
        // unscaled) — `.HANN_NORM` applies extra energy normalization
        // NumPy's version doesn't have, which would've been a subtle
        // mismatch with the Python pipeline.
        vDSP_hann_window(&window, vDSP_Length(nFFT), Int32(vDSP_HANN_DENORM))

        var frameReals: [[Float]] = []
        var frameImags: [[Float]] = []
        var frameMagnitudes: [[Float]] = []
        var frameEnergies: [Float] = []
        frameReals.reserveCapacity(frameCount)
        frameImags.reserveCapacity(frameCount)
        frameMagnitudes.reserveCapacity(frameCount)
        frameEnergies.reserveCapacity(frameCount)

        for f in 0..<frameCount {
            let start = f * hop
            var windowed = [Float](repeating: 0, count: nFFT)
            for i in 0..<nFFT {
                windowed[i] = samples[start + i] * window[i]
            }

            let interleaved = windowed.map { DSPComplex(real: $0, imag: 0) }
            var real = [Float](repeating: 0, count: nFFT)
            var imag = [Float](repeating: 0, count: nFFT)
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP.convert(interleavedComplexVector: interleaved, toSplitComplexVector: &split)
                    fft.transform(input: split, output: &split, direction: .forward)
                }
            }

            var magnitude = [Float](repeating: 0, count: nFFT)
            var energy: Float = 0
            for i in 0..<nFFT {
                let m = (real[i] * real[i] + imag[i] * imag[i]).squareRoot()
                magnitude[i] = m
                energy += m * m
            }
            energy /= Float(nFFT)

            frameReals.append(real)
            frameImags.append(imag)
            frameMagnitudes.append(magnitude)
            frameEnergies.append(energy)
        }

        // Noise profile: average magnitude spectrum of the quietest ~10%
        // of frames — same heuristic as the notebook.
        let noiseFrameCount = max(1, frameCount / 10)
        let quietestIndices = frameEnergies.indices
            .sorted { frameEnergies[$0] < frameEnergies[$1] }
            .prefix(noiseFrameCount)

        var noiseProfile = [Float](repeating: 0, count: nFFT)
        for index in quietestIndices {
            for bin in 0..<nFFT {
                noiseProfile[bin] += frameMagnitudes[index][bin]
            }
        }
        let noiseScale = 1.0 / Float(quietestIndices.count)
        for bin in 0..<nFFT {
            noiseProfile[bin] *= noiseScale
        }

        var output = [Float](repeating: 0, count: samples.count)
        var weightSum = [Float](repeating: 0, count: samples.count)
        let windowSquared = window.map { $0 * $0 }
        // Accelerate's forward+inverse FFT round trip scales by N —
        // unlike NumPy's fft/ifft, which normalize automatically. This
        // factor undoes that so the reconstructed amplitude matches the
        // original signal's scale.
        let inverseScale: Float = 1.0 / Float(nFFT)

        for f in 0..<frameCount {
            var cleanReal = [Float](repeating: 0, count: nFFT)
            var cleanImag = [Float](repeating: 0, count: nFFT)
            for bin in 0..<nFFT {
                let mag = frameMagnitudes[f][bin]
                let cleanMag = max(mag - noiseProfile[bin] * strength * 2, mag * 0.01)
                // Scale real/imag by the same ratio to keep phase exactly
                // as-is while replacing magnitude — equivalent to the
                // Python version's `clean_mag * exp(1j * phase)`.
                let ratio = mag > 1e-12 ? cleanMag / mag : 0
                cleanReal[bin] = frameReals[f][bin] * ratio
                cleanImag[bin] = frameImags[f][bin] * ratio
            }

            cleanReal.withUnsafeMutableBufferPointer { realPtr in
                cleanImag.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    fft.transform(input: split, output: &split, direction: .inverse)
                }
            }

            let start = f * hop
            for i in 0..<nFFT {
                let sample = cleanReal[i] * inverseScale * window[i]
                output[start + i] += sample
                weightSum[start + i] += windowSquared[i]
            }
        }

        for i in 0..<samples.count where weightSum[i] > 1e-8 {
            output[i] /= weightSum[i]
        }
        return output
    }

    // MARK: - Resample

    private static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) throws -> [Float] {
        guard sourceRate != targetRate else { return samples }
        guard
            let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            throw AudioPreprocessingError.formatSetupFailed
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw AudioPreprocessingError.formatSetupFailed
        }
        inputBuffer.frameLength = inputBuffer.frameCapacity
        samples.withUnsafeBufferPointer { ptr in
            inputBuffer.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }

        // Generous capacity — exact output frame count for SRC isn't
        // knowable upfront, only estimable.
        let estimatedFrames = AVAudioFrameCount(Double(samples.count) * targetRate / sourceRate) + 4096
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            throw AudioPreprocessingError.formatSetupFailed
        }

        var inputConsumed = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        if let conversionError {
            throw conversionError
        }

        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0, let outData = outputBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: outData[0], count: frameLength))
    }

    // MARK: - Loudness normalize

    /// Approximates LUFS-style loudness leveling using plain RMS level
    /// matching, rather than full ITU-R BS.1770 K-weighting + gated block
    /// integration (which `pyloudnorm` implements precisely). This is a
    /// deliberate, lower-risk simplification: K-weighting needs carefully
    /// tuned biquad filter coefficients and a gating algorithm, which is
    /// easy to get subtly wrong without being able to test against the
    /// Python output directly. RMS leveling achieves the same *practical*
    /// goal — consistent loudness across reference clips — just without
    /// exact numeric parity to pyloudnorm's specific LUFS values.
    private static func normalizeLoudness(_ samples: [Float], targetLUFS: Float) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        guard meanSquare > 1e-12 else { return samples }

        let rmsDB = 10 * log10(meanSquare)
        let gainDB = targetLUFS - rmsDB
        var gain = pow(10, gainDB / 20)

        var output = [Float](repeating: 0, count: samples.count)
        vDSP_vsmul(samples, 1, &gain, &output, 1, vDSP_Length(samples.count))

        // Safety clip, matching the Python version's `np.clip`.
        var lowerBound: Float = -1
        var upperBound: Float = 1
        vDSP_vclip(output, 1, &lowerBound, &upperBound, &output, 1, vDSP_Length(output.count))
        return output
    }

    // MARK: - Write

    private static func writeWav(samples: [Float], sampleRate: Double, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            throw AudioPreprocessingError.formatSetupFailed
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw AudioPreprocessingError.formatSetupFailed
        }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }
}
