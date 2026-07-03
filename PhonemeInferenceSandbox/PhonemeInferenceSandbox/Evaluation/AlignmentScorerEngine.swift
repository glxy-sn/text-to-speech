import Foundation
import CoreML

struct PhoneScore: Identifiable {
    let id = UUID()
    let symbol: String
    let gopScore: Float
    let frames: Int
}

struct WordScore: Identifiable {
    let id = UUID()
    let word: String
    let phoneScores: [PhoneScore]
    let averageScore: Float
}

class AlignmentScorerEngine {
    private let blankIndex = 0
    
    private func logSumExp(_ a: Float, _ b: Float) -> Float {
        if a == -Float.greatestFiniteMagnitude { return b }
        if b == -Float.greatestFiniteMagnitude { return a }
        let maxVal = max(a, b)
        return maxVal + log(exp(a - maxVal) + exp(b - maxVal))
    }
    
    private func logSumExp(_ a: Float, _ b: Float, _ c: Float) -> Float {
        return logSumExp(logSumExp(a, b), c)
    }
    
    func scorePronunciation(userLogits: MLMultiArray, targetPhonemes: [String], vocabulary: [String], greedyAnchors: [(symbol: String, frame: Int)]) -> [PhoneScore] {
        let totalFrames = userLogits.shape[1].intValue
        let vocabSize = userLogits.shape[2].intValue
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(userLogits.dataPointer))
        
        let probs = MathService.softmaxVectorized(logits: ptr, frameCount: totalFrames, vocabSize: vocabSize)
        
        return runCTCForwardBackward(probs: probs, targets: targetPhonemes, vocab: vocabulary, totalFrames: totalFrames, vocabSize: vocabSize)
    }
    
    private func runCTCForwardBackward(probs: [Float], targets: [String], vocab: [String], totalFrames: Int, vocabSize: Int) -> [PhoneScore] {
        if targets.isEmpty || totalFrames == 0 { return [] }
        
        let M = targets.count
        let L = 2 * M + 1
        var E = [Int](repeating: blankIndex, count: L)
        
        // Map target symbols to vocabulary indices. Default to blank if not found.
        for k in 0..<M {
            let symbol = targets[k].replacingOccurrences(of: "ː", with: "")
            E[2*k+1] = vocab.firstIndex(of: symbol) ?? blankIndex
        }
        
        var alpha = [[Float]](repeating: [Float](repeating: -Float.greatestFiniteMagnitude, count: L), count: totalFrames)
        alpha[0][0] = log(max(probs[E[0]], 1e-8))
        alpha[0][1] = log(max(probs[E[1]], 1e-8))
        
        for t in 1..<totalFrames {
            let offset = t * vocabSize
            for s in 0..<L {
                let logProb = log(max(probs[offset + E[s]], 1e-8))
                let a1 = alpha[t-1][s]
                var a2: Float = -Float.greatestFiniteMagnitude
                var a3: Float = -Float.greatestFiniteMagnitude
                
                if s > 0 { a2 = alpha[t-1][s-1] }
                if s > 1 && E[s] != blankIndex && E[s] != E[s-2] { a3 = alpha[t-1][s-2] }
                
                let sumPrev = logSumExp(a1, a2, a3)
                if sumPrev != -Float.greatestFiniteMagnitude {
                    alpha[t][s] = logProb + sumPrev
                }
            }
        }
        
        var beta = [[Float]](repeating: [Float](repeating: -Float.greatestFiniteMagnitude, count: L), count: totalFrames)
        beta[totalFrames-1][L-1] = 0.0
        beta[totalFrames-1][L-2] = 0.0
        
        for t in (0..<totalFrames-1).reversed() {
            let offset = (t + 1) * vocabSize
            for s in 0..<L {
                var b1: Float = -Float.greatestFiniteMagnitude
                var b2: Float = -Float.greatestFiniteMagnitude
                var b3: Float = -Float.greatestFiniteMagnitude
                
                let p1 = log(max(probs[offset + E[s]], 1e-8))
                b1 = beta[t+1][s] + p1
                
                if s + 1 < L {
                    let p2 = log(max(probs[offset + E[s+1]], 1e-8))
                    b2 = beta[t+1][s+1] + p2
                }
                if s + 2 < L && E[s+2] != blankIndex && E[s+2] != E[s] {
                    let p3 = log(max(probs[offset + E[s+2]], 1e-8))
                    b3 = beta[t+1][s+2] + p3
                }
                beta[t][s] = logSumExp(b1, b2, b3)
            }
        }
        
        let pTotal = logSumExp(alpha[totalFrames-1][L-1], alpha[totalFrames-1][L-2])
        
        var metrics: [PhoneScore] = []
        for k in 0..<M {
            let s = 2 * k + 1
            var sumGammaLin: Float = 0.0
            var sumLogP: Float = 0.0
            
            for t in 0..<totalFrames {
                if alpha[t][s] == -Float.greatestFiniteMagnitude || beta[t][s] == -Float.greatestFiniteMagnitude || pTotal == -Float.greatestFiniteMagnitude {
                    continue
                }
                
                let gamma = alpha[t][s] + beta[t][s] - pTotal
                // Prevent NaN if gamma is incredibly small
                if gamma > -30.0 {
                    let gammaLin = exp(gamma)
                    let logP = log(max(probs[t * vocabSize + E[s]], 1e-8))
                    
                    var maxLogP: Float = -Float.greatestFiniteMagnitude
                    let offset = t * vocabSize
                    for v in 0..<vocabSize {
                        let vp = log(max(probs[offset + v], 1e-8))
                        if vp > maxLogP { maxLogP = vp }
                    }
                    
                    sumGammaLin += gammaLin
                    sumLogP += gammaLin * (logP - 0.5 * maxLogP)
                }
            }
            
            // Expected probability is e^(E[logP])
            let score = sumGammaLin > 0.001 ? exp(sumLogP / sumGammaLin) : 0.0
            let frames = Int(round(sumGammaLin))
            
            metrics.append(PhoneScore(symbol: targets[k], gopScore: score, frames: frames))
        }
        
        return metrics
    }
}
