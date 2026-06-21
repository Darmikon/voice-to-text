# Review-form Shortcuts & Re-record Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the recording shortcut drive the whole dictation loop (record → stop → in-review re-record), send the reviewed text with Return (Shift+Return = newline, configurable), and keep the form visible with a compact waveform during re-record.

**Architecture:** Pure decision logic (hotkey-state policy, review-key send/newline policy, settings persistence) lives in small testable files under `Hotkey/` and is covered by the existing standalone `swiftc` harness pattern in `Tests/`. The controller (`DictationController`) and UI (`LiveHUD`, `SettingsView`, `ReviewBeforePasteCard`) wire those decisions in; UI/controller changes are validated by build + manual checklist, matching how the codebase already treats `@MainActor` UI code.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSTextView/NSPanel), Carbon hotkeys. Tests are standalone `swiftc -parse-as-library` executables run via `Tests/run-hotkey-harnesses.sh`.

Reference design: `docs/superpowers/specs/2026-06-21-review-form-shortcuts-design.md`.

Spec note on the "in-form re-record" gating: the design mentions an `isReviewTake` flag. During implementation we derive that condition from `resumeContext != nil` (already set exactly for the resume cycle and cleared when its result is consumed), so no separate boolean is added. The compact waveform reuses `LiveHUDState.levelHistory`, which the recorder already feeds via `setLevel`.

---

## File Structure

- `VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift` — add `resumeRecording` action; remap `.reviewing` press.
- `VoiceToText/VoiceToText/Hotkey/ReviewKeyPolicy.swift` *(new)* — pure send/newline decision for the review form.
- `VoiceToText/VoiceToText/Hotkey/HotkeyBinding.swift` — `HotkeyStore` gains `sendOnReturn` + `sendShortcut` with persistence.
- `VoiceToText/VoiceToText/Dictation/DictationController.swift` — handle `resumeRecording`; in-form take; append-at-end; send/newline via `ReviewKeyPolicy`; remove ⌘R.
- `VoiceToText/VoiceToText/UI/LiveHUD.swift` — `ReviewTakePhase`, compact waveform strip, button re-layout + hints.
- `VoiceToText/VoiceToText/Settings/SettingsView.swift` — newline toggle + Send shortcut-capture cards.
- `VoiceToText/VoiceToText/Settings/ReviewBeforePasteCard.swift` — update static preview mock.
- `Tests/HotkeyBehaviorHarness.swift` — update reviewing assertions.
- `Tests/ReviewKeyPolicyHarness.swift` *(new)* — cover send/newline decisions.
- `Tests/HotkeyStoreHarness.swift` — cover new settings round-trip.
- `Tests/run-hotkey-harnesses.sh` — register the new harness.

---

## Task 1: Hotkey policy — `resumeRecording` while reviewing

**Files:**
- Modify: `VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift`
- Test: `Tests/HotkeyBehaviorHarness.swift:45-54`

- [ ] **Step 1: Update the failing assertions in the harness**

In `Tests/HotkeyBehaviorHarness.swift`, replace the two reviewing assertions (currently expecting `.confirmPaste`) so they expect the new action:

```swift
        try expect(
            DictationHotkeyPolicy.action(mode: .toggle, state: .reviewing, event: .pressed),
            .resumeRecording,
            "toggle press re-records from review"
        )
        try expect(
            DictationHotkeyPolicy.action(mode: .hold, state: .reviewing, event: .pressed),
            .resumeRecording,
            "hold press re-records from review"
        )
```

- [ ] **Step 2: Run the harness to verify it fails**

Run: `bash Tests/run-hotkey-harnesses.sh`
Expected: FAIL — compile error `type 'DictationHotkeyAction' has no member 'resumeRecording'`.

- [ ] **Step 3: Add the action case and remap the policy**

In `HotkeyActionPolicy.swift`, add the case to the enum:

```swift
enum DictationHotkeyAction: Equatable {
    case none
    case startRecording
    case stopAndTranscribe
    case confirmPaste
    case resumeRecording
    case cancelRecording
    case cancelPendingRecording
}
```

In `holdAction`, change the reviewing line:

```swift
        case (.reviewing, .pressed):
            return .resumeRecording
```

In `toggleAction`, change the reviewing case:

```swift
        case .reviewing:
            return .resumeRecording
```

- [ ] **Step 4: Run the harness to verify it passes**

Run: `bash Tests/run-hotkey-harnesses.sh`
Expected: PASS — prints `Hotkey behavior harness passed` (and all other harnesses pass).

- [ ] **Step 5: Commit**

```bash
git add VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift Tests/HotkeyBehaviorHarness.swift
git commit -m "feat(hotkey): re-record from review instead of paste"
```

---

## Task 2: `ReviewKeyPolicy` — pure send/newline decision

**Files:**
- Create: `VoiceToText/VoiceToText/Hotkey/ReviewKeyPolicy.swift`
- Create: `Tests/ReviewKeyPolicyHarness.swift`
- Modify: `Tests/run-hotkey-harnesses.sh`

- [ ] **Step 1: Write the failing test harness**

Create `Tests/ReviewKeyPolicyHarness.swift`:

```swift
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
```

- [ ] **Step 2: Register the harness in the runner**

Append to `Tests/run-hotkey-harnesses.sh` (after the last block, before EOF):

```bash
swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/ReviewKeyPolicy.swift \
  Tests/ReviewKeyPolicyHarness.swift \
  -o "$TMPDIR/review-key-policy-harness"
"$TMPDIR/review-key-policy-harness"
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash Tests/run-hotkey-harnesses.sh`
Expected: FAIL — compile error `cannot find 'ReviewKeyPolicy' in scope`.

- [ ] **Step 4: Write the implementation**

Create `VoiceToText/VoiceToText/Hotkey/ReviewKeyPolicy.swift`:

```swift
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
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash Tests/run-hotkey-harnesses.sh`
Expected: PASS — prints `Review key policy harness passed`.

- [ ] **Step 6: Commit**

```bash
git add VoiceToText/VoiceToText/Hotkey/ReviewKeyPolicy.swift Tests/ReviewKeyPolicyHarness.swift Tests/run-hotkey-harnesses.sh
git commit -m "feat(review): add pure send/newline key policy"
```

---

## Task 3: `HotkeyStore` — newline toggle + send shortcut

**Files:**
- Modify: `VoiceToText/VoiceToText/Hotkey/HotkeyBinding.swift:129-180`
- Test: `Tests/HotkeyStoreHarness.swift`

- [ ] **Step 1: Add failing assertions to the store harness**

In `Tests/HotkeyStoreHarness.swift`, inside the `MainActor.run` block, after the existing binding assertions (before `print("Hotkey store harness passed")`), add:

```swift
            let sendOnReturnKey = "review.sendOnReturn.v1"
            let sendShortcutKey = "review.sendShortcut.v1"
            defaults.removeObject(forKey: sendOnReturnKey)
            defaults.removeObject(forKey: sendShortcutKey)

            try expect(store.sendOnReturn == true, "send-on-return defaults to true")
            try expect(store.sendShortcut == .commandReturnBinding, "send shortcut defaults to Cmd+Return")

            store.updateSendOnReturn(to: false)
            try expect(store.sendOnReturn == false, "send-on-return updates in memory")
            try expect(defaults.object(forKey: sendOnReturnKey) as? Bool == false, "send-on-return persists")

            let custom = HotkeyBinding(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey), keyLabel: "D")
            store.updateSendShortcut(to: custom)
            let savedSend = defaults.data(forKey: sendShortcutKey)
            try expect(savedSend != nil, "send shortcut persists to defaults")
            let decodedSend = try JSONDecoder().decode(HotkeyBinding.self, from: savedSend ?? Data())
            try expect(decodedSend == custom, "persisted send shortcut decodes back")

            defaults.removeObject(forKey: sendOnReturnKey)
            defaults.removeObject(forKey: sendShortcutKey)
```

Add the matching cleanup so the harness leaves defaults untouched — extend the existing `defer` block at the top of `main()` with:

```swift
        let previousSendOnReturn = defaults.object(forKey: "review.sendOnReturn.v1")
        let previousSendShortcut = defaults.data(forKey: "review.sendShortcut.v1")
```

declared next to `previousBinding`/`previousMode`, and inside the existing `defer { ... }` add:

```swift
            if let previousSendOnReturn {
                defaults.set(previousSendOnReturn, forKey: "review.sendOnReturn.v1")
            } else {
                defaults.removeObject(forKey: "review.sendOnReturn.v1")
            }
            if let previousSendShortcut {
                defaults.set(previousSendShortcut, forKey: "review.sendShortcut.v1")
            } else {
                defaults.removeObject(forKey: "review.sendShortcut.v1")
            }
```

The harness already imports `Carbon.HIToolbox` (for `kVK_*`/`cmdKey`); no new import needed.

- [ ] **Step 2: Run to verify it fails**

Run: `bash Tests/run-hotkey-harnesses.sh`
Expected: FAIL — compile error `value of type 'HotkeyStore' has no member 'sendOnReturn'`.

- [ ] **Step 3: Add the default binding constant**

In `HotkeyBinding.swift`, after `rightControlBinding` (around line 21), add:

```swift
    static let commandReturnBinding = HotkeyBinding(
        keyCode: UInt32(kVK_Return),
        modifiers: UInt32(cmdKey),
        keyLabel: "Return"
    )
```

- [ ] **Step 4: Extend `HotkeyStore` with the new settings**

In `HotkeyStore` (starts line 131), add storage keys, properties, updaters, and load/save. Add next to the existing `bindingStorageKey`/`modeStorageKey`:

```swift
    private let sendOnReturnStorageKey = "review.sendOnReturn.v1"
    private let sendShortcutStorageKey = "review.sendShortcut.v1"
    private(set) var sendOnReturn: Bool = true
    private(set) var sendShortcut: HotkeyBinding = .commandReturnBinding
```

Add updater methods next to `updateMode`:

```swift
    func updateSendOnReturn(to new: Bool) {
        guard new != sendOnReturn else { return }
        sendOnReturn = new
        UserDefaults.standard.set(new, forKey: sendOnReturnStorageKey)
    }

    func updateSendShortcut(to new: HotkeyBinding) {
        guard new != sendShortcut else { return }
        sendShortcut = new
        if let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: sendShortcutStorageKey)
        }
    }
```

Extend `load()` (after the mode-loading block, before its closing brace):

```swift
        if UserDefaults.standard.object(forKey: sendOnReturnStorageKey) != nil {
            sendOnReturn = UserDefaults.standard.bool(forKey: sendOnReturnStorageKey)
        }

        if let data = UserDefaults.standard.data(forKey: sendShortcutStorageKey),
           let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            sendShortcut = decoded
        }
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash Tests/run-hotkey-harnesses.sh`
Expected: PASS — prints `Hotkey store harness passed`.

- [ ] **Step 6: Commit**

```bash
git add VoiceToText/VoiceToText/Hotkey/HotkeyBinding.swift Tests/HotkeyStoreHarness.swift
git commit -m "feat(settings): persist newline toggle and send shortcut"
```

---

## Task 4: LiveHUD — review-take phase, waveform strip, button re-layout

**Files:**
- Modify: `VoiceToText/VoiceToText/UI/LiveHUD.swift`

This task is validated by build + manual checklist (Task 8); the codebase does not unit-test `@MainActor` SwiftUI views.

- [ ] **Step 1: Add the take phase to `LiveHUDState`**

In `LiveHUD.swift`, add the enum near `LiveHUDMode` (after line 26):

```swift
/// Sub-phase shown inside the review form when the user re-records ("dozapis")
/// without leaving the form. `.none` is the normal editable review.
enum ReviewTakePhase {
    case none
    case recording
    case transcribing
}
```

Add the stored property to `LiveHUDState` (next to `var mode`):

```swift
    var reviewTakePhase: ReviewTakePhase = .none
```

- [ ] **Step 2: Reset the phase in every panel transition**

In `LiveHUDPanel`, set `state.reviewTakePhase = .none` inside `show(...)`, `showReview(...)`, `showFailure(...)`, and `hide()` (alongside the other `state.` resets in each). Do **not** reset it in `showTranscribing()` (the in-form take drives it directly). This guarantees a normal review/record/failure screen never shows a stale strip.

- [ ] **Step 3: Render the compact strip in `ReviewView`**

In `ReviewView.body` (line 639), insert the strip between the `ReviewTextEditor` block and the `if state.reviewShowsActions` block:

```swift
            if state.reviewTakePhase != .none {
                ReviewTakeStrip(state: state)
            }
```

Add the new view (place it after `ReviewView` in the file):

```swift
/// Compact in-form indicator shown while re-recording from the review form:
/// a short waveform (reusing the recorded level history) plus a timer/hint
/// while recording, and a shimmer while the new take transcribes. Sits between
/// the editor and the buttons so the prior text stays visible.
private struct ReviewTakeStrip: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        Group {
            switch state.reviewTakePhase {
            case .recording:
                HStack(spacing: 12) {
                    LevelBars(samples: state.levelHistory)
                        .frame(height: 28)
                    Text(timeString)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
            case .transcribing:
                HStack(spacing: 9) {
                    ShimmerText("Transcribing")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .frame(height: 28)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var timeString: String {
        let total = Int(state.elapsedSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var hint: String {
        let keys = HotkeyStore.shared.binding.displayKeys.joined()
        return "Press \(keys) to finish · Esc cancels"
    }
}
```

- [ ] **Step 4: Re-layout the button row and fix hints**

Replace the bottom `HStack` in `ReviewView` (currently lines 652-683) with this order — Cancel + Undo on the left, Resume (mic) then Paste on the right — and updated hints:

```swift
            HStack(spacing: 8) {
                ReviewKeyButton(
                    title: "Cancel",
                    hint: "esc",
                    emphasis: .secondary
                ) { state.onCancel?() }

                if !state.actionRevertStack.isEmpty, state.runningActionId == nil {
                    ReviewKeyButton(
                        title: "Undo",
                        systemImage: "arrow.uturn.backward",
                        hint: nil,
                        emphasis: .secondary
                    ) { state.undoLastAction() }
                    .help("Undo last action")
                }

                Spacer()

                ReviewKeyButton(
                    title: "Resume",
                    systemImage: "mic.fill",
                    hint: HotkeyStore.shared.binding.displayKeys.joined(),
                    emphasis: .secondary
                ) { state.onResume?() }

                ReviewKeyButton(
                    title: "Paste",
                    hint: Self.pasteHint,
                    emphasis: .primary
                ) { state.onPaste?() }
            }
```

Add the hint helper as a static on `ReviewView`:

```swift
    /// "↩" when Return sends; the configured send shortcut when Return is
    /// remapped to newline.
    static var pasteHint: String {
        let store = HotkeyStore.shared
        return store.sendOnReturn ? "↩" : store.sendShortcut.displayKeys.joined()
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `cd VoiceToText && xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug -derivedDataPath build-dev build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add VoiceToText/VoiceToText/UI/LiveHUD.swift
git commit -m "feat(hud): in-form re-record strip and button re-layout"
```

---

## Task 5: DictationController — wire re-record, append-at-end, send/newline

**Files:**
- Modify: `VoiceToText/VoiceToText/Dictation/DictationController.swift`

Validated by build + manual checklist (Task 8).

- [ ] **Step 1: Handle the new hotkey action**

In `performHotkeyAction` (line 255), add a case alongside `.confirmPaste`:

```swift
        case .resumeRecording:
            resumeRecording()
```

- [ ] **Step 2: Append at end instead of splicing at the caret**

In `resumeRecording()` (line 1057-1062), build the resume context pinned to the end of the text so the next take appends after a smart space (the existing `ResumeContext.splicing` already adds a single separating space and an empty suffix means nothing trails):

```swift
        let fullText = LiveHUDPanel.shared.currentReviewText
        let context = ResumeContext(
            fullText: fullText,
            cursorLocation: (fullText as NSString).length
        )
```

Apply the same change in `retryFailedResumeTranscription()` (line 770-773):

```swift
        let retryText = LiveHUDPanel.shared.currentReviewText
        resumeContext = ResumeContext(
            fullText: retryText,
            cursorLocation: (retryText as NSString).length
        )
```

- [ ] **Step 3: Keep the form visible during a re-record take (recording phase)**

In `startRecording(...)`, replace the single `LiveHUDPanel.shared.show(...)` call (line 616) with a branch that, when this cycle is a resume, drives the in-form strip instead of switching panels:

```swift
            if resumeContext != nil {
                LiveHUDState.shared.levelHistory = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
                LiveHUDState.shared.elapsedSeconds = 0
                LiveHUDState.shared.reviewTakePhase = .recording
            } else {
                LiveHUDPanel.shared.show(showsLiveText: streamingEngine != nil)
            }
```

- [ ] **Step 4: Keep the form visible during a re-record take (transcribing phase)**

In `enterTranscribing()` (line 650), replace the unconditional `LiveHUDPanel.shared.showTranscribing()` (line 658) with:

```swift
        if resumeContext != nil {
            LiveHUDState.shared.reviewTakePhase = .transcribing
        } else {
            LiveHUDPanel.shared.showTranscribing()
        }
```

(`state = .transcribing` above it is unchanged — the take must still block re-entrant hotkey presses while transcribing.)

- [ ] **Step 5: Remove ⌘R; add send/newline handling to the review monitor**

In `installReviewEscMonitor()` (line 477), delete the ⌘R block (lines 485-490). After the Esc block and before the ⌘1–⌘9 block, add Return/send handling driven by `ReviewKeyPolicy`:

```swift
            let store = HotkeyStore.shared
            let isReturn = event.keyCode == UInt16(kVK_Return)
                || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
            let hasShift = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift
            let matchesSendShortcut = HotkeyBinding.fromEvent(event) == store.sendShortcut
            switch ReviewKeyPolicy.decision(
                sendOnReturn: store.sendOnReturn,
                isReturn: isReturn,
                hasShift: hasShift,
                matchesSendShortcut: matchesSendShortcut
            ) {
            case .send:
                Task { @MainActor in self?.confirmPaste() }
                return nil
            case .newline:
                return event
            case .ignore:
                break
            }
```

Note: `hasShift` compares the exact device-independent modifier set so a plain `Return` (no modifiers) is *not* treated as Shift+Return, and Shift+Return passes through to the editor as a newline.

- [ ] **Step 6: Build to verify it compiles**

Run: `cd VoiceToText && xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug -derivedDataPath build-dev build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add VoiceToText/VoiceToText/Dictation/DictationController.swift
git commit -m "feat(dictation): in-form re-record, append-at-end, Return-to-send"
```

---

## Task 6: Settings — newline toggle + Send shortcut capture

**Files:**
- Modify: `VoiceToText/VoiceToText/Settings/SettingsView.swift:348-490`

Validated by build + manual checklist (Task 8).

- [ ] **Step 1: Add the newline toggle and Send capture state to `HotkeyPane`**

`HotkeyPane` already has `@Bindable private var store = HotkeyStore.shared`. Add capture state next to the existing `@State` fields (line 350-353):

```swift
    @State private var isCapturingSend = false
    @State private var sendMonitor: Any?
    @State private var sendCaptureSession = HotkeyCaptureSession()
    @State private var sendErrorMessage: String?
```

- [ ] **Step 2: Add the two cards to the layout**

In `HotkeyPane.body`, after the "Recording mode" `RowCard` (closes at line 416) and before the `if let errorMessage` block, insert:

```swift
                RowCard {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Newline on Enter")
                                .font(.system(size: 14, weight: .medium))
                            Text("Off: Return sends, Shift+Return adds a line. On: Return adds a line and a shortcut sends.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !store.sendOnReturn },
                            set: { store.updateSendOnReturn(to: !$0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(18)
                }

                if !store.sendOnReturn {
                    RowCard {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Send shortcut")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Sends the reviewed text. Needs a modifier (e.g. Cmd+Return).")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isCapturingSend {
                                Text("Press a shortcut…")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    )
                            } else {
                                KeyCap(keys: store.sendShortcut.displayKeys)
                            }
                            Button(isCapturingSend ? "Cancel" : "Change") {
                                if isCapturingSend { stopSendCapture(cancelled: true) } else { startSendCapture() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(18)
                    }

                    if let sendErrorMessage {
                        Text(sendErrorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
```

- [ ] **Step 3: Add the Send capture handlers**

Add these methods to `HotkeyPane` (next to `startRecording`/`stopRecording`, around line 456-489). They reuse `HotkeyCaptureSession`, which already requires a modifier/function key — satisfying "Send needs a modifier":

```swift
    private func startSendCapture() {
        sendErrorMessage = nil
        sendCaptureSession.reset()
        isCapturingSend = true
        sendMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch sendCaptureSession.handle(event: event) {
            case .ignored, .pendingStandaloneModifier:
                break
            case .cancelled:
                stopSendCapture(cancelled: true)
            case .captured(let candidate):
                sendErrorMessage = nil
                store.updateSendShortcut(to: candidate)
                stopSendCapture(cancelled: false)
            case .rejected:
                sendErrorMessage = "Add at least one modifier (⌘ ⌥ ⌃ ⇧) — e.g. Cmd+Return."
            }
            return nil
        }
    }

    private func stopSendCapture(cancelled: Bool) {
        isCapturingSend = false
        sendCaptureSession.reset()
        if let m = sendMonitor {
            NSEvent.removeMonitor(m)
            sendMonitor = nil
        }
        if cancelled { sendErrorMessage = nil }
    }
```

Also stop the Send capture on disappear: change `.onDisappear { stopRecording(cancelled: true) }` (line 437) to:

```swift
        .onDisappear {
            stopRecording(cancelled: true)
            stopSendCapture(cancelled: true)
        }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cd VoiceToText && xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug -derivedDataPath build-dev build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add VoiceToText/VoiceToText/Settings/SettingsView.swift
git commit -m "feat(settings): newline toggle and send shortcut capture UI"
```

---

## Task 7: Update the review preview mock

**Files:**
- Modify: `VoiceToText/VoiceToText/Settings/ReviewBeforePasteCard.swift:41-70`

- [ ] **Step 1: Mirror the new layout and hints in the static mock**

`ReviewBeforePasteCard` currently passes `pasteHint: hotkeyStore.binding.displayKeys.joined()` into `ReviewHUDPreview`. Change the call site (line 28-31) to pass the same hints the live form now uses:

```swift
                ReviewHUDPreview(
                    resumeHint: hotkeyStore.binding.displayKeys.joined(),
                    pasteHint: hotkeyStore.sendOnReturn ? "↩" : hotkeyStore.sendShortcut.displayKeys.joined(),
                    isEnabled: reviewBeforePaste
                )
```

Update `ReviewHUDPreview` to take both hints and reorder the chips to match the live form (Cancel left; Resume then Paste right):

```swift
private struct ReviewHUDPreview: View {
    let resumeHint: String
    let pasteHint: String
    let isEnabled: Bool

    private static let sampleTranscript = "Let's ship the build before lunch, and circle back on the API rename tomorrow."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.sampleTranscript)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                ReviewKeyChip(label: "Cancel", hint: "esc", emphasis: .ghost)
                Spacer()
                ReviewKeyChip(label: "Resume", systemImage: "mic.fill", hint: resumeHint, emphasis: .ghost)
                ReviewKeyChip(label: "Paste", hint: pasteHint, emphasis: .primary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.11))
        )
        .opacity(isEnabled ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd VoiceToText && xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug -derivedDataPath build-dev build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add VoiceToText/VoiceToText/Settings/ReviewBeforePasteCard.swift
git commit -m "feat(settings): update review preview mock to match new form"
```

---

## Task 8: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full harness suite**

Run: `bash Tests/run-hotkey-harnesses.sh`
Expected: every harness prints its `… passed` line and the script exits 0.

- [ ] **Step 2: Build the app once more**

Run: `cd VoiceToText && xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug -derivedDataPath build-dev build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual smoke test** (run the dev build via `scripts/dev.sh` with the user's signing identity, or launch from Xcode)

Verify, with "Review before pasting" ON (default):
  - Press the recording shortcut → record → press again → review form appears.
  - Press the recording shortcut again → form stays visible, a compact waveform shows under the text and above the buttons; press again → "Transcribing" shimmer in the same strip → new text is appended to the end after a space.
  - `Esc` during a re-record take → take is dropped, prior text intact.
  - `Return` in the form → text is sent/pasted into the focused app.
  - `Shift+Return` → inserts a newline, does not send.
  - Button row reads: Cancel (left), Resume+Paste (right); Paste hint is `↩`.
  - `⌘R` does nothing (removed).

Verify with "Review before pasting" OFF:
  - Record → stop → text is pasted immediately (no form).

Verify Settings → Shortcut:
  - Toggle "Newline on Enter" ON → a "Send shortcut" row appears showing `⌘Return`; Paste hint in the preview switches to `⌘Return`.
  - In the live form (newline mode): `Return` inserts a newline; `⌘Return` sends.
  - Change the Send shortcut to another combo (e.g. ⌘D) → that combo now sends in the form.

- [ ] **Step 4: Final commit (if any manual-test fixups were needed)**

```bash
git add -A
git commit -m "fix(review): manual-test adjustments for re-record flow"
```

(Skip if no fixups were required.)

---

## Self-Review Notes

- **Spec coverage:** §1 policy → Task 1; §2 in-form take → Tasks 4 (UI) + 5 (controller); §3 send/newline → Tasks 2 (policy) + 5 (monitor); §4 settings → Tasks 3 (store) + 6 (UI); §5 layout/hints → Tasks 4, 6, 7. All covered.
- **Type consistency:** `ReviewKeyDecision`/`ReviewKeyPolicy.decision(sendOnReturn:isReturn:hasShift:matchesSendShortcut:)`, `HotkeyStore.sendOnReturn`/`sendShortcut`/`updateSendOnReturn(to:)`/`updateSendShortcut(to:)`, `HotkeyBinding.commandReturnBinding`, `LiveHUDState.reviewTakePhase`/`ReviewTakePhase`, `ReviewView.pasteHint` are referenced consistently across tasks.
- **Append semantics:** reuse `ResumeContext.splicing` with `cursorLocation` pinned to text end — no new untested code path; matches "append after a space".
</content>
