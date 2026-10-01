import Foundation
import Testing
@testable import SwiftyUI

/// Site-resolution and anti-drift coverage for `MockupCompletionEngine` / `MockupVocabulary`.
/// The engine is the tested unit; the popup (`EditorCompletionController`) and the editor view
/// stay untested per the project convention.
struct MockupCompletionTests {

    /// `§` marks the caret. The `prefix` handed to the engine is the same leading-identifier
    /// run `EditorIntelligence.makeCompletionContext` computes (letters and digits only).
    private func parseMarked(_ marked: String) -> (source: String, offset: Int, prefix: String) {
        let parts = marked.components(separatedBy: "§")
        precondition(parts.count == 2, "exactly one § caret marker")
        let source = parts.joined()
        let before = parts[0]
        let offset = before.utf16.count
        let prefix = String(before.reversed().prefix { $0.isLetter || $0.isNumber }.reversed())
        return (source, offset, prefix)
    }

    private func suggestions(_ marked: String, index: MockupCompletionIndex = .empty) -> [MockupCompletionSuggestion] {
        let parsed = parseMarked(marked)
        return MockupCompletionEngine.completions(
            source: parsed.source,
            cursorUTF16Offset: parsed.offset,
            prefix: parsed.prefix,
            index: index
        )
    }

    /// Labels the engine offers there, filtered by the same leading-identifier `prefix` that
    /// `EditorIntelligence.makeCompletionContext` computes.
    private func labels(_ marked: String, index: MockupCompletionIndex = .empty) -> [String] {
        suggestions(marked, index: index).map(\.label)
    }

    /// Applies `insertText` over the engine's replace span — the same UTF-16 math the popup
    /// uses when it honours the completion item's range.
    private func applied(_ marked: String, choosing label: String, index: MockupCompletionIndex = .empty) -> String? {
        let parsed = parseMarked(marked)
        guard let item = suggestions(marked, index: index).first(where: { $0.label == label }) else { return nil }
        let ns = parsed.source as NSString
        let location = item.replaceStartUTF16
        let length = item.replaceEndUTF16 - location
        guard location >= 0, length >= 0, location + length <= ns.length else { return nil }
        return ns.replacingCharacters(in: NSRange(location: location, length: length), with: item.insertText)
    }

    private func replacedToken(_ marked: String, choosing label: String) -> String? {
        let parsed = parseMarked(marked)
        guard let item = suggestions(marked).first(where: { $0.label == label }) else { return nil }
        let ns = parsed.source as NSString
        let location = item.replaceStartUTF16
        let length = item.replaceEndUTF16 - location
        guard location >= 0, length >= 0, location + length <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: location, length: length))
    }

    // MARK: - Site resolution

    @Test func statementPositionOffersViewNames() {
        let l = labels("HStack {\n    Te§\n}")
        #expect(l.contains("Text"))
        #expect(l.contains("TextField"))
        #expect(l.contains("Toggle"))
        #expect(!l.contains("padding"))
        #expect(!l.contains("font"))
    }

    @Test func topLevelStatementPositionOffersViewNames() {
        let l = labels("VSta§")
        #expect(l.contains("VStack"))
    }

    @Test func afterDotOnAViewOffersModifiers() {
        let l = labels(#"Text("x").fo§"#)
        #expect(l.contains("font"))
        #expect(l.contains("fontWeight"))
        #expect(l.contains("foregroundStyle"))
        #expect(!l.contains("VStack"))
        #expect(!l.contains("Text"))
    }

    @Test func modifierListIncludesRecognisedButIgnoredModifiers() {
        let l = labels(#"Text("x").§"#)
        #expect(l.contains("padding"))       // applied
        #expect(l.contains("onTapGesture"))  // ignored, still offered
    }

    @Test func insideConstructorParensOffersArgumentLabels() {
        let l = labels("VStack(§) {\n}")
        #expect(l.contains("alignment:"))
        #expect(l.contains("spacing:"))
    }

    @Test func argumentLabelsAreFilteredByPrefixAndDropUsedOnes() {
        #expect(labels("VStack(sp§) {\n}") == ["spacing:"])

        let used = labels("VStack(alignment: .leading, §) {\n}")
        #expect(used.contains("spacing:"))
        #expect(!used.contains("alignment:"))
    }

    @Test func leadingDotInColorArgumentOffersColourTokens() {
        let l = labels(#"Text("x").foregroundStyle(.re§)"#)
        #expect(l.contains("red"))
        #expect(!l.contains("regular"))
        #expect(!l.contains("leading"))
    }

    @Test func leadingDotInFontArgumentOffersFontTokens() {
        let l = labels(#"Text("x").font(.la§)"#)
        #expect(l.contains("largeTitle"))
    }

    @Test func alignmentTokensDependOnTheContainer() {
        #expect(labels("VStack(alignment: .§) {\n}").contains("leading"))
        #expect(labels("HStack(alignment: .§) {\n}").contains("firstTextBaseline"))
        #expect(!labels("VStack(alignment: .§) {\n}").contains("firstTextBaseline"))
    }

    @Test func tokenWithoutAPrecedingDotInsertsTheDot() {
        let source = "VStack(alignment: le) {\n}"
        let items = MockupCompletionEngine.completions(
            source: source,
            cursorUTF16Offset: "VStack(alignment: le".utf16.count,
            prefix: "le"
        )
        let leading = items.first { $0.label == "leading" }
        #expect(leading?.insertText == ".leading")
    }

    @Test func tokenAfterADotInsertsBareName() {
        let source = "VStack(alignment: .le) {\n}"
        let items = MockupCompletionEngine.completions(
            source: source,
            cursorUTF16Offset: "VStack(alignment: .le".utf16.count,
            prefix: "le"
        )
        let leading = items.first { $0.label == "leading" }
        #expect(leading?.insertText == "leading")
    }

    @Test func editingInsideAStringIsNotACompletionSite() {
        #expect(labels(#"Text("he§llo")"#).isEmpty)
    }

    @Test func colorMemberAccessOffersColourTokensNotModifiers() {
        let atDot = labels("Color.§")
        #expect(atDot.contains("red"))
        #expect(atDot.contains("blue"))
        #expect(!atDot.contains("padding"))
        #expect(!atDot.contains("font"))

        let partial = labels("Color.re§")
        #expect(partial.contains("red"))
        #expect(!partial.contains("padding"))
        #expect(!partial.contains("font"))
        #expect(!partial.contains("VStack"))
        #expect(applied("Color.re§", choosing: "red") == "Color.red")
    }

    @Test func fontSiteOffersSystemFactory() {
        let l = labels(#"Text("x").font(.sy§)"#)
        #expect(l.contains("system"))
        #expect(applied(#"Text("x").font(.sy§)"#, choosing: "system") == #"Text("x").font(.system(size: 17))"#)
    }

    @Test func attributeCompletionReplacesTheLeadingAtSign() {
        let marked = "@Sta§"
        #expect(labels(marked).contains("@State"))
        #expect(replacedToken(marked, choosing: "@State") == "@Sta")
        let result = applied(marked, choosing: "@State")
        #expect(result == "@State private var name = \"\"")
        #expect(!(result ?? "").contains("@@"))
    }

    @Test func attributeCompletionInsideAViewTypeReplacesTheLeadingAtSign() {
        let marked = """
        struct Card: View {
            @Sta§
            var body: some View { Text("x") }
        }
        """
        #expect(labels(marked).contains("@State"))
        let result = applied(marked, choosing: "@State") ?? ""
        #expect(result.contains("@State private var name = \"\""))
        #expect(!result.contains("@@State"))
    }

    @Test func dottedSymbolReplaceCoversTheWholeTypedName() {
        let marked = #"Image(systemName: "star.f§")"#
        #expect(labels(marked).contains("star.fill"))
        #expect(!labels(marked).contains("heart.fill"))
        #expect(replacedToken(marked, choosing: "star.fill") == "star.f")
        #expect(applied(marked, choosing: "star.fill") == #"Image(systemName: "star.fill")"#)
    }

    @Test func nestedDottedSymbolReplaceCoversTheWholeTypedName() {
        let marked = #"Image(systemName: "person.crop.circle.f§")"#
        #expect(labels(marked).contains("person.crop.circle.fill"))
        #expect(replacedToken(marked, choosing: "person.crop.circle.fill") == "person.crop.circle.f")
        #expect(applied(marked, choosing: "person.crop.circle.fill") == #"Image(systemName: "person.crop.circle.fill")"#)
    }

    @Test func modifierReplaceDoesNotEatTheMemberAccessDot() {
        #expect(applied(#"Text("x").fo§"#, choosing: "font") == #"Text("x").font(.body)"#)
    }

    // MARK: - Image assets

    @Test func bareImageStringOffersLibraryAssetNames() {
        let index = MockupCompletionIndex(views: [], assetNames: ["logo", "hero"])
        let l = labels(#"Image("lo§")"#, index: index)
        #expect(l.contains("logo"))
        #expect(!l.contains("hero"))
        #expect(applied(#"Image("lo§")"#, choosing: "logo", index: index) == #"Image("logo")"#)
    }

    @Test func assetNamesDoNotLeakIntoTheSystemNameLabel() {
        let index = MockupCompletionIndex(views: [], assetNames: ["logo"])
        let l = labels(#"Image(systemName: "sta§")"#, index: index)
        #expect(!l.contains("logo"))
        #expect(l.contains("star"))
    }

    @Test func systemImageStringDoesNotOfferAssetNames() {
        let index = MockupCompletionIndex(views: [], assetNames: ["logo"])
        let l = labels(#"Label("x", systemImage: "lo§")"#, index: index)
        #expect(!l.contains("logo"))
    }

    // MARK: - Local views

    @Test func locallyDeclaredViewsAreOfferedAtStatementPosition() {
        let source = """
        struct Dashboard: View {
            var body: some View {
                VStack {
                    Stat§
                }
            }
        }

        struct StatGrid: View {
            var body: some View { Text("x") }
        }
        """
        #expect(labels(source).contains("StatGrid"))
    }

    @Test func workspaceViewsFromSiblingFilesAreOffered() {
        let index = MockupCompletionIndex(views: [
            MockupIndexedView(name: "ProfileCard", parameters: [], originFile: "ProfileCard"),
        ])
        let l = labels("struct HomeView: View {\n    var body: some View {\n        Pr§\n    }\n}", index: index)
        #expect(l.contains("ProfileCard"))
    }

    @Test func localViewCallOffersParameterLabels() {
        let source = """
        struct CardView: View {
            var title: String
            var body: some View { Text(title) }
        }
        CardView(§)
        """
        #expect(labels(source).contains("title:"))
    }

    @Test func modifierCallOffersArgumentLabels() {
        let l = labels(#"Text("x").frame(§)"#)
        #expect(l.contains("width:"))
        #expect(l.contains("height:"))
        #expect(!l.contains("VStack"))
    }

    @Test func systemNameStringOffersSFSymbols() {
        let l = labels(#"Image(systemName: "st§")"#)
        #expect(l.contains("star"))
        #expect(l.contains("star.fill"))
        #expect(!l.contains("Text"))
    }

    @Test func fileTopLevelOffersPreviewMacro() {
        let l = labels("struct Card: View {\n    var body: some View { Text(\"x\") }\n}\n\n§")
        #expect(l.contains("#Preview"))
        #expect(l.contains("@Preview"))
    }

    @Test func previewMacroReplaceCoversTheLeadingPound() {
        let marked = "#Pre§"
        #expect(labels(marked).contains("#Preview"))
        #expect(replacedToken(marked, choosing: "#Preview") == "#Pre")
        #expect(applied(marked, choosing: "#Preview") == "#Preview {\n    \n}")
    }

    @Test func declarationSiteDoesNotOfferPreviewMacro() {
        let l = labels("""
        struct Card: View {
            §
            var body: some View { Text("x") }
        }
        """)
        #expect(!l.contains("#Preview"))
        #expect(l.contains("@State"))
    }

    @Test func declarationSiteDoesNotOfferViewBuilders() {
        let l = labels("""
        struct Card: View {
            §
            var body: some View { Text("x") }
        }
        """)
        #expect(l.contains("@State"))
        #expect(l.contains("struct View"))
        #expect(!l.contains("Text"))
        #expect(!l.contains("VStack"))
    }

    @Test func catalogSnippetsAreNotDumpedAtViewSites() {
        let l = labels("HStack {\n    §\n}")
        #expect(!l.contains("Styled text"))
        #expect(!l.contains("Spacer & Divider"))
        #expect(l.contains("Text"))
    }

    // MARK: - Offset conversion

    @Test func caretOffsetSurvivesNonASCIIEarlierInTheBuffer() {
        // The 😀 is two UTF-16 units but four UTF-8 bytes; a bad conversion lands the syntax
        // lookup mid-string and the site stops resolving to `.modifier`.
        let l = labels("Text(\"😀 hi\")\nText(\"x\").fo§")
        #expect(l.contains("font"))
    }

    // MARK: - Parity with the lowering (anti-drift)

    private func warnings(_ source: String) -> [String] {
        MockupEngine.parse(source).diagnostics
            .filter { $0.severity == .warning }
            .map(\.message)
    }

    private func containsUnsupported(_ node: MockNode) -> Bool {
        if case .unsupported = node.kind { return true }
        if node.childNodes.contains(where: containsUnsupported) { return true }
        if node.toolbarNodes.contains(where: containsUnsupported) { return true }
        for modifier in node.modifiers {
            switch modifier {
            case let .background(child), let .overlay(child, _):
                if containsUnsupported(child) { return true }
            case let .sheet(content, _, _, _):
                if let content, containsUnsupported(content) { return true }
            case let .safeAreaBar(_, child), let .tabViewBottomAccessory(child):
                if containsUnsupported(child) { return true }
            default:
                break
            }
        }
        return false
    }

    @Test func constructorAndModifierNamesAreUnique() {
        let constructors = MockupVocabulary.constructors.map(\.name)
        #expect(Set(constructors).count == constructors.count)

        let modifiers = MockupVocabulary.modifiers.map(\.name)
        #expect(Set(modifiers).count == modifiers.count)
    }

    @Test func everyConstructorSkeletonLowersCleanly() {
        for constructor in MockupVocabulary.constructors {
            let parsed = MockupEngine.parse(constructor.skeleton)
            #expect(parsed.root != nil, "\(constructor.name): produced no root")
            let w = parsed.diagnostics.filter { $0.severity == .warning }
            #expect(w.isEmpty, "\(constructor.name): \(w.map(\.message).joined(separator: "; "))")
            if let root = parsed.root {
                #expect(!containsUnsupported(root), "\(constructor.name): lowered to an unsupported placeholder")
            }
        }
    }

    @Test func everyModifierSkeletonAppliesWithoutWarning() {
        for modifier in MockupVocabulary.modifiers {
            let source = #"Text("x")."# + modifier.skeleton
            let w = warnings(source)
            #expect(w.isEmpty, "\(modifier.name): \(w.joined(separator: "; "))")
        }
    }

    @Test func everyColourTokenResolves() {
        for name in MockupVocabulary.tokens(for: .color) {
            #expect(MockupTokens.namedColor(name) != nil, "colour token '\(name)' no longer resolves")
        }
    }

    @Test func everyFontAndWeightTokenResolves() {
        for name in MockupVocabulary.tokens(for: .font) {
            #expect(MockupTokens.namedFont(name) != nil, "font token '\(name)' no longer resolves")
        }
        for name in MockupVocabulary.tokens(for: .fontWeight) {
            #expect(MockupTokens.fontWeight(name) != nil, "weight token '\(name)' no longer resolves")
        }
    }

    @Test func everyFontFactorySkeletonLowersCleanly() {
        for factory in MockupVocabulary.fontFactories {
            let source = #"Text("x").font(."# + factory.skeleton + ")"
            let parsed = MockupEngine.parse(source)
            let w = parsed.diagnostics.filter { $0.severity == .warning }
            #expect(w.isEmpty, "\(factory.name): \(w.map(\.message).joined(separator: "; "))")
            if let root = parsed.root {
                #expect(!containsUnsupported(root), "\(factory.name): lowered to an unsupported placeholder")
            }
        }
    }

    @Test func everyUnitPointTokenResolves() {
        for name in MockupVocabulary.tokens(for: .unitPoint) {
            #expect(MockupTokens.unitPoint(name) != nil, "unit-point token '\(name)' no longer resolves")
        }
    }

    /// Every token in a kind's list must resolve to a *different* concrete value — not just a
    /// non-empty list — so a typo like `firstTextBaseLine` (silently falling back to the same
    /// default as every other unrecognized name) is caught. `String(describing:)` sidesteps
    /// `HorizontalAlignment` / `VerticalAlignment` / `Alignment` / `TextAlignment` not being
    /// `Equatable` in SwiftUI.
    private func resolvesDistinctly<T>(_ kind: MockupVocabulary.ValueKind, _ resolve: (MockValue?) -> T) {
        let names = MockupVocabulary.tokens(for: kind)
        let descriptions = names.map { String(describing: resolve(.token($0))) }
        #expect(Set(descriptions).count == descriptions.count, "\(kind): some tokens collapsed to the same value")
    }

    @Test func everyHorizontalAlignmentTokenResolvesDistinctly() {
        resolvesDistinctly(.horizontalAlignment, MockupTokens.horizontalAlignment)
    }

    @Test func everyVerticalAlignmentTokenResolvesDistinctly() {
        resolvesDistinctly(.verticalAlignment, MockupTokens.verticalAlignment)
    }

    @Test func everyAlignmentTokenResolvesDistinctly() {
        resolvesDistinctly(.alignment, MockupTokens.alignment)
    }

    @Test func everyEdgeTokenResolvesDistinctly() {
        resolvesDistinctly(.edges, MockupTokens.edges)
    }

    @Test func everyTextAlignmentTokenResolvesDistinctly() {
        let names = MockupVocabulary.tokens(for: .textAlignment)
        let descriptions = names.map { String(describing: MockupTokens.textAlignment(.token($0))) }
        #expect(Set(descriptions).count == descriptions.count)
    }

    @Test func everyPickerStyleTokenResolvesDistinctly() {
        var seen: Set<MockPickerStyle> = []
        for name in MockupVocabulary.tokens(for: .pickerStyle) {
            let parsed = MockupEngine.parse(#"Text("x").pickerStyle(."# + name + ")")
            guard case let .pickerStyle(style)? = parsed.root?.modifiers.first else {
                Issue.record("'\(name)': pickerStyle(.\(name)) didn't lower to a .pickerStyle modifier")
                continue
            }
            seen.insert(style)
        }
        #expect(seen.count == MockupVocabulary.tokens(for: .pickerStyle).count, "some pickerStyle tokens collapsed")
    }

    @Test func everyContentModeTokenResolvesDistinctly() {
        var seen: Set<MockContentMode> = []
        for name in MockupVocabulary.tokens(for: .contentMode) {
            let parsed = MockupEngine.parse(#"Text("x").aspectRatio(contentMode: ."# + name + ")")
            guard case let .aspectRatio(_, mode)? = parsed.root?.modifiers.first else {
                Issue.record("'\(name)': aspectRatio(contentMode: .\(name)) didn't lower to .aspectRatio")
                continue
            }
            seen.insert(mode)
        }
        #expect(seen.count == MockupVocabulary.tokens(for: .contentMode).count, "some contentMode tokens collapsed")
    }

    @Test func dimensionAndSymbolTokenListsAreNonEmpty() {
        for kind in [MockupVocabulary.ValueKind.dimension, .symbol] {
            #expect(!MockupVocabulary.tokens(for: kind).isEmpty, "\(kind) lost its token list")
        }
    }

    /// Every `ValueKind` either has its own token list or is one of the documented free-form
    /// kinds served some other way (a live index, a raw literal, …).
    @Test func everyValueKindHasTokensOrIsFreeForm() {
        let freeForm: Set<MockupVocabulary.ValueKind> = [.number, .string, .bool, .other, .asset]
        for kind in MockupVocabulary.ValueKind.allCases where !freeForm.contains(kind) {
            #expect(!MockupVocabulary.tokens(for: kind).isEmpty, "\(kind) has no tokens and isn't marked free-form")
        }
    }

    /// The reverse-drift guard `MockupVocabulary`'s header promises: the ignored-modifier table
    /// now *drives* `MockupLowering.modifier(named:call:)`'s fallback case, so this can actually
    /// assert every name in it really is silently accepted — not just non-`.warning`
    /// (`everyModifierSkeletonAppliesWithoutWarning` already covers that) but not `.info`-flagged
    /// "isn't applied" either, which is what an unrecognized name would produce.
    @Test func everyIgnoredModifierIsRecognisedByTheLowering() {
        for name in MockupVocabulary.ignoredModifierNames {
            guard let modifier = MockupVocabulary.modifier(named: name), !modifier.isApplied else {
                Issue.record("'\(name)': in ignoredModifierNames but not an ignored Modifier entry")
                continue
            }
            let parsed = MockupEngine.parse(#"Text("x")."# + modifier.skeleton)
            let bad = parsed.diagnostics.filter { $0.message.contains("isn't applied") }
            #expect(bad.isEmpty, "'\(name)': \(bad.map(\.message).joined(separator: "; "))")
        }
    }

    @Test func everySinceVersionStringIsRecognised() {
        let known: Set<String> = ["iOS 16", "iOS 18", "iOS 26"]
        for constructor in MockupVocabulary.constructors {
            if let since = constructor.since {
                #expect(known.contains(since), "\(constructor.name): unrecognised since '\(since)'")
            }
        }
        for modifier in MockupVocabulary.modifiers {
            if let since = modifier.since {
                #expect(known.contains(since), "\(modifier.name): unrecognised since '\(since)'")
            }
        }
    }

    // MARK: - iOS 26 site resolution

    @Test func glassStyleMemberChainOffersItsMembers() {
        let l = labels(#"Text("x").glassEffect(.regular.§)"#)
        #expect(l.contains("tint"))
        #expect(l.contains("interactive"))
        #expect(!l.contains("padding"))
    }

    @Test func glassNamespaceOffersGlassStyleTokens() {
        let l = labels("Text(\"x\").glassEffect(Glass.§)")
        #expect(l.contains("regular"))
        #expect(l.contains("clear"))
    }

    @Test func buttonStyleOffersGlassTokens() {
        let l = labels("Button(\"Go\") {}.buttonStyle(.§)")
        #expect(l.contains("glass"))
        #expect(l.contains("glassProminent"))
    }

    @Test func clipShapeOffersShapeTokensIncludingConcentric() {
        let l = labels("Text(\"x\").clipShape(.§)")
        #expect(l.contains("concentric"))
        #expect(l.contains("circle"))
    }
}
