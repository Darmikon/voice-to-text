import Foundation

struct ReviewKeyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ actual: ReviewKeyDecision,
    _ expected: ReviewKeyDecision,
    _ message: String
) throws {
    if actual != expected {
        throw ReviewKeyHarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

@main
struct ReviewKeyPolicyHarness {
    static func main() throws {
        // Default mode: Return sends, Shift+Return inserts a newline.
        try expect(
            ReviewKeyPolicy.decision(sendOnReturn: true, isReturn: true, hasShift: false, matchesSendShortcut: false),
            .send,
            "default Return sends"
        )
        try expect(
            ReviewKeyPolicy.decision(sendOnReturn: true, isReturn: true, hasShift: true, matchesSendShortcut: false),
            .newline,
            "default Shift+Return inserts newline"
        )
        // Newline mode: Return inserts a newline, the configured shortcut sends.
        try expect(
            ReviewKeyPolicy.decision(sendOnReturn: false, isReturn: true, hasShift: false, matchesSendShortcut: false),
            .newline,
            "newline-mode Return inserts newline"
        )
        try expect(
            ReviewKeyPolicy.decision(sendOnReturn: false, isReturn: true, hasShift: false, matchesSendShortcut: true),
            .send,
            "newline-mode send shortcut (e.g. Cmd+Return) sends"
        )
        try expect(
            ReviewKeyPolicy.decision(sendOnReturn: false, isReturn: false, hasShift: false, matchesSendShortcut: true),
            .send,
            "newline-mode non-Return send shortcut sends"
        )
        // The configured send shortcut is ignored in default mode (Return already sends).
        try expect(
            ReviewKeyPolicy.decision(sendOnReturn: true, isReturn: false, hasShift: false, matchesSendShortcut: true),
            .ignore,
            "default mode ignores the configured send shortcut"
        )
        // Unrelated keys are ignored so the monitor passes them through.
        try expect(
            ReviewKeyPolicy.decision(sendOnReturn: true, isReturn: false, hasShift: false, matchesSendShortcut: false),
            .ignore,
            "unrelated key is ignored"
        )

        print("Review key policy harness passed")
    }
}
