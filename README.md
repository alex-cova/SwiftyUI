# SwiftyUI

A macOS library that turns a SwiftUI-flavored source buffer into a live view.

Nothing is compiled or executed. `SwiftParser` builds an error-tolerant syntax tree, the lowering walks a whitelisted subset (stacks, lists, controls, modifiers, `if`, `ForEach`, navigation), and `MockNodeView` draws the resulting `MockNode` tree with real SwiftUI.

Hextech's Mockup tool is the editor and persistence shell. This package is the renderer.
