import Foundation

public enum SyllableResult: Equatable, Sendable {
  case correct
  case wrongTone
  case missingTone
  case wrong
}

public struct SyllableCheck: Equatable, Sendable {
  public let expected: String
  public let result: SyllableResult
}

/// Compares typed pinyin with the answer. Accepts tone marks (nǐ) or numbers (ni3), with or without
/// spaces. It only reports differences: grading stays with the learner.
public enum PinyinCheck {
  private struct Syllable {
    var base: String
    /// 1–4, or 5 for neutral; nil when the typed text gave no tone.
    var tone: Int?
  }

  private static let marks: [Character: (Character, Int)] = {
    var table: [Character: (Character, Int)] = [:]
    let groups: [(Character, String)] = [("a", "āáǎà"), ("e", "ēéěè"), ("i", "īíǐì"), ("o", "ōóǒò"), ("u", "ūúǔù"), ("v", "ǖǘǚǜ")]
    for (base, marked) in groups {
      for (index, character) in marked.enumerated() { table[character] = (base, index + 1) }
    }
    return table
  }()

  public static func check(typed: String, answer: String) -> [SyllableCheck] {
    let expectedTexts = answer.split(whereSeparator: \.isWhitespace).map(String.init)
    let expected = expectedTexts.map { syllable($0, neutralIfUnmarked: true) }
    let tokens = typed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

    let given: [Syllable?]
    if tokens.count == expected.count {
      given = tokens.map { syllable($0, neutralIfUnmarked: false) }
    } else {
      given = align(tokens.joined(), to: expected)
    }

    return expected.indices.map { index in
      let target = expected[index]
      let result: SyllableResult
      if let attempt = given[index], attempt.base == target.base {
        if attempt.tone == target.tone || (attempt.tone == nil && target.tone == 5) {
          result = .correct
        } else {
          result = attempt.tone == nil ? .missingTone : .wrongTone
        }
      } else {
        result = .wrong
      }
      return SyllableCheck(expected: expectedTexts[index], result: result)
    }
  }

  private static func syllable(_ text: String, neutralIfUnmarked: Bool) -> Syllable {
    var base = ""
    var tone: Int?
    for character in text.lowercased() {
      if let (letter, mark) = marks[character] {
        base.append(letter)
        tone = mark
      } else if character == "ü" {
        base.append("v")
      } else if let digit = character.wholeNumberValue {
        tone = digit == 0 ? 5 : digit
      } else {
        base.append(character)
      }
    }
    return Syllable(base: base, tone: tone ?? (neutralIfUnmarked ? 5 : nil))
  }

  /// For text typed without spaces, walks along the expected syllables. Everything after the first
  /// mismatch counts as wrong, since there's no reliable way to line it up again.
  private static func align(_ text: String, to expected: [Syllable]) -> [Syllable?] {
    var remaining = Substring(text)
    var result: [Syllable?] = []
    for target in expected {
      var consumed = ""
      var letters = 0
      for character in remaining {
        let isDigit = character.isNumber
        if !isDigit && letters == target.base.count { break }
        consumed.append(character)
        if isDigit { break }
        letters += 1
      }
      let attempt = syllable(consumed, neutralIfUnmarked: false)
      guard attempt.base == target.base else {
        result.append(contentsOf: Array(repeating: nil, count: expected.count - result.count))
        return result
      }
      result.append(attempt)
      remaining = remaining.dropFirst(consumed.count)
    }
    return result
  }
}
