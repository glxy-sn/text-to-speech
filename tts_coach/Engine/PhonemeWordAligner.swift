import Foundation
import NaturalLanguage

struct TextCVToken {
    let type: String // "C" or "V"
    let wordIndex: Int
    let word: String
}

struct PhonemeCVToken {
    let type: String
    let symbol: String
    let originalIndex: Int
}

public class PhonemeWordAligner {
    
    static func isVowelPhoneme(_ symbol: String) -> Bool {
        let vowelChars: Set<Character> = ["a", "e", "i", "o", "u", "y", "ə", "ɛ", "ɪ", "ɐ", "ʊ", "ʌ", "æ", "ɔ", "ɑ", "ɚ", "ɜ", "œ", "ø", "ɨ", "ʉ", "ä", "ɒ", "ɵ", "̃"]
        return symbol.contains { vowelChars.contains(Character(extendedGraphemeClusterLiteral: $0)) || vowelChars.contains(Character(String($0).lowercased())) }
    }
    
    static func isVowelChar(_ char: Character) -> Bool {
        let vowelChars: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        return vowelChars.contains(char)
    }
    
    static func getPinyin(for string: String) -> String {
        let mutableString = NSMutableString(string: string)
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return mutableString as String
    }
    
    public static func tokenize(text: String) -> [String] {
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
    
    // Existing fallback method
    public static func align(targetScript: String, phonemes: [String]) -> [(word: String, phonemeIndices: [Int])] {
        let words = tokenize(text: targetScript)
        
        var textTokens = [TextCVToken]()
        for (idx, word) in words.enumerated() {
            let pinyinOrLatin = getPinyin(for: word).lowercased()
            for char in pinyinOrLatin {
                if char.isLetter {
                    textTokens.append(TextCVToken(type: isVowelChar(char) ? "V" : "C", wordIndex: idx, word: word))
                }
            }
        }
        
        var phonemeTokens = [PhonemeCVToken]()
        for (idx, p) in phonemes.enumerated() {
            if ["<pad>", "<s>", "</s>", "<unk>"].contains(p) { continue }
            phonemeTokens.append(PhonemeCVToken(type: isVowelPhoneme(p) ? "V" : "C", symbol: p, originalIndex: idx))
        }
        
        if textTokens.isEmpty || phonemeTokens.isEmpty {
            return []
        }
        
        let n = textTokens.count
        let m = phonemeTokens.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        
        let matchScore = 2
        let mismatchScore = -1
        let gapScore = -1
        
        for i in 1...n { dp[i][0] = i * gapScore }
        for j in 1...m { dp[0][j] = j * gapScore }
        
        for i in 1...n {
            for j in 1...m {
                let match = dp[i-1][j-1] + (textTokens[i-1].type == phonemeTokens[j-1].type ? matchScore : mismatchScore)
                let delete = dp[i-1][j] + gapScore
                let insert = dp[i][j-1] + gapScore
                dp[i][j] = max(match, max(delete, insert))
            }
        }
        
        var i = n
        var j = m
        var assignments = [Int: Int]()
        
        while i > 0 && j > 0 {
            let currentScore = dp[i][j]
            let match = dp[i-1][j-1] + (textTokens[i-1].type == phonemeTokens[j-1].type ? matchScore : mismatchScore)
            
            if currentScore == match {
                assignments[phonemeTokens[j-1].originalIndex] = textTokens[i-1].wordIndex
                i -= 1
                j -= 1
            } else if currentScore == dp[i-1][j] + gapScore {
                i -= 1
            } else {
                j -= 1
            }
        }
        
        var resultGroups = [(word: String, phonemeIndices: [Int])]()
        for word in words {
            resultGroups.append((word: word, phonemeIndices: []))
        }
        
        var lastWordIndex = 0
        for (idx, p) in phonemes.enumerated() {
            if ["<pad>", "<s>", "</s>", "<unk>"].contains(p) { continue }
            if let wIndex = assignments[idx] { lastWordIndex = wIndex }
            if lastWordIndex < resultGroups.count { resultGroups[lastWordIndex].phonemeIndices.append(idx) }
        }
        
        return resultGroups
    }

    struct HybridTextToken {
        let char: Character
        let type: String // "C" or "V"
        let wordIndex: Int
        let word: String
        let startTime: Double
        let endTime: Double
    }
    
    private static func phoneticSimilarity(char: Character, phoneme: String) -> Double {
        let c = String(char).lowercased()
        let pOriginal = phoneme.lowercased()
        
        let exactMatches: [String: [String]] = [
            "p": ["p", "ph", "pʰ", "pʲ", "pː"], "b": ["b", "bʰ", "bʲ", "bː"],
            "t": ["t", "ɾ", "th", "tʰ", "tʲ", "tː"], "d": ["d", "ɾ", "dʰ", "dʲ", "dː", "dˤ", "ɖ", "ɖʰ"],
            "k": ["k", "kh", "kʰ", "kʲ", "kː", "q", "qː"], "g": ["g", "ɡ", "ɡʰ", "ɡʲ", "ɡː", "ɢ", "ɟ", "ŋ"],
            "f": ["f", "fʲ", "ɸ"], "v": ["v", "vʲ", "ʋ", "β"], 
            "s": ["s", "sʲ", "s̪", "ʂ", "ʂʲ", "ʃ"], "z": ["z", "dz", "ts", "tsh", "tsʰ", "tʂ", "tʂʰ", "dzː"],
            "m": ["m", "mʲ"], "n": ["n", "nʲ", "n̩", "ɳ", "ɲ", "ɴ", "ŋ"], "l": ["l", "l̩", "ɭ", "ʎ", "lː", "ɫ"],
            "r": ["ɹ", "r", "ɚ", "rʲ", "r̩", "r̝", "r̝̊", "ɽ", "ʐ", "ɻ", "ʁ"],
            "h": ["h", "x", "xʲ", "χ", "ħ", "ʕ", "ɦ", "ʂ", "tʂ", "tʂʰ"],
            "w": ["w"], "y": ["j", "ʝ", "ʎ"],
            "c": ["k", "s", "tʃ", "ts", "tsh", "tsʰ", "tɕ", "tɕh", "tɕʰ", "c", "cʰ", "cː", "tʂʰ", "ʈʰ"],
            "q": ["k", "tɕ", "tɕh", "tɕʰ", "q", "qː"], 
            "x": ["k", "s", "z", "ɕ", "ɕʲ", "x", "xʲ"],
            "j": ["j", "dʒ", "tɕ", "tɕh", "tɕʰ", "dʑ", "dʑʲ", "ɟ"]
        ]
        
        // Match exact original phoneme first
        if let matches = exactMatches[c], matches.contains(pOriginal) { return 3.0 }
        
        // Clean phoneme for vowel and class checking (strip digits, length marks, and aspiration)
        let pClean = pOriginal.replacingOccurrences(of: "[0-9ː.ˤɜʰhʲ]", with: "", options: .regularExpression)
        if c == pClean { return 3.0 }
        
        let labials = ["p", "b", "f", "v", "m", "w", "ʋ", "β", "ɸ"]
        let alveolars = ["t", "d", "s", "z", "n", "l", "ɹ", "r", "θ", "ð", "ɾ", "ts", "dz"]
        let velars = ["k", "g", "ɡ", "ŋ", "q", "x", "ɣ", "n"]
        let palatals = ["ʃ", "ʒ", "tʃ", "dʒ", "j", "tɕ", "dʑ", "ɕ", "ɲ", "ʎ", "c", "ɟ"]
        let retroflexes = ["ʈ", "ɖ", "ʂ", "ʐ", "ɻ", "ɳ", "ɭ", "tʂ", "s", "z"]
        
        func getClass(_ s: String) -> Int {
            if labials.contains(s) { return 1 }
            if alveolars.contains(s) { return 2 }
            if velars.contains(s) { return 3 }
            if palatals.contains(s) { return 4 }
            if retroflexes.contains(s) { return 5 }
            return 0
        }
        
        let charClass = getClass(c)
        let phoneClass = getClass(pClean)
        
        if charClass != 0 && charClass == phoneClass { return 1.5 }
        
        let isCharVow = "aeiouy".contains(c)
        let isPhoneVow = ["a", "e", "i", "o", "u", "y", "ə", "ɛ", "ɪ", "ɐ", "ʊ", "ʌ", "æ", "ɔ", "ɑ", "ɚ", "œ", "ø", "ɨ", "ʉ", "ä", "ɒ", "ɵ", "̃"].contains { pClean.contains($0) }
        
        if isCharVow && isPhoneVow { return 2.0 }
        if !isCharVow && !isPhoneVow { return 0.0 }
        
        return -2.0
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
    
    private static func normalizeEnglishSpelling(_ word: String) -> String {
        var w = word.lowercased()
        if w.hasSuffix("e") && w.count > 2 {
            let prefix = w.dropLast()
            let vowelChars: Set<Character> = ["a", "e", "i", "o", "u", "y"]
            if prefix.contains(where: { vowelChars.contains($0) }) {
                w = String(prefix)
            }
        }
        w = w.replacingOccurrences(of: "th", with: "t")
        w = w.replacingOccurrences(of: "sh", with: "s")
        w = w.replacingOccurrences(of: "ch", with: "c")
        w = w.replacingOccurrences(of: "ph", with: "f")
        w = w.replacingOccurrences(of: "gh", with: "g")
        w = w.replacingOccurrences(of: "ou", with: "o")
        w = w.replacingOccurrences(of: "ea", with: "e")
        w = w.replacingOccurrences(of: "ee", with: "e")
        w = w.replacingOccurrences(of: "oo", with: "o")
        w = w.replacingOccurrences(of: "ai", with: "a")
        return w
    }
    
    public static func alignHybrid(targetScript: String, asrTimings: [SpeechAlignmentService.WordTiming], phonemes: [(symbol: String, frame: Int)]) -> [(word: String, phonemeIndices: [Int])] {
        let words = tokenize(text: targetScript)
        
        var textTokens = [HybridTextToken]()
        for (idx, word) in words.enumerated() {
            let timing = (idx < asrTimings.count) ? asrTimings[idx] : SpeechAlignmentService.WordTiming(word: word, startTime: 0, endTime: 0)
            
            var spelledWord = spellOutNumbers(in: word)
            spelledWord = normalizeEnglishSpelling(spelledWord)
            let pinyinOrLatin = getPinyin(for: spelledWord).lowercased()
            
            var wordHasLetters = false
            for char in pinyinOrLatin {
                if char.isLetter {
                    wordHasLetters = true
                    textTokens.append(HybridTextToken(
                        char: char,
                        type: isVowelChar(char) ? "V" : "C",
                        wordIndex: idx,
                        word: word,
                        startTime: timing.startTime,
                        endTime: timing.endTime
                    ))
                }
            }
            if !wordHasLetters {
                textTokens.append(HybridTextToken(char: "x", type: "C", wordIndex: idx, word: word, startTime: timing.startTime, endTime: timing.endTime))
            }
        }
        
        struct HybridPhonemeToken {
            let type: String
            let symbol: String
            let originalIndex: Int
            let timestamp: Double
        }
        
        var phonemeTokens = [HybridPhonemeToken]()
        for (idx, p) in phonemes.enumerated() {
            if ["<pad>", "<s>", "</s>", "<unk>"].contains(p.symbol) { continue }
            phonemeTokens.append(HybridPhonemeToken(
                type: isVowelPhoneme(p.symbol) ? "V" : "C",
                symbol: p.symbol,
                originalIndex: idx,
                timestamp: Double(p.frame) * 0.02
            ))
        }
        
        let n = textTokens.count
        let m = phonemeTokens.count
        
        if n == 0 || m == 0 { return [] }
        
        let textGapScore = -1.5 // Skipping an expected text token is cheap (English spelling is imprecise)
        let phonemeGapScore = -100.0 // Skipping an actual acoustic phoneme is heavily penalized
        let timePenaltyFactor = 20.0 
        
        var dp = [[Double]](repeating: [Double](repeating: -Double.infinity, count: m + 1), count: n + 1)
        struct State { let i: Int; let j: Int }
        var backtrace = [[State?]](repeating: [State?](repeating: nil, count: m + 1), count: n + 1)
        
        dp[0][0] = 0.0
        
        for i in 1...n { 
            dp[i][0] = dp[i-1][0] + textGapScore 
            backtrace[i][0] = State(i: i-1, j: 0)
        }
        for j in 1...m { 
            dp[0][j] = dp[0][j-1] + phonemeGapScore 
            backtrace[0][j] = State(i: 0, j: j-1)
        }
        
        for i in 1...n {
            for j in 1...m {
                let tToken = textTokens[i-1]
                let pToken = phonemeTokens[j-1]
                
                let baseScore = phoneticSimilarity(char: tToken.char, phoneme: pToken.symbol)
                let timeDistance = max(0, pToken.timestamp - tToken.endTime) + max(0, tToken.startTime - pToken.timestamp)
                let timePenalty = timeDistance * timePenaltyFactor
                
                let match = dp[i-1][j-1] + baseScore - timePenalty
                let absorb = dp[i][j-1] + baseScore - timePenalty // text token i absorbs multiple consecutive phonemes
                let delete = dp[i-1][j] + textGapScore // skip text token
                let insert = dp[i][j-1] + phonemeGapScore // skip phoneme
                
                let maxScore = max(match, max(absorb, max(delete, insert)))
                dp[i][j] = maxScore
                
                if maxScore == match { backtrace[i][j] = State(i: i-1, j: j-1) }
                else if maxScore == absorb { backtrace[i][j] = State(i: i, j: j-1) }
                else if maxScore == delete { backtrace[i][j] = State(i: i-1, j: j) }
                else { backtrace[i][j] = State(i: i, j: j-1) }
            }
        }
        
        var currI = n
        var currJ = m
        var assignments = [Int: [Int]]() // phoneme index -> list of word indices
        
        while currI > 0 || currJ > 0 {
            guard let prev = backtrace[currI][currJ] else { break }
            
            if prev.j < currJ {
                let pIdx = currJ - 1
                if assignments[pIdx] == nil { assignments[pIdx] = [] }
                
                if prev.i < currI {
                    // Match
                    if !(assignments[pIdx]!.contains(textTokens[currI-1].wordIndex)) {
                        assignments[pIdx]!.append(textTokens[currI-1].wordIndex)
                    }
                } else if prev.i == currI && currI > 0 {
                    // Absorb
                    let tToken = textTokens[currI-1]
                    let pToken = phonemeTokens[currJ-1]
                    let baseScore = phoneticSimilarity(char: tToken.char, phoneme: pToken.symbol)
                    let timeDistance = max(0, pToken.timestamp - tToken.endTime) + max(0, tToken.startTime - pToken.timestamp)
                    let absorbScore = dp[prev.i][prev.j] + baseScore - (timeDistance * timePenaltyFactor)
                    
                    if abs(dp[currI][currJ] - absorbScore) < 1e-5 {
                        if !(assignments[pIdx]!.contains(tToken.wordIndex)) {
                            assignments[pIdx]!.append(tToken.wordIndex)
                        }
                    }
                }
            } else if prev.j == currJ && prev.i < currI {
                // Text token was skipped (Delete)
                let skippedToken = textTokens[currI-1]
                // If a consonant text token was skipped, it might be due to coarticulation/gemination where 
                // the speaker merged it with an adjacent identical phoneme (e.g. "just to" -> single 't').
                // We can share the adjacent phoneme with this word!
                if currJ > 0 {
                    let pToken = phonemeTokens[currJ-1]
                    let sim = phoneticSimilarity(char: skippedToken.char, phoneme: pToken.symbol)
                    if sim >= 1.5 { // Class match or perfect match
                        if assignments[currJ-1] == nil { assignments[currJ-1] = [] }
                        if !(assignments[currJ-1]!.contains(skippedToken.wordIndex)) {
                            assignments[currJ-1]!.append(skippedToken.wordIndex)
                        }
                    }
                }
            }
            
            currI = prev.i
            currJ = prev.j
        }
        
        var resultGroups = [(word: String, phonemeIndices: [Int])]()
        for word in words { resultGroups.append((word: word, phonemeIndices: [])) }
        for j in 0..<phonemes.count {
            if let wIdxs = assignments[j] {
                for wIdx in wIdxs {
                    resultGroups[wIdx].phonemeIndices.append(j)
                }
            }
        }
        
        return resultGroups
    }
}
