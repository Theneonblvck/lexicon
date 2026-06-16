import ApplicationServices
import Foundation

/// Shared inter-step data contract. Emitted by the CaptureEngine (Step 2) and
/// consumed by the AnalysisRouter (Step 3). `elementRef` lets later steps query
/// caret bounds (Step 4) and write the accepted suggestion back (Step 5).
struct CaptureEvent {
    let text: String
    let caretRange: NSRange
    let appBundleId: String
    let appName: String
    let elementRef: AXUIElement
}
