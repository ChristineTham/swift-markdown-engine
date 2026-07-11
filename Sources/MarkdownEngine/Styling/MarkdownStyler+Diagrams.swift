//
//  MarkdownStyler+Diagrams.swift
//  MarkdownEngine
//
//  Renders fenced diagram code blocks (```mermaid …```) inline as images,
//  mirroring the block-LaTeX pass in MarkdownStyler+Latex.swift. When a
//  `DiagramRenderer` is configured and the caret is outside the block, the
//  fenced source collapses and the rendered image is drawn in its place;
//  moving the caret into the block reveals the raw source for editing.
//

import AppKit
import Foundation

extension MarkdownStyler {

    static func styleDiagramBlocks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .codeBlock {
            guard let language = fenceInfoString(of: token, in: ctx.nsText) else { continue }

            // Editing the block? Leave it as an ordinary code block so the raw
            // source shows with normal monospace + syntax styling.
            if ctx.activeTokenIndices.contains(idx) { continue }

            // Only render a diagram when the block stands alone in its paragraph
            // (same requirement block LaTeX has for `appendRenderedStandaloneBlock`).
            guard token.standaloneParagraphRange(in: ctx.nsText) != nil else { continue }

            let rawSource = ctx.nsText.substring(with: token.contentRange)
            let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty,
                  let result = ctx.services.diagrams.render(
                    source: source,
                    language: language,
                    theme: ctx.configuration.theme
                  )
            else { continue }

            // Suppress the code-block background so no filled box shows behind
            // the diagram — the AST styler tagged this range as code earlier.
            attrs.append((token.range, [.backgroundColor: NSColor.clear]))

            _ = appendRenderedStandaloneBlock(
                for: token,
                rawContent: rawSource,
                image: result.image,
                imageBounds: CGRect(x: 0, y: 0, width: result.size.width, height: result.size.height),
                paragraphSpacingBefore: ctx.configuration.blockLatex.paragraphSpacingBefore,
                paragraphSpacing: ctx.configuration.blockLatex.paragraphSpacing,
                alignment: .center,
                mode: .collapsedSource(markerTexts: [
                    ctx.nsText.substring(with: token.markerRanges[0]),
                    ctx.nsText.substring(with: token.markerRanges[1])
                ]),
                ctx: ctx,
                attrs: &attrs
            )
        }
        return attrs
    }

    /// The fence info string (language) of a code-block token, e.g. `"mermaid"`
    /// for ```` ```mermaid ````. `nil` for a bare ```` ``` ```` fence.
    private static func fenceInfoString(of token: MarkdownToken, in ns: NSString) -> String? {
        guard let openMarker = token.markerRanges.first else { return nil }
        let info = ns.substring(with: openMarker)
            .drop(while: { $0 == "`" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return info.isEmpty ? nil : info
    }
}
