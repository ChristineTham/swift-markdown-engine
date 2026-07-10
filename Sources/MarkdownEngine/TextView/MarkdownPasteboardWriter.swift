//
//  MarkdownPasteboardWriter.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//
//  Writes a clean, multi-flavor representation of a raw markdown selection to
//  an NSPasteboard. The editor's storage holds RAW markdown styled in place,
//  so a default copy leaks syntax markers and drops thematic breaks. Here we
//  render the raw markdown to clean HTML, write it as web archive + HTML,
//  derive RTF with visible stand-ins for constructs RTF cannot carry, and
//  keep the raw markdown itself as the plain-text flavor.
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

        // Web archive built straight from OUR html — deriving it from
        // NSAttributedString(html:) silently dropped <hr> and checkboxes, so
        // WebKit-reading consumers get the real document instead.
        if let web = webArchiveData(html: fullHTML) {
            pasteboard.setData(web, forType: NSPasteboard.PasteboardType("com.apple.webarchive"))
        }
        pasteboard.setData(Data(fullHTML.utf8), forType: .html)

        // RTF for consumers without web-archive support. RTF has no horizontal
        // rule or checkbox and the HTML importer drops both, so convert a body
        // with visible stand-ins (─ rule, ☐/☑) on the main thread.
        let rtfHTML = "<html><head><meta charset=\"utf-8\"></head><body>\(rtfFallbackBody(htmlBody))</body></html>"
        if let data = rtfHTML.data(using: .utf8),
           let attr = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ),
           let rtf = try? attr.data(
               from: NSRange(location: 0, length: attr.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
           ) {
            pasteboard.setData(rtf, forType: .rtf)
        }
    }

    /// Stand-ins for constructs the RTF path cannot represent — the HTML
    /// importer drops `<hr>` and `<input>` outright, and it emits a bullet for
    /// every `<li>` no matter what `list-style-type` says (probed empirically:
    /// neither inline CSS on the `<li>` nor on the `<ul>` suppresses the
    /// marker). So task items are rewritten OUT of list markup into plain
    /// `<p>☐/☑ text</p>` paragraphs — the only importer-safe representation —
    /// before any generic glyph substitution, and their list containers are
    /// closed around them so no checkbox-bearing `<li>` ever reaches the
    /// converter. Non-task items in mixed lists keep their bullets.
    static func rtfFallbackBody(_ body: String) -> String {
        var out: [String] = []
        var openListTag: String?     // list container currently open in the OUTPUT
        var sourceListTag: String?   // list container currently open in the SOURCE

        for line in body.components(separatedBy: "\n") {
            switch line {
            case "<ul>", "<ol>":
                // Withhold the opener until a non-task item needs it, so a
                // list made only of task items loses its container entirely.
                sourceListTag = String(line.dropFirst().dropLast())
            case "</ul>", "</ol>":
                if let tag = openListTag { out.append("</\(tag)>"); openListTag = nil }
                sourceListTag = nil
            default:
                if let (checked, content) = taskListItemParts(line) {
                    // Task item → plain paragraph, outside any list.
                    if let tag = openListTag { out.append("</\(tag)>"); openListTag = nil }
                    out.append("<p>\(checked ? "☑" : "☐") \(content)</p>")
                } else {
                    if let tag = sourceListTag, openListTag == nil, line.hasPrefix("<li") {
                        out.append("<\(tag)>")
                        openListTag = tag
                    }
                    out.append(line)
                }
            }
        }

        return out.joined(separator: "\n")
            // The importer drops <hr> and cannot carry border CSS; a line of
            // U+2500 (glyphs connect edge-to-edge) is the only visible rule.
            // 40 chars: reads as a full-width separator, yet stays under
            // narrow wrap points (~72-char mail/chat columns) so it never
            // wraps into two stacked lines.
            .replacingOccurrences(of: "<hr>", with: "<p>\(rtfRuleStandIn)</p>")
            // Safety net for any checkbox that escaped the li→p rewrite.
            .replacingOccurrences(of: "<input type=\"checkbox\" checked disabled>", with: "☑")
            .replacingOccurrences(of: "<input type=\"checkbox\" disabled>", with: "☐")
    }

    /// The visible horizontal-rule stand-in for the RTF flavor.
    static let rtfRuleStandIn = String(repeating: "─", count: 40)

    /// One rendered task-item line — `<li>` with any attributes (the renderer
    /// emits `style="list-style-type: none"`), the checkbox input in either
    /// checked form, then the item text.
    private static let taskListItemPattern = try! NSRegularExpression(
        pattern: "^<li(?: [^>]*)?><input type=\"checkbox\"( checked)? disabled> ?(.*)</li>$"
    )

    private static func taskListItemParts(_ line: String) -> (checked: Bool, content: String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = taskListItemPattern.firstMatch(in: line, range: range) else { return nil }
        let checked = m.range(at: 1).location != NSNotFound
        let content = Range(m.range(at: 2), in: line).map { String(line[$0]) } ?? ""
        return (checked, content)
    }

    /// A minimal Safari-style web archive with `html` as its main resource.
    static func webArchiveData(html: String) -> Data? {
        let resource: [String: Any] = [
            "WebResourceData": Data(html.utf8),
            "WebResourceMIMEType": "text/html",
            "WebResourceTextEncodingName": "UTF-8",
            "WebResourceURL": "about:blank",
        ]
        return try? PropertyListSerialization.data(
            fromPropertyList: ["WebMainResource": resource],
            format: .binary,
            options: 0
        )
    }
}
