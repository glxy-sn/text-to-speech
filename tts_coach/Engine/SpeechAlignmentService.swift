import Foundation
import Speech
import NaturalLanguage

public actor SpeechAlignmentService {
    
    public struct WordTiming {
        let word: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }
    
    public static func getWordTimings(audioURL: URL, localeIdentifier: String) async throws -> [WordTiming] {
        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw NSError(domain: "SpeechAlignmentService", code: 1, userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer not supported for locale \(localeIdentifier)"])
        }
        
        if !recognizer.isAvailable {
            throw NSError(domain: "SpeechAlignmentService", code: 2, userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer is not available at the moment"])
        }
        
        let hasAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        guard hasAuth else {
            throw NSError(domain: "SpeechAlignmentService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"])
        }
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        
        return try await withCheckedThrowingContinuation { continuation in
            var isFinished = false
            recognizer.recognitionTask(with: request) { result, error in
                if isFinished { return }
                
                if let error = error {
                    isFinished = true
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result, result.isFinal {
                    isFinished = true
                    let segments = result.bestTranscription.segments
                    let timings = segments.map { segment in
                        WordTiming(word: segment.substring, startTime: segment.timestamp, endTime: segment.timestamp + segment.duration)
                    }
                    continuation.resume(returning: timings)
                }
            }
        }
    }
    private nonisolated static func tokenize(text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words = [String]()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let token = String(text[tokenRange])
            if token.range(of: "\\p{Han}", options: .regularExpression) != nil {
                for char in token {
                    words.append(String(char))
                }
            } else {
                words.append(token)
            }
            return true
        }
        return words
    }
    
    private static func charsMatch(_ a: Character, _ b: Character) -> Bool {
        if a == b { return true }
        
        let strA = NSMutableString(string: String(a))
        CFStringTransform(strA, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(strA, nil, kCFStringTransformStripDiacritics, false)
        
        let strB = NSMutableString(string: String(b))
        CFStringTransform(strB, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(strB, nil, kCFStringTransformStripDiacritics, false)
        
        return strA == strB
    }
    
    private static func spellOutNumbers(in word: String) -> String {
        let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
        if let num = Double(cleanWord) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .spellOut
            return formatter.string(from: NSNumber(value: num)) ?? word
        }
        return word
    }

    public static func alignTimingsToTarget(targetScript: String, asrTimings: [WordTiming]) -> [WordTiming] {
        let targetWords = SpeechAlignmentService.tokenize(text: targetScript)
        
        if targetWords.isEmpty { return [] }
        if asrTimings.isEmpty {
            // fallback
            return targetWords.map { WordTiming(word: $0, startTime: 0, endTime: 0) }
        }
        
        // 1. Flatten target words into characters, keeping track of their parent word index
        struct TargetChar {
            let char: Character
            let wordIndex: Int
        }
        var targetChars = [TargetChar]()
        for (i, word) in targetWords.enumerated() {
            let spelledWord = SpeechAlignmentService.spellOutNumbers(in: word)
            for char in spelledWord where !char.isWhitespace {
                targetChars.append(TargetChar(char: Character(char.lowercased()), wordIndex: i))
            }
        }
        
        // 2. Flatten ASR timings into characters with linearly interpolated timings
        struct ASRChar {
            let char: Character
            let startTime: TimeInterval
            let endTime: TimeInterval
        }
        var asrChars = [ASRChar]()
        for timing in asrTimings {
            let spelledWord = SpeechAlignmentService.spellOutNumbers(in: timing.word)
            let chars = Array(spelledWord.filter { !$0.isWhitespace })
            if chars.isEmpty { continue }
            
            let durationPerChar = (timing.endTime - timing.startTime) / TimeInterval(chars.count)
            for (i, char) in chars.enumerated() {
                let cStart = timing.startTime + durationPerChar * TimeInterval(i)
                let cEnd = cStart + durationPerChar
                asrChars.append(ASRChar(char: Character(char.lowercased()), startTime: cStart, endTime: cEnd))
            }
        }
        
        if targetChars.isEmpty || asrChars.isEmpty {
            return targetWords.map { WordTiming(word: $0, startTime: 0, endTime: 0) }
        }
        
        // 3. Needleman-Wunsch DP Alignment on characters
        let n = targetChars.count
        let m = asrChars.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        
        let matchScore = 2
        let mismatchScore = -1
        let gapScore = -1
        
        for i in 1...n { dp[i][0] = i * gapScore }
        for j in 1...m { dp[0][j] = j * gapScore }
        
        for i in 1...n {
            for j in 1...m {
                let isMatch = SpeechAlignmentService.charsMatch(targetChars[i-1].char, asrChars[j-1].char)
                let match = dp[i-1][j-1] + (isMatch ? matchScore : mismatchScore)
                let delete = dp[i-1][j] + gapScore
                let insert = dp[i][j-1] + gapScore
                dp[i][j] = max(match, max(delete, insert))
            }
        }
        
        var i = n
        var j = m
        var targetCharToASRIndex = [Int: Int]()
        
        while i > 0 && j > 0 {
            let currentScore = dp[i][j]
            let isMatch = SpeechAlignmentService.charsMatch(targetChars[i-1].char, asrChars[j-1].char)
            let match = dp[i-1][j-1] + (isMatch ? matchScore : mismatchScore)
            
            if currentScore == match {
                targetCharToASRIndex[i-1] = j-1
                i -= 1
                j -= 1
            } else if currentScore == dp[i-1][j] + gapScore {
                i -= 1
            } else {
                j -= 1
            }
        }

        
        // 4. Aggregate back to words
        var alignedTimings = [WordTiming]()
        for wordIndex in 0..<targetWords.count {
            var firstStartTime: TimeInterval? = nil
            var lastEndTime: TimeInterval? = nil
            
            for (charIdx, tChar) in targetChars.enumerated() where tChar.wordIndex == wordIndex {
                if let asrIdx = targetCharToASRIndex[charIdx] {
                    let aChar = asrChars[asrIdx]
                    if firstStartTime == nil {
                        firstStartTime = aChar.startTime
                    }
                    // Since characters are appended in order, the last one assigned updates this correctly.
                    lastEndTime = aChar.endTime
                }
            }
            
            if let start = firstStartTime, let end = lastEndTime {
                alignedTimings.append(WordTiming(word: targetWords[wordIndex], startTime: start, endTime: end))
            } else {
                alignedTimings.append(WordTiming(word: targetWords[wordIndex], startTime: -1, endTime: -1))
            }
        }
        
        // 5. Interpolate missing timings (-1)
        for k in 0..<alignedTimings.count {
            if alignedTimings[k].startTime == -1 {
                var prevEnd: TimeInterval = 0
                if k > 0, alignedTimings[k-1].endTime != -1 {
                    prevEnd = alignedTimings[k-1].endTime
                }
                
                var nextStart: TimeInterval = prevEnd
                for nextK in (k+1)..<alignedTimings.count {
                    if alignedTimings[nextK].startTime != -1 {
                        nextStart = alignedTimings[nextK].startTime
                        break
                    }
                }
                
                alignedTimings[k] = WordTiming(word: alignedTimings[k].word, startTime: prevEnd, endTime: nextStart)
            }
        }
        
        return alignedTimings
    }
}
