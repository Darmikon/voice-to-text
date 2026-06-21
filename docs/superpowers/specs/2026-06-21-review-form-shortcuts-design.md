# Review-form shortcuts & re-record flow — design

Date: 2026-06-21
Branch: `feat/review-form-shortcuts`

## Problem

The recording shortcut and the review (preview-before-paste) form behave
inconsistently:

- Pressing the recording shortcut while the review form is open **pastes**
  (`confirmPaste`) instead of letting the user dictate more.
- Re-recording from the form is bound to **⌘R**, which is unintuitive
  ("absurd").
- There is **no way to send via Return** — Return only inserts a newline in
  the NSTextView. Sending requires the recording shortcut or a button click.

## Goals

1. The recording shortcut drives the whole loop: start → stop (→ send if no
   review) → in review, press again to re-record → stop → re-transcribe.
2. Send the reviewed text with **Return**; insert a newline with
   **Shift+Return** (messenger convention).
3. A settings toggle flips this: **Enter inserts a newline**, and sending moves
   to a user-assignable shortcut (default **⌘Return**).
4. Re-recording keeps the form visible with a compact waveform; the new
   transcript is appended to the end of the existing text.
5. Remove ⌘R. Re-layout the form's buttons.

## Non-goals

- Failure HUD shortcuts (Return = retry / Esc = dismiss) — unchanged.
- AI action shortcuts ⌘1–⌘9 — unchanged.
- Hold-to-record mode keeps working; re-record is the same press gesture, so
  it stays consistent.
- Streaming engines (ElevenLabs) — no behavior change.

## Design

### 1. Hotkey state policy (`Hotkey/HotkeyActionPolicy.swift`)

Add a `resumeRecording` case to `DictationHotkeyAction`. Change the
`.reviewing` mapping in both `holdAction` and `toggleAction` from
`.confirmPaste` to `.resumeRecording`.

| State | Shortcut press |
|---|---|
| `idle` / `error` | `startRecording` |
| `recording` | `stopAndTranscribe` |
| `reviewing` | `resumeRecording` (new) |
| `preparing` / `transcribing` | `none` |

`DictationController.performHotkeyAction` handles `.resumeRecording` by calling
the existing `resumeRecording()` entry point (adapted below). `.confirmPaste`
stays in the enum but is now triggered only by the in-form Send (Return /
configured shortcut), not by the global hotkey.

When `review.beforePaste` is off, `recording → stopAndTranscribe` still
delivers the text immediately (unchanged path in
`runTranscriptionPipeline`).

### 2. In-form re-record ("review take")

Today `resumeRecording()` → `startRecording()` → `LiveHUDPanel.show()`, which
hides the review panel and shows the large recording HUD. New behavior keeps
the review panel up.

**State:** add to `LiveHUDState`

```
enum ReviewTakePhase { case none, recording, transcribing }
var reviewTakePhase: ReviewTakePhase = .none
```

**Controller:** track `isReviewTake: Bool`. While true:

- `startRecording` skips `LiveHUDPanel.show()`; instead sets
  `reviewTakePhase = .recording` and keeps the review panel key. Mic level
  already streams into `state.levelHistory` via `recorder.onLevel` /
  `setLevel`, so the compact waveform is fed for free.
- `enterTranscribing` skips `LiveHUDPanel.showTranscribing()`; sets
  `reviewTakePhase = .transcribing` and keeps the panel.
- On success, the processed transcript is **appended to the end** of the
  current form text with a single separating space (reuse the existing
  `needsSpace` whitespace logic so spaces aren't doubled), `reviewTakePhase`
  returns to `.none`, and the form re-renders with the longer text. Caret goes
  to end.
- **Esc** during a review take cancels only that take and restores the form
  with its prior text (existing recording-Esc → `finishRecordingSession` path,
  adapted to clear `reviewTakePhase` and not switch panels).

The caret-splice `ResumeContext` is simplified to append-at-end semantics
(cursor pinned to end of the current text). The failed-resume retry path
(`retryFailedResumeTranscription`) follows the same append semantics.

**View (`UI/LiveHUD.swift` `ReviewView`):** between the text editor and the
button row, when `reviewTakePhase != .none`, show a compact strip:

- `.recording`: a small `LevelBars` (~28 px tall) fed by `state.levelHistory`,
  an elapsed timer, and the hint "Press `<recording shortcut>` to finish ·
  Esc cancels".
- `.transcribing`: a slim "Transcribing…" shimmer in the same slot.

The review panel grows by the strip height while a take is active.

### 3. Send / newline in the form

Newline behavior is configured by a new setting (see §4). Handling lives in the
existing review key monitor (`installReviewEscMonitor` in
`DictationController`), which already runs before the NSTextView and can consume
or pass events:

**Default mode (`sendOnReturn = true`):**
- `Return` (no Shift) → consume, Send.
- `Shift+Return` → pass through → NSTextView inserts a newline.

**Newline mode (`sendOnReturn = false`):**
- `Return` → pass through → newline.
- The configured Send shortcut (default ⌘Return) → consume, Send.

"Send" calls `confirmPaste()`. Esc and ⌘1–⌘9 handling in the monitor is
unchanged. ⌘R handling is removed.

### 4. Settings (`Settings/SettingsView.swift` `HotkeyPane` + `HotkeyStore`)

Extend `HotkeyStore` with:

- `sendOnReturn: Bool` (default `true`) — persisted under a new UserDefaults
  key (e.g. `review.sendOnReturn.v1`).
- `sendShortcut: HotkeyBinding` (default ⌘Return) — persisted under
  `review.sendShortcut.v1`.

Add two cards to `HotkeyPane`:

- Toggle **"Newline on Enter"** bound to `sendOnReturn`.
- When the toggle is on, a shortcut-capture row **"Send"** reusing
  `HotkeyCaptureSession` + `HotkeyBinding` (same Change/Cancel/KeyCap pattern
  as the recording-shortcut card). Capture requires a modifier, which ⌘Return
  satisfies.

### 5. Button layout & hints (`UI/LiveHUD.swift`, `Settings/ReviewBeforePasteCard.swift`)

New bottom row order:

- **Left:** `Cancel` (hint `esc`); `Undo` next to it when the revert stack is
  non-empty.
- **Spacer**
- **Right:** `Resume` mic button (hint = current recording shortcut display),
  then `Paste` (hint = `↩` in default mode, or the configured Send shortcut in
  newline mode).

Remove the `⌘R` hint from Resume. Update the static mock in
`ReviewBeforePasteCard.swift` to mirror the new order and hints.

## Affected files

- `Hotkey/HotkeyActionPolicy.swift` — new action + reviewing mapping.
- `Hotkey/HotkeyBinding.swift` (`HotkeyStore`) — new settings + persistence.
- `Dictation/DictationController.swift` — resume → in-form take, append
  semantics, send/newline monitor, remove ⌘R.
- `UI/LiveHUD.swift` — `ReviewTakePhase`, compact waveform strip, button
  re-layout, hints.
- `Settings/SettingsView.swift` — newline toggle + Send capture cards.
- `Settings/ReviewBeforePasteCard.swift` — updated preview mock.

## Testing

- Unit: extend `Tests/` policy coverage so `.reviewing + pressed →
  resumeRecording` in both modes; existing `HotkeyStoreHarness` covers the new
  persisted settings round-trip.
- Manual: full loop with review on (record → form → re-record appends →
  Return sends), Shift+Return newline, toggle newline-mode (Return newlines,
  ⌘Return sends), Esc during a take restores text, review off still pastes
  immediately, button layout/hints correct.
</content>
</invoke>
