import Foundation

/// Turns CaptureEvents into AnalysisResults via a cascading model selection:
///   • Tier 1 (Haiku) on every tick — the cheap, fast hot path.
///   • Tier 2 (Sonnet) when Tier-1 confidence is low, the input is long, or the
///     goal is ambiguous.
///   • Tier 3 (Opus) only for an explicit deep-rewrite request (not the loop).
/// Cancels any in-flight request when a newer CaptureEvent arrives.
final class AnalysisRouter {

    /// Delivered on the main thread with the final result + which tier produced it.
    var onResult: ((AnalysisResult, _ tier: String, _ model: String) -> Void)?

    private let client = ClaudeAPIClient()
    private var current: Task<Void, Never>?

    /// ~600 tokens ≈ 2400 chars: above this, start at Tier 2 instead of Tier 1.
    private let escalateCharThreshold = 2400
    private let confidenceFloor = 0.6

    private var loggedMissingKey = false

    func handle(_ event: CaptureEvent) {
        guard AppConfig.apiKey != nil else {
            if !loggedMissingKey {
                FileLog.write("analysis skipped — no API key (set LEXICON_API_KEY or Keychain)")
                loggedMissingKey = true
            }
            return
        }
        current?.cancel()
        let text = event.text
        let caret = event.caretRange.location
        current = Task { [weak self] in
            await self?.run(text: text, caret: caret)
        }
    }

    /// Explicit, on-demand deep rewrite — escalates straight to Tier 3.
    func requestDeepRewrite(_ event: CaptureEvent) {
        guard AppConfig.apiKey != nil else { return }
        current?.cancel()
        let text = event.text
        let caret = event.caretRange.location
        current = Task { [weak self] in
            await self?.runSingle(text: text, caret: caret,
                                  model: AppConfig.tier3Model, tier: "tier3 (deep rewrite)")
        }
    }

    // MARK: Cascade

    private func run(text: String, caret: Int) async {
        let startHigh = text.count > escalateCharThreshold
        let firstModel = startHigh ? AppConfig.tier2Model : AppConfig.tier1Model
        let firstTier = startHigh ? "tier2 (long input)" : "tier1"

        do {
            let started = Date()
            var result = try await client.analyze(text: text, caret: caret, model: firstModel)
            if Task.isCancelled { return }
            var tier = firstTier
            var model = firstModel

            // Escalate from Tier 1 on low confidence.
            if !startHigh && result.confidence < confidenceFloor {
                let escalated = try await client.analyze(
                    text: text, caret: caret, model: AppConfig.tier2Model)
                if Task.isCancelled { return }
                result = escalated
                tier = "tier2 (escalated, conf<\(confidenceFloor))"
                model = AppConfig.tier2Model
            }

            let ms = Int(Date().timeIntervalSince(started) * 1000)
            FileLog.write("analysis  \(tier) [\(model)]  \(ms)ms  goal=\(result.goalId) (conf \(String(format: "%.2f", result.confidence)))  suggestions=\(result.suggestions.count)")
            await deliver(result, tier, model)
        } catch {
            if Task.isCancelled { return }
            FileLog.write("analysis error [\(firstModel)]: \(error)")
        }
    }

    private func runSingle(text: String, caret: Int, model: String, tier: String) async {
        do {
            let result = try await client.analyze(text: text, caret: caret, model: model)
            if Task.isCancelled { return }
            FileLog.write("analysis  \(tier) [\(model)]  goal=\(result.goalId)  suggestions=\(result.suggestions.count)")
            await deliver(result, tier, model)
        } catch {
            if Task.isCancelled { return }
            FileLog.write("analysis error [\(model)]: \(error)")
        }
    }

    @MainActor
    private func deliver(_ result: AnalysisResult, _ tier: String, _ model: String) {
        onResult?(result, tier, model)
    }
}
