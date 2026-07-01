//
//  MathServices.swift
//  tts_coach
//
//  Created by Shafa Tiara on 01/07/26.
//
import Accelerate

struct MathService {
    static func softmaxVectorized(logits: UnsafeMutablePointer<Float>, frameCount: Int, vocabSize: Int) -> [Float] {
        var probabilities = [Float](repeating: 0.0, count: frameCount * vocabSize)

        for f in 0..<frameCount {
            let offset = f * vocabSize
            let frameData = Array(UnsafeBufferPointer(start: logits.advanced(by: offset), count: vocabSize))

            var maxVal: Float = 0.0
            vDSP_maxv(frameData, 1, &maxVal, vDSP_Length(vocabSize))
            var negMax = -maxVal

            var expIn = [Float](repeating: 0.0, count: vocabSize)
            vDSP_vsadd(frameData, 1, &negMax, &expIn, 1, vDSP_Length(vocabSize))

            var count = Int32(vocabSize)
            var expOut = [Float](repeating: 0.0, count: vocabSize)
            vvexpf(&expOut, expIn, &count)

            var sum: Float = 0.0
            vDSP_sve(expOut, 1, &sum, vDSP_Length(vocabSize))

            var frameProbs = [Float](repeating: 0.0, count: vocabSize)
            vDSP_vsdiv(expOut, 1, &sum, &frameProbs, 1, vDSP_Length(vocabSize))

            for v in 0..<vocabSize {
                probabilities[offset + v] = frameProbs[v]
            }
        }
        return probabilities
    }
}
