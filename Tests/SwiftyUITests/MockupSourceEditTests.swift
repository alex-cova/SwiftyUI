import Foundation
import Testing
@testable import SwiftyUI

struct MockupSourceEditTests {
    @Test func emptySourceTakesTheSnippetAsIs() {
        let result = MockupSourceEdit.insert("Text(\"Hi\")", into: "  \n", atUTF16Offset: 0)
        #expect(result.source == "Text(\"Hi\")")
        #expect(result.caretUTF16Offset == (result.source as NSString).length)
    }

    @Test func negativeOffsetAppendsAtTheEnd() {
        let result = MockupSourceEdit.insert("Text(\"B\")", into: "Text(\"A\")", atUTF16Offset: -1)
        #expect(result.source == "Text(\"A\")\n\nText(\"B\")")
        #expect(result.caretUTF16Offset == (result.source as NSString).length)
    }

    @Test func insertAtCaretSplitsTheBufferWithBlankLines() {
        let source = "Text(\"A\")\nText(\"C\")"
        let caret = ("Text(\"A\")" as NSString).length
        let result = MockupSourceEdit.insert("Text(\"B\")", into: source, atUTF16Offset: caret)
        #expect(result.source == "Text(\"A\")\n\nText(\"B\")\n\nText(\"C\")")
        let expectedCaret = ("Text(\"A\")\n\nText(\"B\")" as NSString).length
        #expect(result.caretUTF16Offset == expectedCaret)
    }

    @Test func insertDoesNotStackExtraNewlinesWhenAGapAlreadyExists() {
        let source = "Text(\"A\")\n\n"
        let result = MockupSourceEdit.insert("Text(\"B\")", into: source, atUTF16Offset: (source as NSString).length)
        #expect(result.source == "Text(\"A\")\n\nText(\"B\")")
    }

    @Test func emptySnippetIsANoOp() {
        let source = "Text(\"A\")"
        let result = MockupSourceEdit.insert("  ", into: source, atUTF16Offset: 2)
        #expect(result.source == source)
        #expect(result.caretUTF16Offset == 2)
    }
}
