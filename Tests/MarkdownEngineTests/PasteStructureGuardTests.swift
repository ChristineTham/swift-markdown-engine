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
}
