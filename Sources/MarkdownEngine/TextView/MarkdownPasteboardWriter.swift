//
//  MarkdownPasteboardWriter.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//
//  Writes a clean, multi-flavor representation of a raw markdown selection to
//  an NSPasteboard. The editor's storage holds RAW markdown styled in place,
//  so a default copy leaks syntax markers and drops thematic breaks. Here we
//  render the raw markdown to clean HTML and derive RTF + web archive from it,
//  while keeping the raw markdown itself as the plain-text flavor.
//

import AppKit

enum MarkdownPasteboardWriter {
    /// Private flavor carrying the exact raw markdown of the selection. When one
    /// of our own editors pastes, it prefers this over the derived HTML so wiki
    /// links (`[[Name|UUID]]`), code, and every other construct round-trip
    /// byte-exact instead of being re-derived from the lossy HTML flavor.
    static let markdownType = NSPasteboard.PasteboardType("dev.markdownengine.raw-markdown")

    @MainActor
    static func write(markdown: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        // Always keep the raw markdown available as plain text.
        pasteboard.setString(markdown, forType: .string)

        // Also keep the exact raw markdown under our private flavor so our own
        // paste path can round-trip it losslessly.
        pasteboard.setString(markdown, forType: Self.markdownType)

        // Render the selection to clean HTML.
        let htmlBody = MarkdownHTMLRenderer.html(from: markdown)
        let fullHTML = "<html><head><meta charset=\"utf-8\"></head><body>\(htmlBody)</body></html>"

        // Build a clean attributed string from the HTML on the main thread.
        guard let data = fullHTML.data(using: .utf8),
              let attr = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              )
        else {
            // Raw markdown is already on the pasteboard as plain text.
            pasteboard.setData(Data(fullHTML.utf8), forType: .html)
            return
        }

        let fullRange = NSRange(location: 0, length: attr.length)

        // Derive and write RTF.
        if let rtf = try? attr.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pasteboard.setData(rtf, forType: .rtf)
        }

        // Derive and write the web archive (the point of this change).
        if let web = try? attr.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.webArchive]
        ) {
            pasteboard.setData(web, forType: NSPasteboard.PasteboardType("com.apple.webarchive"))
        }

        // Also write the raw HTML.
        pasteboard.setData(Data(fullHTML.utf8), forType: .html)
    }
}
