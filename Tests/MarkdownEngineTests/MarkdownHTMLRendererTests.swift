//
//  MarkdownHTMLRendererTests.swift
//  MarkdownEngineTests
//
//  Test-first specification for the clean Markdown→HTML renderer used by the
//  editor's rich-copy path. Asserts the exact HTML fragment produced for each
//  representative construct.
//

import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Markdown → HTML renderer")
struct MarkdownHTMLRendererTests {

    private func html(_ md: String) -> String { MarkdownHTMLRenderer.html(from: md) }

    // MARK: - Headings

    @Test("h1 and h2")
    func headings() {
        #expect(html("# Title") == "<h1>Title</h1>")
        #expect(html("## Sub") == "<h2>Sub</h2>")
    }

    // MARK: - Inline emphasis

    @Test("bold, italic, and bold-italic")
    func emphasis() {
        #expect(html("*i*") == "<p><em>i</em></p>")
        #expect(html("**b**") == "<p><strong>b</strong></p>")
        #expect(html("***x***") == "<p><strong><em>x</em></strong></p>")
    }

    @Test("emphasis nested in a paragraph")
    func emphasisInParagraph() {
        #expect(html("hello **world**") == "<p>hello <strong>world</strong></p>")
    }

    // MARK: - Inline code

    @Test("inline code span")
    func inlineCode() {
        #expect(html("`code`") == "<p><code>code</code></p>")
    }

    // MARK: - Fenced code block

    @Test("fenced code block with language")
    func fencedCode() {
        let md = "```swift\nlet x = 1\n```"
        #expect(html(md) == "<pre><code class=\"language-swift\">let x = 1</code></pre>")
    }

    @Test("fenced code block without language")
    func fencedCodeNoLang() {
        let md = "```\nplain\n```"
        #expect(html(md) == "<pre><code>plain</code></pre>")
    }

    @Test("fenced code block escapes html")
    func fencedCodeEscapes() {
        let md = "```\n<a> & <b>\n```"
        #expect(html(md) == "<pre><code>&lt;a&gt; &amp; &lt;b&gt;</code></pre>")
    }

    // MARK: - Link

    @Test("a link")
    func link() {
        #expect(html("[text](http://x.com)") == "<p><a href=\"http://x.com\">text</a></p>")
    }

    // MARK: - Lists

    @Test("unordered list")
    func unorderedList() {
        let md = "- a\n- b"
        #expect(html(md) == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>")
    }

    @Test("ordered list")
    func orderedList() {
        let md = "1. a\n2. b"
        #expect(html(md) == "<ol>\n<li>a</li>\n<li>b</li>\n</ol>")
    }

    @Test("task list — checkbox replaces the bullet (list-style-type: none)")
    func taskList() {
        let md = "- [ ] todo\n- [x] done"
        #expect(html(md) == "<ul>\n<li style=\"list-style-type: none\"><input type=\"checkbox\" disabled> todo</li>\n<li style=\"list-style-type: none\"><input type=\"checkbox\" checked disabled> done</li>\n</ul>")
    }

    @Test("mixed list — only task items lose their marker")
    func mixedTaskList() {
        let md = "- plain\n- [ ] task"
        #expect(html(md) == "<ul>\n<li>plain</li>\n<li style=\"list-style-type: none\"><input type=\"checkbox\" disabled> task</li>\n</ul>")
    }

    // MARK: - Blockquote

    @Test("blockquote strips markers")
    func blockquote() {
        #expect(html("> hello") == "<blockquote>hello</blockquote>")
    }

    @Test("blockquote keeps inline emphasis")
    func blockquoteEmphasis() {
        #expect(html("> a **b**") == "<blockquote>a <strong>b</strong></blockquote>")
    }

    // MARK: - Thematic break (the headline bug)

    @Test("thematic break becomes hr")
    func thematicBreak() {
        #expect(html("---").contains("<hr"))
        #expect(html("***").contains("<hr"))
        #expect(html("___").contains("<hr"))
    }

    // MARK: - Table

    @Test("GFM table")
    func table() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let out = html(md)
        #expect(out.contains("<table"))
        #expect(out.contains("<th>A</th>"))
        #expect(out.contains("<th>B</th>"))
        #expect(out.contains("<td>1</td>"))
        #expect(out.contains("<td>2</td>"))
    }

    // MARK: - HTML escaping

    @Test("escapes angle brackets and ampersand in text")
    func escaping() {
        #expect(html("a < b & c > d") == "<p>a &lt; b &amp; c &gt; d</p>")
    }

    // MARK: - Multiple blocks

    @Test("multiple blocks joined by newline")
    func multipleBlocks() {
        let md = "# Title\n\nA paragraph."
        #expect(html(md) == "<h1>Title</h1>\n<p>A paragraph.</p>")
    }
}
