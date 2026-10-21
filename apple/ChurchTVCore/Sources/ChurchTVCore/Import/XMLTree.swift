import Foundation

/// A tiny namespace-agnostic XML tree built with `XMLParser` (local names only). Enough for the Office Open XML parts we read.
/// External entities are never resolved. Depth and node count are capped so a hostile file cannot exhaust memory.
final class XNode {
    let name: String
    var attrs: [String: String]
    var children: [XNode] = []
    var text = ""
    init(name: String, attrs: [String: String]) { self.name = name; self.attrs = attrs }

    /// Attribute by local name (`embed` finds `r:embed`).
    func attr(_ local: String) -> String? {
        if let v = attrs[local] { return v }
        for (k, v) in attrs where k.hasSuffix(":" + local) { return v }
        return nil
    }
    /// Namespaced attribute only (`r:id`, not `id`).
    func prefixedAttr(_ local: String) -> String? {
        for (k, v) in attrs where k.hasSuffix(":" + local) { return v }
        return nil
    }
    func child(_ n: String) -> XNode? { children.first { $0.name == n } }
    func kids(_ n: String) -> [XNode] { children.filter { $0.name == n } }
    func path(_ names: String...) -> XNode? {
        var cur: XNode? = self
        for n in names { cur = cur?.child(n); if cur == nil { return nil } }
        return cur
    }
    /// First descendant (depth first) with this local name.
    func first(_ n: String) -> XNode? {
        for c in children { if c.name == n { return c }; if let f = c.first(n) { return f } }
        return nil
    }
    func all(_ n: String) -> [XNode] {
        var r: [XNode] = []
        for c in children { if c.name == n { r.append(c) }; r += c.all(n) }
        return r
    }
}

final class XMLTreeParser: NSObject, XMLParserDelegate {
    static let maxDepth = 120
    static let maxNodes = 400_000
    private var stack: [XNode] = []
    private var root: XNode?
    private var count = 0
    private var failed = false

    static func parse(_ data: Data) -> XNode? {
        let p = XMLParser(data: data)
        let h = XMLTreeParser()
        p.delegate = h
        p.shouldProcessNamespaces = true
        p.shouldResolveExternalEntities = false
        guard p.parse(), !h.failed else { return h.root }   // a partly read tree is still useful
        return h.root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        count += 1
        if count > Self.maxNodes || stack.count >= Self.maxDepth { failed = true; parser.abortParsing(); return }
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let n = XNode(name: local, attrs: attributeDict)
        if let top = stack.last { top.children.append(n) } else { root = n }
        stack.append(n)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
}
