//
//  HTMLToMarkdownConverter.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//

import Foundation

/// A lenient HTML→Markdown converter for the editor's smart-paste path.
///
/// Real-world clipboard HTML (from Claude, browsers, Word, Notion) is messy:
/// inline styles, stray `<span>`/`<div>`/`<meta>` wrappers, mixed-case tags,
/// and sometimes unclosed elements. This converter does NOT assume well-formed
/// XML — it runs a tolerant tag scanner with a small nesting stack, unwraps
/// unknown/styling-only tags, decodes entities, and collapses insignificant
/// whitespace. It prefers robustness over completeness.
///
/// Returns `nil` when the input has no convertible structure (no tags), so the
/// caller can fall back to the plain-text flavor.
enum HTMLToMarkdownConverter {

    static func markdown(fromHTML html: String) -> String? {
        var sawTag = false
        let root = parse(html, sawTag: &sawTag)
        guard sawTag else { return nil }
        let rendered = renderBlocks(root.children).htmlTrimmed
        return rendered.isEmpty ? nil : rendered
    }

    // MARK: - DOM

    private final class Node {
        let name: String            // "" for a text node, "#root" for the root
        var attrs: [String: String]
        var children: [Node] = []
        var text: String

        init(name: String, attrs: [String: String] = [:], text: String = "") {
            self.name = name
            self.attrs = attrs
            self.text = text
        }

        var isText: Bool { name.isEmpty }
    }

    private static let voidElements: Set<String> = [
        "br", "hr", "img", "input", "meta", "link", "source",
        "col", "area", "base", "wbr", "embed", "param", "track"
    ]

    // MARK: - Lenient parse

    private static func parse(_ html: String, sawTag: inout Bool) -> Node {
        let root = Node(name: "#root")
        var stack = [root]
        let chars = Array(html)
        let n = chars.count
        var i = 0

        func top() -> Node { stack[stack.count - 1] }
        func appendText(_ s: String) {
            if !s.isEmpty { top().children.append(Node(name: "", text: s)) }
        }

        while i < n {
            if chars[i] == "<" {
                // HTML comment: skip through "-->"
                if hasPrefix(chars, at: i, "<!--") {
                    var j = i + 4
                    while j + 2 < n, !(chars[j] == "-" && chars[j + 1] == "-" && chars[j + 2] == ">") {
                        j += 1
                    }
                    i = (j + 2 < n) ? j + 3 : n
                    continue
                }
                // Doctype / processing instruction: skip to ">"
                if i + 1 < n, chars[i + 1] == "!" || chars[i + 1] == "?" {
                    var j = i + 1
                    while j < n, chars[j] != ">" { j += 1 }
                    i = (j < n) ? j + 1 : n
                    continue
                }
                // Generic tag: read to the next ">"
                var j = i + 1
                while j < n, chars[j] != ">" { j += 1 }
                if j >= n {
                    // Unclosed "<": treat the remainder as literal text.
                    appendText(decodeHTMLEntities(String(chars[i..<n])))
                    break
                }
                let inner = String(chars[(i + 1)..<j])
                i = j + 1
                sawTag = true

                if inner.hasPrefix("/") {
                    let name = tagName(String(inner.dropFirst()))
                    if let idx = stack.lastIndex(where: { $0.name == name }), idx >= 1 {
                        stack.removeSubrange(idx...)
                    }
                } else {
                    let selfClose = inner.hasSuffix("/")
                    let body = selfClose ? String(inner.dropLast()) : inner
                    let name = tagName(body)
                    let node = Node(name: name, attrs: parseAttrs(body, name: name))
                    top().children.append(node)
                    if !selfClose && !voidElements.contains(name) {
                        stack.append(node)
                    }
                }
            } else {
                var j = i
                while j < n, chars[j] != "<" { j += 1 }
                appendText(decodeHTMLEntities(String(chars[i..<j])))
                i = j
            }
        }
        return root
    }

    private static func hasPrefix(_ chars: [Character], at i: Int, _ prefix: String) -> Bool {
        let p = Array(prefix)
        guard i + p.count <= chars.count else { return false }
        for k in 0..<p.count where chars[i + k] != p[k] { return false }
        return true
    }

    /// Leading tag name (letters/digits until whitespace or "/"), lowercased.
    private static func tagName(_ body: String) -> String {
        var name = ""
        for ch in body {
            if ch.isWhitespace || ch == "/" { break }
            name.append(ch)
        }
        return name.lowercased()
    }

    private static let attrRegex = try! NSRegularExpression(
        pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#
    )

    private static func parseAttrs(_ body: String, name: String) -> [String: String] {
        let rest = String(body.dropFirst(name.count))
        guard !rest.isEmpty else { return [:] }
        let ns = rest as NSString
        var attrs: [String: String] = [:]
        for m in attrRegex.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            var value = ""
            for group in 2...4 where m.range(at: group).location != NSNotFound {
                value = ns.substring(with: m.range(at: group))
                break
            }
            attrs[key] = decodeHTMLEntities(value)
        }
        return attrs
    }

    // MARK: - Block rendering

    private static func renderBlocks(_ children: [Node]) -> String {
        var blocks: [String] = []
        var inlineBuffer = ""

        func flush() {
            let trimmed = inlineBuffer.htmlTrimmed
            if !trimmed.isEmpty { blocks.append(trimmed) }
            inlineBuffer = ""
        }

        for child in children {
            if child.isText {
                inlineBuffer += renderInlineNode(child)
                continue
            }
            if let block = renderBlock(child) {
                flush()
                if !block.isEmpty { blocks.append(block) }
            } else {
                inlineBuffer += renderInlineNode(child)
            }
        }
        flush()
        return blocks.joined(separator: "\n\n")
    }

    /// Renders a block-level element, or returns `nil` when `node` is not a
    /// block (so the caller folds it into the surrounding inline paragraph).
    private static func renderBlock(_ node: Node) -> String? {
        switch node.name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(node.name.dropFirst()) ?? 1
            return String(repeating: "#", count: level) + " "
                + renderInlineChildren(node.children).htmlTrimmed
        case "p":
            return renderInlineChildren(node.children).htmlTrimmed
        case "hr":
            return "----"
        case "ul":
            return renderList(node, ordered: false, depth: 0)
        case "ol":
            return renderList(node, ordered: true, depth: 0)
        case "li":
            return renderListItem(node, ordered: false, number: 1, depth: 0)
        case "blockquote":
            let inner = renderBlocks(node.children)
            let lines = inner.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }
            return lines.joined(separator: "\n")
        case "pre":
            return renderPre(node)
        case "table":
            return renderTable(node)
        case "div":
            return renderBlocks(node.children)
        default:
            return nil
        }
    }

    private static func renderList(_ node: Node, ordered: Bool, depth: Int) -> String {
        var items: [String] = []
        var number = 0
        for child in node.children where child.name == "li" {
            number += 1
            items.append(renderListItem(child, ordered: ordered, number: number, depth: depth))
        }
        return items.joined(separator: "\n")
    }

    private static func renderListItem(_ li: Node, ordered: Bool, number: Int, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)

        var inlineChildren: [Node] = []
        var nestedLists: [Node] = []
        for child in li.children {
            if child.name == "ul" || child.name == "ol" {
                nestedLists.append(child)
            } else {
                inlineChildren.append(child)
            }
        }

        let marker: String
        if let box = findCheckbox(li) {
            marker = isChecked(box) ? "- [x] " : "- [ ] "
        } else {
            marker = ordered ? "\(number). " : "- "
        }

        var line = indent + marker + renderInlineChildren(inlineChildren).htmlTrimmed
        for list in nestedLists {
            let sub = renderList(list, ordered: list.name == "ol", depth: depth + 1)
            if !sub.isEmpty { line += "\n" + sub }
        }
        return line
    }

    private static func renderPre(_ node: Node) -> String {
        let source = firstDescendant(node, named: "code") ?? node
        var language = ""
        if let cls = source.attrs["class"] {
            for token in cls.split(separator: " ") where token.hasPrefix("language-") {
                language = String(token.dropFirst("language-".count))
                break
            }
        }
        var code = rawText(source)
        if code.hasPrefix("\n") { code.removeFirst() }
        if code.hasSuffix("\n") { code.removeLast() }
        return "```\(language)\n\(code)\n```"
    }

    private static func renderTable(_ node: Node) -> String {
        let trs = descendants(node, named: "tr")
        var rows: [[String]] = []
        for tr in trs {
            var cells: [String] = []
            for cell in tr.children where cell.name == "td" || cell.name == "th" {
                let text = renderInlineChildren(cell.children).htmlTrimmed
                    .replacingOccurrences(of: "|", with: #"\|"#)
                    .replacingOccurrences(of: "\n", with: " ")
                cells.append(text)
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        guard !rows.isEmpty else { return "" }

        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return "" }
        func pad(_ row: [String]) -> [String] {
            row + Array(repeating: "", count: max(0, columns - row.count))
        }

        var lines: [String] = []
        lines.append("| " + pad(rows[0]).joined(separator: " | ") + " |")
        lines.append("|" + Array(repeating: "---", count: columns).joined(separator: "|") + "|")
        for row in rows.dropFirst() {
            lines.append("| " + pad(row).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Inline rendering

    private static func renderInlineChildren(_ children: [Node]) -> String {
        children.map(renderInlineNode).joined()
    }

    private static func renderInlineNode(_ node: Node) -> String {
        if node.isText { return collapseWhitespace(node.text) }
        switch node.name {
        case "strong", "b":
            return "**" + renderInlineChildren(node.children) + "**"
        case "em", "i":
            return "*" + renderInlineChildren(node.children) + "*"
        case "del", "s", "strike":
            return "~~" + renderInlineChildren(node.children) + "~~"
        case "mark":
            return "==" + renderInlineChildren(node.children) + "=="
        case "code":
            return "`" + rawText(node) + "`"
        case "br":
            return "\n"
        case "a":
            let inner = renderInlineChildren(node.children)
            let href = node.attrs["href"] ?? ""
            return href.isEmpty ? inner : "[\(inner)](\(href))"
        case "input":
            return ""   // checkboxes are handled at the list-item level
        default:
            // Unknown / styling-only tags (span, font, sup, etc.) → unwrap.
            return renderInlineChildren(node.children)
        }
    }

    // MARK: - Tree helpers

    private static func findCheckbox(_ node: Node) -> Node? {
        for child in node.children {
            if child.name == "input", child.attrs["type"]?.lowercased() == "checkbox" {
                return child
            }
            if let found = findCheckbox(child) { return found }
        }
        return nil
    }

    private static func isChecked(_ input: Node) -> Bool {
        guard let value = input.attrs["checked"] else { return false }
        return value.isEmpty || value.lowercased() == "checked" || value.lowercased() == "true"
    }

    private static func firstDescendant(_ node: Node, named name: String) -> Node? {
        for child in node.children {
            if child.name == name { return child }
            if let found = firstDescendant(child, named: name) { return found }
        }
        return nil
    }

    private static func descendants(_ node: Node, named name: String) -> [Node] {
        var result: [Node] = []
        for child in node.children {
            if child.name == name { result.append(child) }
            result.append(contentsOf: descendants(child, named: name))
        }
        return result
    }

    /// Concatenates the raw (un-collapsed) text of a node's subtree — used for
    /// code spans and fenced blocks where whitespace is significant.
    private static func rawText(_ node: Node) -> String {
        if node.isText { return node.text }
        return node.children.map(rawText).joined()
    }

    // MARK: - Whitespace & entities

    /// Collapses runs of insignificant whitespace to a single space, preserving
    /// a single leading/trailing space so inline runs stay separated.
    private static func collapseWhitespace(_ s: String) -> String {
        var out = ""
        var pendingSpace = false
        for ch in s {
            if ch.isWhitespace {
                pendingSpace = true
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(ch)
        }
        if pendingSpace { out.append(" ") }
        return out
    }

    private static func decodeHTMLEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

private extension String {
    var htmlTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
