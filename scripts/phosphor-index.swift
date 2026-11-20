// Builds the icon library's index from Phosphor's stylesheets: name → Unicode code point, one list shared by the
// Bold and Fill fonts (checked: both styles must give the same code point for every name).
//   swift scripts/phosphor-index.swift <bold/style.css> <fill/style.css> Packaging/Resources/phosphor-icons.json
import Foundation

func index(_ path: String, style: String) throws -> [String: Int] {
    let css = try String(contentsOfFile: path, encoding: .utf8)
    // .ph-bold.ph-acorn:before {\n  content: "\eb9a";\n}
    let pattern = try NSRegularExpression(pattern: #"\.ph-\#(style)\.ph-([a-z0-9-]+):before\s*\{\s*content:\s*"\\([0-9a-f]+)""#)
    var result: [String: Int] = [:]
    for match in pattern.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
        let name = String(css[Range(match.range(at: 1), in: css)!])
        let code = Int(css[Range(match.range(at: 2), in: css)!], radix: 16)!
        result[name] = code
    }
    return result
}

let args = CommandLine.arguments
let bold = try index(args[1], style: "bold")
let fill = try index(args[2], style: "fill")
precondition(bold.count > 1000, "too few icons in \(args[1])")
precondition(bold == fill, "bold and fill disagree on names or code points")
let sorted = bold.keys.sorted().map { ["name": $0, "code": bold[$0]!] as [String: Any] }
let data = try JSONSerialization.data(withJSONObject: sorted, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: args[3]))
print("Wrote \(sorted.count) icons to \(args[3])")
