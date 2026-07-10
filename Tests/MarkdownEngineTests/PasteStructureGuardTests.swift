//
//  PasteStructureGuardTests.swift
//  MarkdownEngineTests
//
//  Created by Luca Chen on 09.07.26.
//
//  Specifies the block-structure guard the paste path uses to decide whether an
//  HTML flavor is worth converting to Markdown. Only real block structure
//  (lists, headings, tables, blockquotes, preformatted blocks, rules) should
//  pass; inline-only markup must fall through to the clean plain-text flavor so
//  code keeps its indentation and casually copied bold/links stay plain.
//
//  The `paste(_:)` override itself is not unit-tested here: it needs a live
//  NSTextView and NSPasteboard, so its branch selection is exercised through
//  this pure helper instead.
//

import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Paste HTML structure guard")
struct PasteStructureGuardTests {

    private func hasStructure(_ html: String) -> Bool {
        NativeTextView.htmlHasBlockStructure(html)
    }

    // MARK: - Block structure → convert

    @Test("unordered list is structural")
    func unorderedList() {
        #expect(hasStructure("<ul><li>One</li><li>Two</li></ul>"))
    }

    @Test("unordered list with attributes is structural")
    func unorderedListWithAttrs() {
        #expect(hasStructure("<ul class=\"x\"><li>One</li></ul>"))
    }

    @Test("ordered list is structural")
    func orderedList() {
        #expect(hasStructure("<ol start=\"3\"><li>One</li></ol>"))
    }

    @Test("heading is structural")
    func heading() {
        #expect(hasStructure("<h2>Title</h2>"))
    }

    @Test("table is structural")
    func table() {
        #expect(hasStructure("<table><tr><td>A</td></tr></table>"))
    }

    @Test("blockquote is structural")
    func blockquote() {
        #expect(hasStructure("<blockquote>Quoted</blockquote>"))
    }

    @Test("preformatted block is structural")
    func preformatted() {
        #expect(hasStructure("<pre><code>let x = 1</code></pre>"))
    }

    @Test("horizontal rule is structural")
    func horizontalRule() {
        #expect(hasStructure("Above<hr>Below"))
    }

    @Test("guard is case-insensitive")
    func caseInsensitive() {
        #expect(hasStructure("<H2>Shouting</H2>"))
        #expect(hasStructure("<TABLE><TR><TD>A</TD></TR></TABLE>"))
    }

    // MARK: - Inline only → fall through to plain text

    @Test("div-only (VS Code code) is not structural")
    func divOnly() {
        let code = "<div>func foo() {</div><div>    return 1</div><div>}</div>"
        #expect(!hasStructure(code))
    }

    @Test("span-only is not structural")
    func spanOnly() {
        #expect(!hasStructure("<span style=\"color:red\">word</span>"))
    }

    @Test("bold-only is not structural")
    func boldOnly() {
        #expect(!hasStructure("a <b>bold</b> word"))
    }

    @Test("italic-only is not structural")
    func italicOnly() {
        #expect(!hasStructure("a <i>slanted</i> word"))
    }

    @Test("anchor-only is not structural")
    func anchorOnly() {
        #expect(!hasStructure("see <a href=\"https://example.com\">here</a>"))
    }

    @Test("paragraph-only is not structural")
    func paragraphOnly() {
        #expect(!hasStructure("<p>Just a paragraph of text.</p>"))
    }

    @Test("plain text with no tags is not structural")
    func plainText() {
        #expect(!hasStructure("just some words, no markup at all"))
    }

    // MARK: - Formatted prose (chatbot / web / Word copy) → convert

    @Test("multiple bold-led paragraphs are structural (the chatbot prose shape)")
    func boldLedParagraphs() {
        let html = "<p><strong>Fristberechnung:</strong> Die zwei Wochen laufen ab Zugang.</p>"
            + "<p><strong>Schriftform:</strong> Muss eigenhändig unterschrieben sein.</p>"
        #expect(hasStructure(html))
    }

    @Test("Word-style paragraphs with <b> are structural")
    func wordParagraphs() {
        let html = "<p class=\"MsoNormal\"><b>Term:</b> definition</p>"
            + "<p class=\"MsoNormal\">second paragraph with <i>emphasis</i></p>"
        #expect(hasStructure(html))
    }

    @Test("multi-paragraph prose with links counts as formatted")
    func linkedParagraphs() {
        let html = "<p>See <a href=\"https://x.com\">the spec</a> first.</p>"
            + "<p>Then read on.</p>"
        #expect(hasStructure(html))
    }

    // MARK: - Still plain despite the prose rule

    @Test("two plain paragraphs without any formatting stay plain")
    func plainParagraphs() {
        #expect(!hasStructure("<p>First paragraph.</p><p>Second paragraph.</p>"))
    }

    @Test("a single formatted paragraph stays plain (casual copy)")
    func singleFormattedParagraph() {
        #expect(!hasStructure("<p><strong>bold</strong> word in one sentence</p>"))
    }

    @Test("bare list items are structural (Chromium strips the ul/ol wrapper)")
    func bareListItems() {
        let html = "<meta charset='utf-8'><li class=\"x\"><strong>A:</strong> one</li><li>two</li>"
        #expect(hasStructure(html))
    }

    @Test("pre does not count as a paragraph tag")
    func preIsNotParagraph() {
        // <pre is structural via its own needle — but the <p counter must not
        // be what trips it (guards the "<p" prefix against "<pre").
        #expect(hasStructure("<pre>code</pre>"))
        #expect(!hasStructure("<premium>not a tag</premium><premium>x</premium><b>y</b>"))
    }
}
