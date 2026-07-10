//
//  HTMLToMarkdownConverterTests.swift
//  MarkdownEngineTests
//
//  Test-first specification for the lenient HTML→Markdown converter used by
//  the editor's smart-paste path. Asserts the exact Markdown produced for each
//  representative construct, including messy real-world clipboard HTML.
//

import Foundation
import Testing
@testable import MarkdownEngine

@Suite("HTML → Markdown converter")
struct HTMLToMarkdownConverterTests {

    private func md(_ html: String) -> String? {
        HTMLToMarkdownConverter.markdown(fromHTML: html)
    }

    // MARK: - The headline case: unordered list → "- " lines

    @Test("unordered list of three items")
    func unorderedList() {
        let html = "<ul><li>One</li><li>Two</li><li>Three</li></ul>"
        #expect(md(html) == "- One\n- Two\n- Three")
    }

    // MARK: - Ordered list

    @Test("ordered list increments 1. 2. 3.")
    func orderedList() {
        let html = "<ol><li>Alpha</li><li>Beta</li><li>Gamma</li></ol>"
        #expect(md(html) == "1. Alpha\n2. Beta\n3. Gamma")
    }

    // MARK: - Nested list

    @Test("nested ul inside an li indents by two spaces")
    func nestedList() {
        let html = "<ul><li>Parent<ul><li>Child</li></ul></li></ul>"
        #expect(md(html) == "- Parent\n  - Child")
    }

    // MARK: - Task list

    @Test("checkbox li becomes GFM task item")
    func taskList() {
        let html = "<ul>"
            + "<li><input type=\"checkbox\">Todo</li>"
            + "<li><input type=\"checkbox\" checked>Done</li>"
            + "</ul>"
        #expect(md(html) == "- [ ] Todo\n- [x] Done")
    }

    // MARK: - Headings

    @Test("h1 and h2")
    func headings() {
        #expect(md("<h1>Title</h1>") == "# Title")
        #expect(md("<h2>Sub</h2>") == "## Sub")
    }

    // MARK: - Inline emphasis

    @Test("strong and em")
    func emphasis() {
        let html = "<p><strong>bold</strong> and <em>italic</em></p>"
        #expect(md(html) == "**bold** and *italic*")
    }

    // MARK: - Links

    @Test("anchor with href")
    func anchor() {
        let html = "<a href=\"https://example.com\">link</a>"
        #expect(md(html) == "[link](https://example.com)")
    }

    // MARK: - Inline code

    @Test("inline code span")
    func inlineCode() {
        let html = "<p>Use <code>let x</code> here</p>"
        #expect(md(html) == "Use `let x` here")
    }

    // MARK: - Fenced code block

    @Test("pre code with language class")
    func fencedCode() {
        let html = "<pre><code class=\"language-swift\">let x = 1</code></pre>"
        #expect(md(html) == "```swift\nlet x = 1\n```")
    }

    // MARK: - Blockquote

    @Test("blockquote prefixes each line")
    func blockquote() {
        #expect(md("<blockquote>quoted</blockquote>") == "> quoted")
    }

    // MARK: - Horizontal rule

    @Test("hr becomes a dashed line")
    func horizontalRule() {
        #expect(md("<hr>") == "----")
    }

    // MARK: - Messy real-world clipboard HTML

    @Test("messy inline styles and meta are unwrapped")
    func messyClipboardHTML() {
        let html = "<meta charset=\"utf-8\">"
            + "<ul>"
            + "<li><span style=\"color:red\">Live-Neuberechnung</span></li>"
            + "<li>Inline-Rendering</li>"
            + "</ul>"
        #expect(md(html) == "- Live-Neuberechnung\n- Inline-Rendering")
    }

    // MARK: - Non-HTML input returns nil

    @Test("plain non-HTML text returns nil")
    func plainTextIsNil() {
        #expect(md("just text") == nil)
    }

    // MARK: - Regression fixes (entities, ol start, hard breaks, href)

    @Test("entities, ol start, hard breaks, and unsafe hrefs")
    func converterFixes() {
        #expect(md("<p>&#123;a&#125; &#x1F600;</p>") == "{a} 😀")
        #expect(md("<ol start=\"5\"><li>a</li><li>b</li></ol>") == "5. a\n6. b")
        #expect(md("<p>a<br>b</p>") == "a  \nb")
        #expect(md("<ul><li>a<br>b</li></ul>") == "- a  \n  b")
        #expect(md("<a href=\"/my file.md\">doc</a>") == "[doc](</my file.md>)")
    }

    @Test("literal text is escaped, real emphasis is not")
    func textEscaping() {
        #expect(md("<p>1. First</p>") == "1\\. First")
        #expect(md("<p># not a heading</p>") == "\\# not a heading")
        #expect(md("<p>*stars*</p>") == "\\*stars\\*")
        #expect(md("<p><em>x</em></p>") == "*x*")
    }

    @Test("block children inside li stay in the item")
    func listItemBlocks() {
        #expect(md("<li><p>First</p><p>Second</p></li>") == "- First\n\n  Second")
        #expect(md("<ul><li>Parent<div><ul><li>Child</li></ul></div></li></ul>") == "- Parent\n  - Child")
    }

    // Chromium strips the ul/ol wrapper on within-list copies (Claude/ChatGPT):
    // consecutive bare <li> become one tight bullet list, whitespace between
    // siblings must not split the run.
    @Test("bare li fragments become one tight bullet list")
    func bareListItems() {
        #expect(md("<meta charset='utf-8'><li class=\"x\"><strong>A:</strong> one</li>\n  <li>two</li>")
            == "- **A:** one\n- two")
    }
}
