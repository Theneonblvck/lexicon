import AppKit

/// The structured result of one analysis tick. Decoded from the model's JSON
/// response and consumed by the overlay/suggestions UI.
struct AnalysisResult: Codable {
    let goalId: String
    let goalLabel: String
    let confidence: Double
    let suggestions: [Suggestion]
}

/// The three suggestion classes Lexicon distinguishes. Vocabulary and syntax are
/// insertable edits (Tab accepts them); cadence is a flow/rhythm observation that
/// is shown as a comment but not inserted.
enum SuggestionKind: String, Codable {
    case vocabulary
    case syntax
    case cadence

    var isInsertable: Bool { self != .cadence }

    /// Low-saturation system accent per the UX spec.
    var accent: NSColor {
        switch self {
        case .vocabulary: return .systemTeal
        case .syntax:     return .systemIndigo
        case .cadence:    return .systemPink
        }
    }

    var symbolName: String {
        switch self {
        case .vocabulary: return "textformat.abc"
        case .syntax:     return "curlybraces"
        case .cadence:    return "waveform"
        }
    }

    var label: String {
        switch self {
        case .vocabulary: return "Vocabulary"
        case .syntax:     return "Syntax"
        case .cadence:    return "Cadence"
        }
    }
}

struct Suggestion: Codable {
    let kind: SuggestionKind
    /// The span being improved, or nil/empty if additive.
    let original: String?
    /// The higher-precision word/phrase to insert (for cadence: a short headline,
    /// not inserted).
    let replacement: String
    /// One line: why this better serves the inferred goal.
    let rationale: String

    enum CodingKeys: String, CodingKey { case kind, original, replacement, rationale }

    // Tolerant decode — `kind` defaults to vocabulary if missing/unknown so older
    // responses still parse.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(SuggestionKind.self, forKey: .kind)) ?? .vocabulary
        original = try? c.decode(String.self, forKey: .original)
        replacement = (try? c.decode(String.self, forKey: .replacement)) ?? ""
        rationale = (try? c.decode(String.self, forKey: .rationale)) ?? ""
    }

    init(kind: SuggestionKind = .vocabulary, original: String?, replacement: String, rationale: String) {
        self.kind = kind
        self.original = original
        self.replacement = replacement
        self.rationale = rationale
    }
}
