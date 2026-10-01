import Foundation
import SwiftSyntax

/// Pure literal extraction shared by `MockupSourceModel` (collecting `@State`/`let` initial
/// values) and `MockupLowering` (resolving identifier references). No view context, no
/// diagnostics — just "is this expression a literal, and what is it".
nonisolated enum MockupLiterals {
    static func string(from expr: ExprSyntax) -> String? {
        guard let literal = expr.as(StringLiteralExprSyntax.self) else { return nil }
        var result = ""
        for segment in literal.segments {
            switch segment {
            case .stringSegment(let piece):
                result += piece.content.text
            case .expressionSegment:
                result += "…"
            }
        }
        return result
    }

    static func double(from expr: ExprSyntax) -> Double? {
        if let intLit = expr.as(IntegerLiteralExprSyntax.self) {
            return Double(intLit.literal.text.replacingOccurrences(of: "_", with: ""))
        }
        if let floatLit = expr.as(FloatLiteralExprSyntax.self) {
            return Double(floatLit.literal.text.replacingOccurrences(of: "_", with: ""))
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "-" {
            return double(from: prefix.expression).map { -$0 }
        }
        if let member = expr.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "zero" {
            return 0
        }
        return nil
    }

    static func bool(from expr: ExprSyntax) -> Bool? {
        if let literal = expr.as(BooleanLiteralExprSyntax.self) {
            return literal.literal.text == "true"
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" {
            return bool(from: prefix.expression).map { !$0 }
        }
        return nil
    }

    /// The leading-dot / dotted token name: `.red`, `Color.red`, `.center`, `.infinity`.
    static func token(from expr: ExprSyntax) -> String? {
        expr.as(MemberAccessExprSyntax.self)?.declName.baseName.text
    }

    /// A literal `MockValue` — string, number, bool, or bare token. Does not cover fonts or
    /// gradients (those are view-context specific and handled in `MockupLowering`).
    static func value(from expr: ExprSyntax) -> MockValue? {
        if let string = string(from: expr) { return .string(string) }
        if let double = double(from: expr) { return .number(double) }
        if let bool = bool(from: expr) { return .bool(bool) }
        if let token = token(from: expr) { return .token(token) }
        return nil
    }
}
