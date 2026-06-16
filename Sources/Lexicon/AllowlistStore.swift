import Foundation

/// Privacy posture: DEFAULT-DENY. Capture is off in every app except those the
/// user explicitly approves. Backed by UserDefaults; an audit log records every
/// app that was ever approved. The capture engine (Step 2) consults this before
/// reading any text.
final class AllowlistStore {
    private let defaults = UserDefaults.standard
    private let allowKey = "lexicon.allowlist.bundleIds"
    private let auditKey = "lexicon.allowlist.auditLog"

    /// Bundle ids currently approved for capture.
    var approvedBundleIds: Set<String> {
        Set(defaults.stringArray(forKey: allowKey) ?? [])
    }

    func isAllowed(_ bundleId: String) -> Bool {
        approvedBundleIds.contains(bundleId)
    }

    func approve(_ bundleId: String) {
        var current = approvedBundleIds
        guard !current.contains(bundleId) else { return }
        current.insert(bundleId)
        defaults.set(Array(current), forKey: allowKey)
        appendAudit("approved \(bundleId)")
    }

    func revoke(_ bundleId: String) {
        var current = approvedBundleIds
        guard current.remove(bundleId) != nil else { return }
        defaults.set(Array(current), forKey: allowKey)
        appendAudit("revoked \(bundleId)")
    }

    var auditLog: [String] { defaults.stringArray(forKey: auditKey) ?? [] }

    private func appendAudit(_ entry: String) {
        var log = auditLog
        let stamp = ISO8601DateFormatter().string(from: Date())
        log.append("\(stamp)  \(entry)")
        defaults.set(log, forKey: auditKey)
    }
}
