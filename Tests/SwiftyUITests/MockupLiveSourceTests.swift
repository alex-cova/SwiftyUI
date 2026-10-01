import Foundation
import Testing
@testable import SwiftyUI

@MainActor
struct MockupLiveSourceTests {
    @Test func recordAcceptsAWriteFromTheOwningFile() {
        let id = UUID()
        let source = MockupLiveSource(screenID: id, text: "before")
        source.record(id: id, text: "after")
        #expect(source.text == "after")
        #expect(source.screenID == id)
    }

    @Test func recordIgnoresAWriteFromAFileThatNoLongerOwnsTheSelection() {
        // A keystroke's echo lands (via `DispatchQueue.main.async`) after the user has
        // already switched tabs. Without the owner check, this write would land in the
        // newly selected file instead of the one the keystroke actually came from.
        let previousFile = UUID()
        let newFile = UUID()
        let source = MockupLiveSource(screenID: previousFile, text: "typed in the old file")
        source.reset(id: newFile, text: "the new file's own source")
        source.record(id: previousFile, text: "a trailing echo from the old file")
        #expect(source.text == "the new file's own source")
        #expect(source.screenID == newFile)
    }

    @Test func resetAlwaysTakesTheNewOwnerRegardlessOfWhatItWas() {
        let source = MockupLiveSource(screenID: nil, text: "")
        let id = UUID()
        source.reset(id: id, text: "sample content")
        #expect(source.text == "sample content")
        #expect(source.screenID == id)
    }
}
