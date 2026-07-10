//
//  MarkdownPasteboardWriterTests.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 11.07.26.
//
//  The web archive must carry OUR html verbatim (deriving it from
//  NSAttributedString(html:) dropped <hr> and checkboxes), and the RTF path
//  substitutes visible stand-ins for what RTF cannot represent.
//

import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Pasteboard writer flavors")
struct MarkdownPasteboardWriterTests {

    @Test("web archive wraps our html verbatim as its main resource")
    func webArchiveCarriesRealHTML() throws {
        let html = "<html><body><p>a</p><hr><li><input type=\"checkbox\" disabled> t</li></body></html>"
        let data = try #require(MarkdownPasteboardWriter.webArchiveData(html: html))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let main = try #require(plist["WebMainResource"] as? [String: Any])
        #expect(main["WebResourceMIMEType"] as? String == "text/html")
        let payload = try #require(main["WebResourceData"] as? Data)
        let roundTripped = try #require(String(data: payload, encoding: .utf8))
        #expect(roundTripped == html)   // <hr> and the checkbox survive untouched
    }

    @Test("rtf fallback rewrites task items to plain checkbox paragraphs (no list, no bullet)")
    func rtfFallbackTaskItems() {
        // Exactly what the renderer emits for "- [ ] open\n- [x] done".
        let body = "<ul>\n"
            + "<li style=\"list-style-type: none\"><input type=\"checkbox\" disabled> open</li>\n"
            + "<li style=\"list-style-type: none\"><input type=\"checkbox\" checked disabled> done</li>\n"
            + "</ul>"
        let out = MarkdownPasteboardWriter.rtfFallbackBody(body)
        // The list container is gone: the Cocoa HTML importer bullets every
        // <li> regardless of list-style-type, so plain <p> is the only safe form.
        #expect(out == "<p>☐ open</p>\n<p>☑ done</p>")
    }

    @Test("rtf fallback keeps bullets for non-task items in a mixed list")
    func rtfFallbackMixedList() {
        let body = "<ul>\n"
            + "<li>plain</li>\n"
            + "<li style=\"list-style-type: none\"><input type=\"checkbox\" disabled> task</li>\n"
            + "<li>tail</li>\n"
            + "</ul>"
        let out = MarkdownPasteboardWriter.rtfFallbackBody(body)
        #expect(out == "<ul>\n<li>plain</li>\n</ul>\n<p>☐ task</p>\n<ul>\n<li>tail</li>\n</ul>")
    }

    @Test("rtf fallback substitutes a 40-char rule stand-in for <hr>")
    func rtfFallbackRuleStandIn() {
        let out = MarkdownPasteboardWriter.rtfFallbackBody("<p>a</p>\n<hr>\n<p>b</p>")
        let rule = String(repeating: "─", count: 40)
        #expect(out == "<p>a</p>\n<p>\(rule)</p>\n<p>b</p>")
    }
}
