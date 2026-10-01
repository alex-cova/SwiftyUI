import Foundation

/// Live editor snapshot, keyed to the file it was captured from. Class so
/// `textViewDidChange` can write it without a SwiftUI invalidation (the `@State source`
/// binding still drives the preview parse) — `@State source` lags one turn (and can miss
/// a write while `setState` is applying), so New Tab / persist must read this, not `source`.
///
/// The owner id guards against a keystroke echoed *after* the user has already switched
/// tabs: without it, that trailing write would land in the newly selected file instead of
/// the one it actually came from. See `MockupTool.swift`'s `.id(editorIdentity)`, which
/// tears down the editor (and so its capture of the owning id) on every file switch.
@MainActor
public final class MockupLiveSource {
    public private(set) var screenID: UUID?
    public private(set) var text: String

    public init(screenID: UUID? = nil, text: String) {
        self.screenID = screenID
        self.text = text
    }

    /// Whole-buffer replacement from outside (Sample, Clear, tab switch, file drop, handoff).
    public func reset(id: UUID?, text: String) {
        screenID = id
        self.text = text
    }

    /// Ignores a write from an editor that no longer owns the selection — a keystroke
    /// echoed after the user switched tabs must not be saved into the new file.
    public func record(id: UUID?, text: String) {
        guard id == screenID else { return }
        self.text = text
    }
}
