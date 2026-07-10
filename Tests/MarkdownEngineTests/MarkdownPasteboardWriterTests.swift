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

    @Test("rtf fallback substitutes rule and checkbox stand-ins")
    func rtfFallbackStandIns() {
        let body = "<hr><li><input type=\"checkbox\" disabled> open</li>"
            + "<li><input type=\"checkbox\" checked disabled> done</li>"
        let out = MarkdownPasteboardWriter.rtfFallbackBody(body)
        #expect(out.contains("─"))
        #expect(out.contains("☐ open"))   // glyph replaces the tag, space + text come from the source
        #expect(out.contains("☑ done"))
        #expect(!out.contains("<input"))
        #expect(!out.contains("<hr>"))
    }
}
