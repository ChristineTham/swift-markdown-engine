//
//  MarkdownStyler+Callouts.swift
//  MarkdownEngine
//
//  Styles Obsidian-style callouts: a blockquote whose first line begins with
//  `[!type]`. The block gets a tinted band + accent bar (drawn by
//  MarkdownTextLayoutFragment via `.calloutTint`), the title line is set bold
//  in the accent color, and the `[!` `]` punctuation is hidden.
//

import AppKit
import Foundation

extension MarkdownStyler {

    private static let calloutHeaderRegex = try! NSRegularExpression(
        pattern: #"^(\s*)\[!([A-Za-z][\w-]*)\]"#
    )

    static func styleCallouts(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for group in blockquoteGroups(in: ctx) {
            guard let first = group.first else { continue }
            let content = ctx.nsText.substring(with: first.contentRange)
            guard let match = calloutHeaderRegex.firstMatch(
                in: content, range: NSRange(content.startIndex..., in: content)
            ) else { continue }

            let wsLen = match.range(at: 1).length
            let type = (content as NSString).substring(with: match.range(at: 2)).lowercased()
            let tint = calloutColor(for: type)

            // Tinted band + accent bar per line; suppress the grey quote bar.
            for line in group {
                attrs.append((line.range, [.calloutTint: tint]))
                attrs.append((line.range, [.blockquoteLevel: 0]))
            }

            // Title line: bold + accent, and hide the `[!` … `]` punctuation.
            let contentLoc = first.contentRange.location
            let headerContentRange = NSRange(location: contentLoc + wsLen,
                                             length: first.contentRange.length - wsLen)
            let headerFont = boldFont(ctx.baseFont)
            attrs.append((headerContentRange, [.foregroundColor: tint, .font: headerFont]))

            hide(NSRange(location: contentLoc + wsLen, length: 2), ctx: ctx, into: &attrs)       // "[!"
            let typeRange = match.range(at: 2)
            let closeBracket = NSRange(location: contentLoc + typeRange.location + typeRange.length, length: 1) // "]"
            hide(closeBracket, ctx: ctx, into: &attrs)
        }
        return attrs
    }

    private static func boldFont(_ font: NSFont) -> NSFont {
        let merged = font.fontDescriptor.symbolicTraits.union(.bold)
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(merged), size: font.pointSize) ?? font
    }

    /// Kern a short run to zero width and clear it, reusing the marker-hiding trick.
    private static func hide(_ range: NSRange, ctx: StylingContext, into attrs: inout [StyledRange]) {
        guard range.location >= 0, NSMaxRange(range) <= ctx.nsText.length else { return }
        let text = ctx.nsText.substring(with: range)
        attrs.append((range, [
            .foregroundColor: NSColor.clear,
            .font: ctx.latexMarkerFont,
            .kern: -HeadingHelpers.textWidth(text, font: ctx.latexMarkerFont)
        ]))
    }

    /// Consecutive `.blockquote` line tokens grouped into contiguous blocks.
    private static func blockquoteGroups(in ctx: StylingContext) -> [[MarkdownToken]] {
        var groups: [[MarkdownToken]] = []
        var current: [MarkdownToken] = []
        var lastEnd = -1
        for token in ctx.tokens where token.kind == .blockquote {
            let contiguous = !current.isEmpty && isSingleLineBreak(between: lastEnd, and: token.range.location, in: ctx.nsText)
            if contiguous {
                current.append(token)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [token]
            }
            lastEnd = NSMaxRange(token.range)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// True when the gap between two blockquote lines is exactly one line break.
    private static func isSingleLineBreak(between end: Int, and start: Int, in text: NSString) -> Bool {
        guard end >= 0, start >= end, start <= text.length else { return false }
        let gap = text.substring(with: NSRange(location: end, length: start - end))
        return gap == "\n" || gap == "\r\n" || gap == "\r"
    }

    private static func calloutColor(for type: String) -> NSColor {
        switch type {
        case "tip", "hint", "success", "check", "done": return .systemGreen
        case "warning", "caution", "attention": return .systemOrange
        case "failure", "fail", "danger", "error", "bug", "missing": return .systemRed
        case "example": return .systemPurple
        case "quote", "cite": return .systemGray
        case "question", "help", "faq": return .systemTeal
        default: return .systemBlue   // note, info, todo, abstract, …
        }
    }
}
