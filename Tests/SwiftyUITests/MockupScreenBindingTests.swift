import Foundation
import Testing
@testable import SwiftyUI

struct MockupScreenBindingTests {
    @Test func persistTargetsThePendingInsertWhenQueryHasNotCaughtUp() {
        let original = UUID()
        let created = UUID()
        let visible = [original]
        #expect(
            MockupScreenBinding.persistID(
                selectedID: created,
                visibleIDs: visible,
                pendingID: created
            ) == created
        )
        #expect(
            MockupScreenBinding.activeID(
                selectedID: created,
                visibleIDs: visible,
                pendingID: created
            ) == created
        )
    }

    @Test func persistDoesNotFallBackToAnotherFile() {
        let original = UUID()
        let created = UUID()
        // This is the New Tab race: selection already points at the insert, @Query still
        // lists only the previous file, and there is no pending handle. Writing through
        // `screens.first` would replace the pasted buffer with the blank template.
        #expect(
            MockupScreenBinding.persistID(
                selectedID: created,
                visibleIDs: [original],
                pendingID: nil
            ) == nil
        )
        #expect(
            MockupScreenBinding.activeID(
                selectedID: created,
                visibleIDs: [original],
                pendingID: nil
            ) == original
        )
    }

    @Test func persistFollowsAVisibleSelection() {
        let first = UUID()
        let second = UUID()
        #expect(
            MockupScreenBinding.persistID(
                selectedID: second,
                visibleIDs: [first, second],
                pendingID: nil
            ) == second
        )
    }

    @Test func activeFallsBackToTheFirstVisibleFileWhenSelectionIsGone() {
        let remaining = UUID()
        #expect(
            MockupScreenBinding.activeID(
                selectedID: UUID(),
                visibleIDs: [remaining],
                pendingID: nil
            ) == remaining
        )
        #expect(
            MockupScreenBinding.activeID(
                selectedID: nil,
                visibleIDs: [remaining],
                pendingID: nil
            ) == remaining
        )
    }

    @Test func persistIsNilWhenNothingIsSelected() {
        #expect(
            MockupScreenBinding.persistID(
                selectedID: nil,
                visibleIDs: [UUID()],
                pendingID: nil
            ) == nil
        )
    }
}
