import Foundation

/// Resolves which mockup file the editor is bound to.
///
/// `@Query` snapshots lag one turn behind `ModelContext.insert`, so a freshly created tab's
/// UUID is already selected while the visible array still lists only the previous files.
/// Persisting through "selected or else first" in that window overwrites the file the user
/// was just editing (paste, sample, anything) with the new tab's blank template.
public nonisolated enum MockupScreenBinding {
    /// File the editor should read and display. Falls back to the first visible file when the
    /// stored selection is gone (deleted out from under us).
    public static func activeID(
        selectedID: UUID?,
        visibleIDs: [UUID],
        pendingID: UUID?
    ) -> UUID? {
        if let selectedID {
            if visibleIDs.contains(selectedID) { return selectedID }
            if pendingID == selectedID { return selectedID }
        }
        return visibleIDs.first
    }

    /// File the editor may write into. `nil` means "do not persist" — never fall back to
    /// another file, which is what deleted a just-pasted buffer on New Tab.
    public static func persistID(
        selectedID: UUID?,
        visibleIDs: [UUID],
        pendingID: UUID?
    ) -> UUID? {
        guard let selectedID else { return nil }
        if visibleIDs.contains(selectedID) { return selectedID }
        if pendingID == selectedID { return selectedID }
        return nil
    }
}
