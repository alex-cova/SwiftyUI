import Foundation
import Testing
@testable import SwiftyUI

/// Structural assertions over `MockupEngine.parse` — the lowering is the tested unit; the
/// renderer is a view and stays untested per the project convention.
struct MockupEngineTests {

    // MARK: - Helpers

    private func root(_ source: String) -> MockNode {
        let parsed = MockupEngine.parse(source)
        return try! #require(parsed.root)
    }

    // MARK: - Blocks

    @Test func emptySourceProducesNoRoot() {
        let parsed = MockupEngine.parse("   \n  ")
        #expect(parsed.root == nil)
        #expect(parsed.nodeCount == 0)
    }

    @Test func singleStatementIsTheRootDirectly() {
        let node = root(#"Text("Hi")"#)
        #expect(node.kind == .text("Hi"))
    }

    @Test func multipleTopLevelStatementsWrapInImplicitVStack() {
        let node = root(#"""
        Text("One")
        Text("Two")
        """#)
        guard case let .vstack(_, _, children) = node.kind else {
            Issue.record("expected implicit VStack, got \(node.kind)")
            return
        }
        #expect(children.count == 2)
        #expect(children[0].kind == .text("One"))
    }

    @Test func pullsBodyOutOfAFullViewStruct() {
        let node = root(#"""
        struct ContentView: View {
            var body: some View {
                HStack {
                    Text("Left")
                    Text("Right")
                }
            }
        }
        """#)
        guard case let .hstack(_, _, children) = node.kind else {
            Issue.record("expected HStack, got \(node.kind)")
            return
        }
        #expect(children.count == 2)
    }

    // MARK: - Containers & args

    @Test func stackAlignmentAndSpacingAreCaptured() {
        let node = root(#"""
        VStack(alignment: .leading, spacing: 12) {
            Text("A")
        }
        """#)
        guard case let .vstack(alignment, spacing, _) = node.kind else {
            Issue.record("expected VStack")
            return
        }
        #expect(alignment == .token("leading"))
        #expect(spacing == 12)
    }

    @Test func sectionHeaderStringIsCaptured() {
        let node = root(#"""
        List {
            Section("Account") {
                Text("Apple ID")
            }
        }
        """#)
        guard case let .list(children) = node.kind,
              case let .section(header, _) = children.first?.kind else {
            Issue.record("expected List > Section")
            return
        }
        #expect(header == "Account")
    }

    @Test func formLowersLikeListWithSeededControls() {
        let node = root(#"""
        Form {
            TextField("Name", text: .constant("Ada"))
            Toggle("Public", isOn: .constant(true))
        }
        """#)
        guard case let .form(children) = node.kind else {
            Issue.record("expected Form, got \(node.kind)")
            return
        }
        #expect(children.count == 2)
        #expect(children[0].kind == .textField(placeholder: "Name", initialText: "Ada", editable: false))
        #expect(children[1].kind == .toggle(title: "Public", initialOn: true, editable: false))
    }

    // MARK: - Leaves

    @Test func imageSystemNameLowersToSystemSource() {
        let node = root(#"Image(systemName: "star.fill")"#)
        #expect(node.kind == .image(.system("star.fill")))
    }

    @Test func bareImageStringLowersToAssetSource() {
        let node = root(#"Image("logo")"#)
        #expect(node.kind == .image(.asset("logo")))
    }

    @Test func unknownAssetNameNotesAMissingImageWhenLibraryIsKnown() {
        let parsed = MockupEngine.parse(#"Image("logo")"#, assetNames: ["hero"])
        #expect(parsed.diagnostics.contains { $0.severity == .info && $0.message.contains("logo") })
        #expect(parsed.root == .leaf(.image(.asset("logo"))))
    }

    @Test func knownAssetNameRaisesNoDiagnostic() {
        let parsed = MockupEngine.parse(#"Image("logo")"#, assetNames: ["logo", "hero"])
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test func emptyAssetLibraryRaisesNoDiagnostic() {
        // An empty `assetNames` means "don't know the library yet" (e.g. before the first
        // `@Query` snapshot arrives), not "the library is empty" — don't flag every name.
        let parsed = MockupEngine.parse(#"Image("logo")"#)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test func imageResizableAndAspectRatioApply() {
        // The lowering only resolves literal arithmetic, not expressions — `1.5`, not `3.0 / 2.0`.
        let node = root(#"Image("logo").resizable().aspectRatio(1.5, contentMode: .fill).clipped()"#)
        #expect(node.modifiers.contains(.resizable))
        #expect(node.modifiers.contains(.aspectRatio(ratio: 1.5, contentMode: .fill)))
        #expect(node.modifiers.contains(.clipped))
    }

    @Test func scaledToFitAppliesAsAspectRatio() {
        let node = root(#"Image("logo").scaledToFit()"#)
        #expect(node.modifiers.contains(.aspectRatio(ratio: nil, contentMode: .fit)))
    }

    @Test func labelCapturesTitleAndSymbol() {
        let node = root(#"Label("Follow", systemImage: "plus")"#)
        #expect(node.kind == .label(title: "Follow", systemImage: "plus"))
    }

    @Test func roundedRectangleDefaultsCornerRadiusWhenAbsent() {
        let node = root("RoundedRectangle()")
        #expect(node.kind == .shape(.roundedRectangle(cornerRadius: 8)))
    }

    // MARK: - Modifiers

    @Test func modifierChainLandsOnTheNode() {
        let node = root(#"Text("Hi").padding(16).opacity(0.5)"#)
        #expect(node.kind == .text("Hi"))
        #expect(node.modifiers.contains(.padding(edges: nil, length: 16)))
        #expect(node.modifiers.contains(.opacity(0.5)))
    }

    @Test func paddingWithoutArgumentsIsTheSystemDefault() {
        let node = root(#"Text("Hi").padding()"#)
        #expect(node.modifiers == [.padding(edges: nil, length: nil)])
    }

    @Test func paddingWithEdgeAndLength() {
        let node = root(#"Text("Hi").padding(.horizontal, 20)"#)
        #expect(node.modifiers == [.padding(edges: .token("horizontal"), length: 20)])
    }

    @Test func frameFlexibleOverloadParsesMaxWidthInfinity() {
        let node = root(#"Text("Hi").frame(maxWidth: .infinity, alignment: .leading)"#)
        guard case let .frame(frame) = node.modifiers.first else {
            Issue.record("expected a frame modifier")
            return
        }
        #expect(frame.maxWidth == .infinity)
        #expect(frame.alignment == .token("leading"))
    }

    @Test func fontSystemSizeAndWeightAreCaptured() {
        let node = root(#"Text("Hi").font(.system(size: 40, weight: .bold))"#)
        #expect(node.modifiers == [.font(.systemFont(size: 40, weight: "bold"))])
    }

    @Test func cornerRadiusModifierIsCaptured() {
        let node = root(#"Color.blue.cornerRadius(14)"#)
        #expect(node.kind == .color(.token("blue")))
        #expect(node.modifiers == [.cornerRadius(14)])
    }

    @Test func backgroundWithShapeArgumentBecomesAChildNode() {
        let node = root(#"Text("Hi").background(RoundedRectangle(cornerRadius: 10))"#)
        #expect(node.modifiers == [.background(MockNode(kind: .shape(.roundedRectangle(cornerRadius: 10))))])
    }

    @Test func knownNoOpModifiersAreAcceptedSilently() {
        // `buttonStyle` used to be one of these — it now genuinely changes rendering (including
        // Liquid Glass styles), so it moved to the applied side; `disabled` stays a true no-op.
        let parsed = MockupEngine.parse(#"Text("Hi").disabled(true).accessibilityLabel("hi")"#)
        #expect(parsed.root?.modifiers.isEmpty == true)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test func unknownModifierIsReportedButDoesNotBreakTheNode() {
        let parsed = MockupEngine.parse(#"Text("Hi").rotation3DEffect(.degrees(45))"#)
        #expect(parsed.root?.kind == .text("Hi"))
        #expect(parsed.diagnostics.contains { $0.message.contains("rotation3DEffect") })
    }

    // MARK: - Control flow

    @Test func forEachOverHalfOpenRangeCountsElements() {
        let node = root(#"""
        ForEach(0..<3) {
            Text("Row")
        }
        """#)
        #expect(node.kind == .forEach(count: 3, child: MockNode(kind: .text("Row"))))
    }

    @Test func forEachOverClosedRangeCountsInclusively() {
        let node = root(#"""
        ForEach(1...4) { Text("Row") }
        """#)
        guard case let .forEach(count, _) = node.kind else {
            Issue.record("expected ForEach")
            return
        }
        #expect(count == 4)
    }

    @Test func forEachCountIsClampedToACeiling() {
        let node = root(#"ForEach(0..<100000) { Divider() }"#)
        guard case let .forEach(count, _) = node.kind else {
            Issue.record("expected ForEach")
            return
        }
        #expect(count == 200)
    }

    @Test func singleBranchIfBecomesAConditionalNode() {
        let node = root(#"""
        if isLoggedIn {
            Text("Welcome")
        }
        """#)
        #expect(node.kind == .conditional(
            then: MockNode(kind: .text("Welcome")),
            elseBranch: nil,
            known: nil
        ))
    }

    @Test func unfoldableIfIsFlaggedForTheBranchToggle() {
        let parsed = MockupEngine.parse(#"""
        if isLoggedIn {
            Text("Welcome")
        }
        """#)
        #expect(parsed.hasUnresolvedConditional)
    }

    @Test func elseBranchIsCapturedNotDropped() {
        let node = root(#"""
        if flag {
            Text("A")
        } else {
            Text("B")
        }
        """#)
        #expect(node.kind == .conditional(
            then: MockNode(kind: .text("A")),
            elseBranch: MockNode(kind: .text("B")),
            known: nil
        ))
    }

    @Test func elseIfChainNestsAsAConditionalInTheElseBranch() {
        let node = root(#"""
        if a {
            Text("A")
        } else if b {
            Text("B")
        } else {
            Text("C")
        }
        """#)
        guard case let .conditional(_, elseBranch, _) = node.kind else {
            Issue.record("expected conditional")
            return
        }
        guard case .conditional = elseBranch?.kind else {
            Issue.record("expected nested conditional in else branch")
            return
        }
    }

    @Test func constantTrueConditionFoldsToTheThenBranch() {
        let node = root(#"""
        if true {
            Text("Shown")
        } else {
            Text("Hidden")
        }
        """#)
        #expect(node.kind == .conditional(
            then: MockNode(kind: .text("Shown")),
            elseBranch: MockNode(kind: .text("Hidden")),
            known: true
        ))
    }

    @Test func constantFalseConditionFoldsToTheElseBranch() {
        let parsed = MockupEngine.parse(#"""
        if 1 > 2 {
            Text("Shown")
        } else {
            Text("Hidden")
        }
        """#)
        guard case let .conditional(_, _, known) = parsed.root?.kind else {
            Issue.record("expected conditional")
            return
        }
        #expect(known == false)
        #expect(!parsed.hasUnresolvedConditional)
    }

    @Test func stateBoolResolvesTheCondition() {
        let parsed = MockupEngine.parse(#"""
        struct V: View {
            @State private var isOn = false
            var body: some View {
                if isOn { Text("On") } else { Text("Off") }
            }
        }
        """#)
        guard case let .conditional(_, _, known) = parsed.root?.kind else {
            Issue.record("expected conditional")
            return
        }
        #expect(known == false)
    }

    // MARK: - State bindings

    @Test func textFieldSeedsInitialValueFromResolvedState() {
        let parsed = MockupEngine.parse(#"""
        struct V: View {
            @State private var name = "Ada"
            var body: some View {
                TextField("Name", text: $name)
            }
        }
        """#)
        #expect(parsed.root?.kind == .textField(placeholder: "Name", initialText: "Ada", editable: true))
    }

    @Test func toggleSeedsInitialOnFromResolvedState() {
        let parsed = MockupEngine.parse(#"""
        struct V: View {
            @State private var enabled = true
            var body: some View {
                Toggle("Enabled", isOn: $enabled)
            }
        }
        """#)
        #expect(parsed.root?.kind == .toggle(title: "Enabled", initialOn: true, editable: true))
    }

    @Test func constantBindingIsNotEditable() {
        let node = root(#"TextField("Name", text: .constant("fixed"))"#)
        #expect(node.kind == .textField(placeholder: "Name", initialText: "fixed", editable: false))
    }

    @Test func unresolvedBindingRendersNonEditable() {
        let node = root(#"Toggle("X", isOn: $somethingUnknown)"#)
        #expect(node.kind == .toggle(title: "X", initialOn: false, editable: false))
    }

    @Test func identifierArgumentsResolveToLiterals() {
        let parsed = MockupEngine.parse(#"""
        struct V: View {
            let heading = "Dashboard"
            var body: some View {
                Text(heading).padding(gap)
            }
        }
        """#)
        // `gap` is undeclared, so padding has no length; `heading` resolves.
        #expect(parsed.root?.kind == .text("Dashboard"))
    }

    // MARK: - Shape styling

    @Test func fillOnAShapeIsCaptured() {
        let node = root(#"Circle().fill(.blue)"#)
        #expect(node.kind == .shape(.circle))
        #expect(node.modifiers == [.fill(.token("blue"))])
    }

    @Test func strokeOnAShapeCapturesColorAndWidth() {
        let node = root(#"Rectangle().stroke(.red, lineWidth: 2)"#)
        #expect(node.kind == .shape(.rectangle))
        #expect(node.modifiers == [.stroke(color: .token("red"), lineWidth: 2)])
    }

    @Test func linearGradientLowersToAGradientValue() {
        let node = root(#"Rectangle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))"#)
        #expect(node.modifiers == [.fill(.gradient(MockGradient(
            kind: .linear,
            colors: [.token("blue"), .token("purple")],
            startPoint: "top",
            endPoint: "bottom"
        )))])
    }

    @Test func foregroundStyleAcceptsAGradient() {
        let node = root(#"Text("Hi").foregroundStyle(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))"#)
        guard case let .foregroundStyle(value) = node.modifiers.first else {
            Issue.record("expected foregroundStyle")
            return
        }
        guard case .gradient = value else {
            Issue.record("expected a gradient value")
            return
        }
    }

    // MARK: - Custom views

    @Test func localViewStructIsInlined() {
        let node = root(#"""
        struct Screen: View {
            var body: some View {
                VStack { Header() }
            }
        }
        struct Header: View {
            var body: some View {
                Text("Title")
            }
        }
        """#)
        #expect(node.kind == .vstack(alignment: nil, spacing: nil, children: [MockNode(kind: .text("Title"))]))
    }

    @Test func computedSubviewPropertyIsInlined() {
        let node = root(#"""
        struct Screen: View {
            var body: some View {
                VStack { rows }
            }
            var rows: some View {
                Text("Row")
            }
        }
        """#)
        #expect(node.kind == .vstack(alignment: nil, spacing: nil, children: [MockNode(kind: .text("Row"))]))
    }

    @Test func callSiteLiteralArgsBindInsideTheInlinedView() {
        let node = root(#"""
        struct Screen: View {
            var body: some View {
                Card(title: "Pricing")
            }
        }
        struct Card: View {
            var title: String
            var body: some View {
                Text(title)
            }
        }
        """#)
        #expect(node.kind == .text("Pricing"))
    }

    @Test func recursiveLocalViewBecomesAPlaceholderNotAHang() {
        let parsed = MockupEngine.parse(#"""
        struct Loop: View {
            var body: some View {
                VStack { Loop() }
            }
        }
        """#)
        #expect(parsed.root != nil)
        #expect(parsed.diagnostics.contains { $0.message.contains("refers to itself") })
    }

    @Test func unknownViewThatIsNotLocalStillReportsClearly() {
        let parsed = MockupEngine.parse("TotallyMadeUpView()")
        #expect(parsed.root?.kind == .unsupported(label: "TotallyMadeUpView"))
        #expect(parsed.diagnostics.contains { $0.message.contains("not a builtin or local View") })
    }

    // MARK: - Diagnostics & recovery

    @Test func unknownViewRendersAsPlaceholderWithDiagnostic() {
        let parsed = MockupEngine.parse("SomeCustomView()")
        #expect(parsed.root?.kind == .unsupported(label: "SomeCustomView"))
        #expect(parsed.diagnostics.contains { $0.message.contains("SomeCustomView") })
    }

    @Test func brokenSyntaxStillYieldsWhateverParsed() {
        let parsed = MockupEngine.parse(#"""
        VStack {
            Text("Still here"
        }
        """#)
        #expect(parsed.parseFailed)
        #expect(parsed.root != nil)
    }

    @Test func nodeCountWalksTheWholeTree() {
        let parsed = MockupEngine.parse(#"""
        VStack {
            Text("A")
            Text("B")
        }
        """#)
        // VStack + 2 Text
        #expect(parsed.nodeCount == 3)
    }

    @Test func diagnosticsAreDeduplicatedByLineAndMessage() {
        let parsed = MockupEngine.parse(#"""
        VStack {
            Mystery()
            Mystery()
        }
        """#)
        let mysteryNotes = parsed.diagnostics.filter { $0.message.contains("Mystery") }
        #expect(mysteryNotes.count == 2)
    }

    // MARK: - Components

    @Test func secureFieldNoLongerAliasesTextField() {
        let node = root(#"SecureField("Password", text: .constant("hunter2"))"#)
        #expect(node.kind == .secureField(placeholder: "Password", initialText: "hunter2", editable: false))
    }

    @Test func pickerReadsOptionsFromChildTextLiterals() {
        let node = root(#"""
        Picker("Theme", selection: .constant(1)) {
            Text("Light")
            Text("Dark")
            Text("System")
        }
        """#)
        guard case let .picker(title, options, selectedIndex, _) = node.kind else {
            Issue.record("expected a picker, got \(node.kind)")
            return
        }
        #expect(title == "Theme")
        #expect(options == ["Light", "Dark", "System"])
        #expect(selectedIndex == 1)
    }

    @Test func pickerStyleModifierIsCapturedNotIgnored() {
        let node = root(#"""
        Picker("X", selection: .constant(0)) {
            Text("A")
            Text("B")
        }
        .pickerStyle(.segmented)
        """#)
        #expect(node.modifiers.contains(.pickerStyle(.segmented)))
    }

    @Test func sliderParsesItsRange() {
        let node = root("Slider(value: .constant(0.4), in: 0...10)")
        #expect(node.kind == .slider(value: 0.4, lowerBound: 0, upperBound: 10))
    }

    @Test func sliderWithoutASeededValueCentresInTheRange() {
        let node = root("Slider(value: $volume, in: 0...100)")
        guard case let .slider(value, lower, upper) = node.kind else {
            Issue.record("expected a slider")
            return
        }
        #expect(lower == 0 && upper == 100)
        #expect(value == 50)
    }

    @Test func stepperAndProgressViewAndGaugeLower() {
        #expect(root(#"Stepper("Qty", value: .constant(3))"#).kind == .stepper(title: "Qty", value: 3))
        #expect(root(#"ProgressView("Sync", value: 0.5)"#).kind == .progressView(title: "Sync", value: 0.5))
        #expect(root("ProgressView()").kind == .progressView(title: nil, value: nil))
        #expect(root(#"Gauge("Speed", value: 0.7)"#).kind == .gauge(title: "Speed", value: 0.7))
    }

    @Test func menuAndDisclosureGroupKeepTheirChildren() {
        let menu = root(#"""
        Menu("Actions") {
            Button("Rename") {}
            Button("Delete") {}
        }
        """#)
        guard case let .menu(title, children) = menu.kind else {
            Issue.record("expected a menu")
            return
        }
        #expect(title == "Actions")
        #expect(children.count == 2)

        let disclosure = root(#"""
        DisclosureGroup("More") {
            Toggle("A", isOn: .constant(true))
        }
        """#)
        guard case let .disclosureGroup(dTitle, _, dChildren) = disclosure.kind else {
            Issue.record("expected a disclosure group")
            return
        }
        #expect(dTitle == "More")
        #expect(dChildren.count == 1)
    }

    @Test func contentUnavailableViewReadsItsDescriptionText() {
        let node = root(#"""
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("Try again.")
        )
        """#)
        #expect(node.kind == .contentUnavailable(
            title: "No Results",
            systemImage: "magnifyingglass",
            description: "Try again."
        ))
    }

    @Test func navigationStackWrapsChildrenAndNavigationTitleApplies() {
        let node = root(#"""
        NavigationStack {
            Text("Body")
        }
        .navigationTitle("Home")
        """#)
        guard case let .navigationStack(children) = node.kind else {
            Issue.record("expected a navigation stack")
            return
        }
        #expect(children.count == 1)
        #expect(node.modifiers.contains(.navigationTitle("Home")))
    }

    @Test func navigationLinkCapturesTitleAndInlineDestination() {
        let node = root(#"""
        NavigationLink("Settings") {
            Text("Settings pane")
        }
        """#)
        guard case let .navigationLink(title, destination, targetName) = node.kind else {
            Issue.record("expected a navigation link, got \(node.kind)")
            return
        }
        #expect(title == "Settings")
        #expect(targetName == nil)
        #expect(destination?.kind == .text("Settings pane"))
    }

    @Test func navigationLinkUnknownDestinationIsAScreenTargetWithoutWarning() {
        let parsed = MockupEngine.parse(#"""
        NavigationLink("Settings") {
            SettingsView()
        }
        """#)
        #expect(parsed.diagnostics.filter { $0.severity == .warning }.isEmpty)
        guard case let .navigationLink(title, destination, targetName) = parsed.root?.kind else {
            Issue.record("expected a navigation link, got \(String(describing: parsed.root?.kind))")
            return
        }
        #expect(title == "Settings")
        #expect(destination == nil)
        #expect(targetName == "SettingsView")
    }

    @Test func navigationLinkLocalViewInlinesAndKeepsTargetName() {
        let node = root(#"""
        struct ContentView: View {
            var body: some View {
                NavigationLink("Settings") {
                    SettingsView()
                }
            }
        }

        struct SettingsView: View {
            var body: some View {
                Text("Local settings")
            }
        }
        """#)
        guard case let .navigationLink(title, destination, targetName) = node.kind else {
            Issue.record("expected a navigation link, got \(node.kind)")
            return
        }
        #expect(title == "Settings")
        #expect(targetName == "SettingsView")
        #expect(destination?.kind == .text("Local settings"))
    }

    @Test func navigationLinkLabeledDestinationUsesTrailingClosureAsLabel() {
        let node = root(#"""
        NavigationLink(destination: Text("Dest")) {
            Text("Go")
        }
        """#)
        guard case let .navigationLink(title, destination, targetName) = node.kind else {
            Issue.record("expected a navigation link, got \(node.kind)")
            return
        }
        #expect(title == "Go")
        #expect(targetName == nil)
        #expect(destination?.kind == .text("Dest"))
    }

    @Test func navigationLinkLabelTrailingClosureSetsTitle() {
        let node = root(#"""
        NavigationLink {
            Text("Dest")
        } label: {
            Text("Open")
        }
        """#)
        guard case let .navigationLink(title, destination, _) = node.kind else {
            Issue.record("expected a navigation link, got \(node.kind)")
            return
        }
        #expect(title == "Open")
        #expect(destination?.kind == .text("Dest"))
    }

    @Test func sheetModifierCapturesContentAndCover() {
        let node = root(#"""
        Button("Show") {}
            .sheet(isPresented: .constant(false)) {
                Text("Pane")
            }
        """#)
        #expect(node.modifiers.contains { modifier in
            if case let .sheet(content, targetName, isCover, autoPresent) = modifier {
                return content?.kind == .text("Pane")
                    && targetName == nil
                    && isCover == false
                    && autoPresent == false
            }
            return false
        })

        let cover = root(#"""
        Text("Host")
            .fullScreenCover(isPresented: .constant(true)) {
                DetailView()
            }
        """#)
        #expect(cover.modifiers.contains { modifier in
            if case let .sheet(content, targetName, isCover, autoPresent) = modifier {
                return content == nil
                    && targetName == "DetailView"
                    && isCover == true
                    && autoPresent == true
            }
            return false
        })
        #expect(MockupEngine.parse(#"""
        Text("Host").fullScreenCover(isPresented: .constant(true)) { DetailView() }
        """#).diagnostics.filter { $0.severity == .warning }.isEmpty)
    }

    @Test func tabViewNamesTabsFromTheirTabItem() {
        let node = root(#"""
        TabView {
            Text("One")
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            Text("Two")
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        """#)
        guard case let .tabView(tabs, _) = node.kind else {
            Issue.record("expected a tab view, got \(node.kind)")
            return
        }
        #expect(tabs.count == 2)
        #expect(tabs[0].title == "Home")
        #expect(tabs[0].systemImage == "house")
        #expect(tabs[1].title == "Settings")
    }

    @Test func chartReadsItsMarkTypeAndCount() {
        let bar = root(#"""
        Chart {
            ForEach(0..<7) {
                BarMark(x: .value("d", 0), y: .value("v", 0))
            }
        }
        """#)
        #expect(bar.kind == .chart(kind: .bar, count: 7))

        let line = root(#"""
        Chart {
            ForEach(0..<12) {
                LineMark(x: .value("d", 0), y: .value("v", 0))
            }
        }
        """#)
        #expect(line.kind == .chart(kind: .line, count: 12))
    }

    @Test func newComponentsAddNoWarningDiagnostics() {
        let sources = [
            #"Picker("X", selection: .constant(0)) { Text("A"); Text("B") }"#,
            "Slider(value: .constant(0.5), in: 0...1)",
            #"Gauge("G", value: 0.5)"#,
            #"Menu("M") { Button("x") {} }"#,
            "TabView { Text(\"a\").tabItem { Label(\"a\", systemImage: \"star\") } }",
            #"NavigationLink("Detail") { Text("Detail") }"#,
            #"Button("Show") {}.sheet(isPresented: .constant(false)) { Text("Sheet") }"#,
        ]
        for source in sources {
            let parsed = MockupEngine.parse(source)
            #expect(parsed.diagnostics.allSatisfy { $0.severity != .warning }, "warned for: \(source)")
        }
    }

    @Test func samplesLowerWithoutWarnings() {
        for sample in MockupSamples.all {
            let parsed = MockupEngine.parse(sample.source)
            #expect(!parsed.parseFailed, "\(sample.title): syntax error")
            #expect(
                parsed.diagnostics.allSatisfy { $0.severity != .warning },
                "\(sample.title): \(parsed.diagnostics.map(\.message).joined(separator: "; "))"
            )
        }
    }

    // MARK: - Multi-file workspace

    @Test func siblingFileViewIsInlinedInTheEntryFile() {
        let cardID = UUID()
        let homeID = UUID()
        let parsed = MockupEngine.parse(
            files: [
                MockupSourceFile(
                    id: cardID,
                    name: "ProfileCard",
                    source: """
                    struct ProfileCard: View {
                        var body: some View { Text("Card") }
                    }
                    """
                ),
                MockupSourceFile(
                    id: homeID,
                    name: "HomeView",
                    source: """
                    struct HomeView: View {
                        var body: some View { ProfileCard() }
                    }
                    """
                ),
            ],
            entryID: homeID
        )
        #expect(parsed.root?.kind == .text("Card"))
    }

    @Test func selectedFileWithoutAViewUsesTopLevelStatements() {
        let cardID = UUID()
        let pageID = UUID()
        let parsed = MockupEngine.parse(
            files: [
                MockupSourceFile(
                    id: cardID,
                    name: "Card",
                    source: """
                    struct Card: View {
                        var body: some View { Text("Card") }
                    }
                    """
                ),
                MockupSourceFile(id: pageID, name: "Page", source: "Card()"),
            ],
            entryID: pageID
        )
        #expect(parsed.root?.kind == .text("Card"))
    }

    @Test func firstFileWinsOnDuplicateTypeNames() {
        let firstID = UUID()
        let secondID = UUID()
        let homeID = UUID()
        let parsed = MockupEngine.parse(
            files: [
                MockupSourceFile(
                    id: firstID,
                    name: "A",
                    source: """
                    struct Card: View {
                        var body: some View { Text("A") }
                    }
                    """
                ),
                MockupSourceFile(
                    id: secondID,
                    name: "B",
                    source: """
                    struct Card: View {
                        var body: some View { Text("B") }
                    }
                    """
                ),
                MockupSourceFile(
                    id: homeID,
                    name: "Home",
                    source: """
                    struct Home: View {
                        var body: some View { Card() }
                    }
                    """
                ),
            ],
            entryID: homeID
        )
        #expect(parsed.root?.kind == .text("A"))
    }

    @Test func emptyEntryFileProducesNoRootEvenWhenSiblingsHaveViews() {
        let homeID = UUID()
        let parsed = MockupEngine.parse(
            files: [
                MockupSourceFile(
                    id: UUID(),
                    name: "Card",
                    source: """
                    struct Card: View {
                        var body: some View { Text("Card") }
                    }
                    """
                ),
                MockupSourceFile(id: homeID, name: "Home", source: "   \n  "),
            ],
            entryID: homeID
        )
        #expect(parsed.root == nil)
    }

    // MARK: - Multiple devices (#Preview / @Preview)

    @Test func unannotatedSubviewDoesNotGetItsOwnDevice() {
        let parsed = MockupEngine.parse(#"""
        struct Dashboard: View {
            var body: some View { StatGrid() }
        }
        struct StatGrid: View {
            var body: some View { Text("42") }
        }
        Capsule()
        """#)
        #expect(parsed.previews.count == 1)
        #expect(parsed.previews[0].name == "Dashboard")
        #expect(parsed.root?.kind == .text("42"))
    }

    @Test func previewMacroAddsAnotherDevice() {
        let parsed = MockupEngine.parse(#"""
        struct Dashboard: View {
            var body: some View { Text("Dash") }
        }
        struct StatGrid: View {
            var body: some View { Text("42") }
        }
        #Preview("Stats") {
            StatGrid()
        }
        #Preview("Capsule") {
            Capsule()
        }
        """#)
        #expect(parsed.previews.map(\.name) == ["Dashboard", "Stats", "Capsule"])
        #expect(parsed.previews[0].root.kind == .text("Dash"))
        #expect(parsed.previews[1].root.kind == .text("42"))
        #expect(parsed.previews[2].root.kind == .shape(.capsule))
    }

    @Test func previewAttributeOnAStructAddsAnotherDevice() {
        let parsed = MockupEngine.parse(#"""
        struct Dashboard: View {
            var body: some View { Text("Dash") }
        }
        @Preview
        struct StatGrid: View {
            var body: some View { Text("42") }
        }
        """#)
        #expect(parsed.previews.map(\.name) == ["Dashboard", "StatGrid"])
        #expect(parsed.previews[1].root.kind == .text("42"))
    }

    @Test func previewOfTheEntryStructIsNotDuplicated() {
        let parsed = MockupEngine.parse(#"""
        struct Dashboard: View {
            var body: some View { Text("Dash") }
        }
        #Preview {
            Dashboard()
        }
        """#)
        #expect(parsed.previews.count == 1)
        #expect(parsed.previews[0].name == "Dashboard")
    }

    @Test func previewOfTheEntryStructWithModifiersIsKeptAsAVariant() {
        let parsed = MockupEngine.parse(#"""
        struct Dashboard: View {
            var body: some View { Text("Dash") }
        }
        #Preview("Padded") {
            Dashboard().padding(16)
        }
        """#)
        #expect(parsed.previews.map(\.name) == ["Dashboard", "Padded"])
        #expect(parsed.previews[1].root.modifiers.contains(.padding(edges: nil, length: 16)))
    }

    @Test func previewMacrosAloneAreTheDevices() {
        let parsed = MockupEngine.parse(#"""
        #Preview("One") {
            Text("A")
        }
        #Preview("Two") {
            Text("B")
        }
        """#)
        #expect(parsed.previews.map(\.name) == ["One", "Two"])
        #expect(parsed.previews[0].root.kind == .text("A"))
        #expect(parsed.previews[1].root.kind == .text("B"))
    }

    @Test func unnamedPreviewInfersTheConstructorName() {
        let parsed = MockupEngine.parse(#"""
        struct Host: View {
            var body: some View { Text("Host") }
        }
        #Preview {
            Capsule().frame(width: 220, height: 64)
        }
        """#)
        #expect(parsed.previews.map(\.name) == ["Host", "Capsule"])
    }

    @Test func scenesIncludeSiblingFileStructsAndFileTitles() {
        let homeID = UUID()
        let parsed = MockupEngine.parse(
            files: [
                MockupSourceFile(
                    id: UUID(),
                    name: "Settings",
                    source: """
                    struct SettingsView: View {
                        var body: some View { Text("Gear") }
                    }
                    """
                ),
                MockupSourceFile(
                    id: homeID,
                    name: "Home",
                    source: """
                    struct Home: View {
                        var body: some View { Text("Hi") }
                    }
                    """
                ),
            ],
            entryID: homeID
        )
        #expect(parsed.previews.map(\.name) == ["Home"])
        #expect(parsed.scenes.map(\.name) == ["Home", "SettingsView", "Settings"])
        #expect(parsed.scenes.first { $0.name == "SettingsView" }?.root.kind == .text("Gear"))
        #expect(parsed.scenes.first { $0.name == "Settings" }?.root.kind == .text("Gear"))
    }

    @Test func siblingFilePreviewDoesNotAppearOnTheEntryCanvas() {
        let homeID = UUID()
        let parsed = MockupEngine.parse(
            files: [
                MockupSourceFile(
                    id: UUID(),
                    name: "Card",
                    source: """
                    struct Card: View {
                        var body: some View { Text("Card") }
                    }
                    #Preview {
                        Card()
                    }
                    """
                ),
                MockupSourceFile(
                    id: homeID,
                    name: "Home",
                    source: """
                    struct Home: View {
                        var body: some View { Card() }
                    }
                    """
                ),
            ],
            entryID: homeID
        )
        #expect(parsed.previews.count == 1)
        #expect(parsed.previews[0].name == "Home")
        #expect(parsed.root?.kind == .text("Card"))
    }

    // MARK: - onClickShow & scenes

    @Test func onClickShowLandsOnTheNode() {
        let node = root(#"Button("Go") {}.onClickShow("StatGrid")"#)
        #expect(node.kind == .button(title: "Go", children: []))
        #expect(node.modifiers.contains(.onClickShow("StatGrid")))
    }

    @Test func onClickShowUnknownNameIsNotAWarning() {
        let parsed = MockupEngine.parse(#"Text("x").onClickShow("Nope")"#)
        #expect(parsed.root?.modifiers.contains(.onClickShow("Nope")) == true)
        #expect(parsed.diagnostics.allSatisfy { $0.severity != .warning })
    }

    @Test func scenesIncludeUnpreviewedStructs() {
        let parsed = MockupEngine.parse(#"""
        struct Dashboard: View {
            var body: some View { Text("Dash") }
        }
        struct StatGrid: View {
            var body: some View { Text("42") }
        }
        """#)
        #expect(parsed.previews.count == 1)
        #expect(parsed.scenes.map(\.name) == ["Dashboard", "StatGrid"])
        #expect(parsed.scenes[1].root.kind == .text("42"))
    }

    @Test func scenesPreferPreviewTitlesThenStructNames() {
        let parsed = MockupEngine.parse(#"""
        struct Dashboard: View {
            var body: some View { Text("Dash") }
        }
        struct StatGrid: View {
            var body: some View { Text("42") }
        }
        #Preview("Stats") {
            StatGrid()
        }
        """#)
        #expect(parsed.scenes.map(\.name) == ["Dashboard", "Stats", "StatGrid"])
    }

    // MARK: - iOS 26

    @Test func glassEffectChainCapturesTintAndInteractive() {
        let node = root(#"Text("Hi").glassEffect(.regular.tint(.blue).interactive())"#)
        #expect(node.modifiers == [.glassEffect(
            MockGlass(variant: .regular, tint: .token("blue"), interactive: true), shape: nil
        )])
    }

    @Test func glassEffectDefaultsToRegularWithNoArguments() {
        let node = root(#"Text("Hi").glassEffect()"#)
        #expect(node.modifiers == [.glassEffect(MockGlass(), shape: nil)])
    }

    @Test func glassEffectContainerKeepsItsChildren() {
        let node = root(#"""
        GlassEffectContainer(spacing: 12) {
            Text("A")
            Text("B")
        }
        """#)
        #expect(node.kind == .glassEffectContainer(spacing: 12, children: [
            MockNode(kind: .text("A")), MockNode(kind: .text("B")),
        ]))
    }

    @Test func buttonStyleIsCapturedNotIgnored() {
        let node = root(#"Text("Hi").buttonStyle(.glassProminent)"#)
        #expect(node.modifiers == [.buttonStyle(.glassProminent)])
    }

    @Test func tabConstructorsProduceNamedAndSectionedTabs() {
        let node = root(#"""
        TabView {
            Tab("Home", systemImage: "house") {
                Text("Home")
            }
            Tab(role: .search) {
                Text("Search")
            }
            TabSection("More") {
                Tab("Settings", systemImage: "gear") {
                    Text("Settings")
                }
            }
        }
        """#)
        guard case let .tabView(tabs, _) = node.kind else {
            Issue.record("expected a tabView")
            return
        }
        #expect(tabs.map(\.title) == ["Home", "Search", "Settings"])
        #expect(tabs[1].isSearchRole == true)
        #expect(tabs[1].systemImage == "magnifyingglass")
        #expect(tabs[2].sectionTitle == "More")
    }

    @Test func tabBarMinimizeBehaviorAndBottomAccessoryAreCaptured() {
        let node = root(#"""
        TabView {
            Tab("Home", systemImage: "house") { Text("Home") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            Text("Now Playing")
        }
        """#)
        #expect(node.modifiers.contains(.tabBarMinimizeBehavior(.onScrollDown)))
        #expect(node.modifiers.contains(.tabViewBottomAccessory(MockNode(kind: .text("Now Playing")))))
    }

    @Test func toolbarItemsAreGroupedByPlacement() {
        let node = root(#"""
        Text("Hi").toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Leading")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text("Trailing")
            }
        }
        """#)
        guard case let .toolbar(items)? = node.modifiers.first else {
            Issue.record("expected a .toolbar modifier")
            return
        }
        #expect(items.map(\.placement) == [.leading, .trailing])
    }

    @Test func concentricAndUnevenShapesLower() {
        #expect(root("ConcentricRectangle()").kind == .shape(.concentric))
        let node = root("UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 8, bottomTrailingRadius: 12, topTrailingRadius: 16)")
        #expect(node.kind == .shape(.unevenRoundedRectangle(topLeading: 4, bottomLeading: 8, bottomTrailing: 12, topTrailing: 16)))
    }

    @Test func clipShapeAcceptsTheConcentricToken() {
        let node = root(#"Text("Hi").clipShape(.concentric)"#)
        #expect(node.modifiers == [.clipShape(.concentric)])
    }

    @Test func containerShapeIsCapturedNotIgnored() {
        let node = root(#"Text("Hi").containerShape(.concentric)"#)
        #expect(node.modifiers == [.containerShape(.concentric)])
    }

    @Test func symbolModifiersAreCapturedOnAnyNode() {
        let node = root(#"Text("Hi").symbolRenderingMode(.multicolor).imageScale(.large).symbolEffect(.bounce)"#)
        #expect(node.modifiers.contains(.symbolRenderingMode(.multicolor)))
        #expect(node.modifiers.contains(.imageScale(.large)))
        #expect(node.modifiers.contains(.symbolEffect(.bounce)))
    }

    @Test func shadowCapturesColorAndOffset() {
        let node = root(#"Text("Hi").shadow(color: .red, radius: 6, x: 1, y: 2)"#)
        #expect(node.modifiers == [.shadow(color: .token("red"), radius: 6, x: 1, y: 2)])
    }

    @Test func shadowDefaultsWhenOnlyRadiusIsGiven() {
        let node = root(#"Text("Hi").shadow(radius: 4)"#)
        #expect(node.modifiers == [.shadow(color: nil, radius: 4, x: 0, y: 0)])
    }

    @Test func linearGradientLowersAsADirectView() {
        let node = root(#"LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)"#)
        guard case let .color(.gradient(gradient)) = node.kind else {
            Issue.record("expected a gradient color node")
            return
        }
        #expect(gradient.kind == .linear)
        #expect(gradient.colors == [.token("blue"), .token("purple")])
    }

    @Test func alertCapturesTitleAndButtonTitles() {
        let node = root(#"""
        Text("Hi").alert("Delete?", isPresented: .constant(false)) {
            Button("Cancel") {}
            Button("Delete") {}
        }
        """#)
        #expect(node.modifiers == [.alert(title: "Delete?", message: nil, buttonTitles: ["Cancel", "Delete"])])
    }

    @Test func confirmationDialogDefaultsToAnOKButtonWhenEmpty() {
        let node = root(#"Text("Hi").confirmationDialog("Sure?", isPresented: .constant(false)) {}"#)
        #expect(node.modifiers == [.confirmationDialog(title: "Sure?", buttonTitles: ["OK"])])
    }

    @Test func popoverSharesTheSheetModifierNotFullScreen() {
        let node = root(#"""
        Text("Hi").popover(isPresented: .constant(false)) {
            Text("Popover")
        }
        """#)
        #expect(node.modifiers == [.sheet(
            content: MockNode(kind: .text("Popover")), targetName: nil, isCover: false, autoPresent: false
        )])
    }

    @Test func newLeafKindsLowerFromTheirConstructors() {
        #expect(root(#"LabeledContent("Title", value: "Value")"#).kind == .labeledContent(title: "Title", value: "Value"))
        #expect(root(#"WebView(url: "https://example.com")"#).kind == .webView(url: "https://example.com"))
        #expect(root(#"TextEditor(text: .constant("Body"))"#).kind == .textEditor(placeholder: "", initialText: "Body", editable: false))
    }

    @Test func styleModifiersArePromotedFromIgnoredToApplied() {
        let node = root(#"Text("Hi").listStyle(.plain).toggleStyle(.switch).labelStyle(.iconOnly).progressViewStyle(.linear).controlSize(.small)"#)
        #expect(node.modifiers.contains(.listStyle(.plain)))
        #expect(node.modifiers.contains(.toggleStyle(.swiftSwitch)))
        #expect(node.modifiers.contains(.labelStyle(.iconOnly)))
        #expect(node.modifiers.contains(.progressViewStyle(.linear)))
        #expect(node.modifiers.contains(.controlSize(.small)))
    }

    @Test func badgeIsCapturedNotIgnored() {
        let node = root(#"Text("Hi").badge("3")"#)
        #expect(node.modifiers == [.badge(.string("3"))])
    }
}
