import Foundation

/// What the review form should do with a key event. `.newline` and `.ignore`
/// both let the event reach the NSTextView (one inserts a line break, the
/// other is simply not ours); only `.send` is consumed by the key monitor.
enum ReviewKeyDecision: Equatable {
    case send
    case newline
    case ignore
}

/// Pure mapping from "what was pressed" to a review-form decision, so the
/// send/newline rules can be unit-tested without AppKit. The caller derives the
/// booleans from the NSEvent and the user's settings.
enum ReviewKeyPolicy {
    static func decision(
        sendOnReturn: Bool,
        isReturn: Bool,
        hasShift: Bool,
        matchesSendShortcut: Bool
    ) -> ReviewKeyDecision {
        if sendOnReturn {
            // Return sends; Shift+Return inserts a newline. The configured
            // send shortcut is inert in this mode (Return already sends).
            guard isReturn else { return .ignore }
            return hasShift ? .newline : .send
        }
        // Newline mode: the configured shortcut sends; Return inserts a newline.
        if matchesSendShortcut { return .send }
        return isReturn ? .newline : .ignore
    }
}
