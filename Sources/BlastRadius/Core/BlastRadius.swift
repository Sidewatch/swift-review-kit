//
//  BlastRadius.swift
//  BlastRadius
//
//  "What's the ripple of this change?" — for each symbol touched by a diff, find
//  its callers and covering tests across a project. Deterministic whole-word
//  search (same spirit as Find Usages). The human does the reasoning.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Finds the project-wide impact of the symbols touched by a change.
///
/// The symbol-resolution step (mapping changed lines to their enclosing symbol
/// names) is injected via a closure, so this stays language- and parser-agnostic —
/// wire it to tree-sitter breadcrumbs, ctags, an LSP, or anything else.
public enum BlastRadius {

    /// The built-in noise list skipped while walking the project.
    public static let defaultSkip: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm", "Pods",
        "DerivedData", "dist", "build", "__pycache__", ".next", ".cache", "vendor",
    ]

    /// Directory names skipped while walking the project. Defaults to ``defaultSkip``; assign to
    /// override (a project with real sources in `dist/` needs it off the list).
    ///
    /// Lock-guarded like `FileTools.SkippedDirs.names`: written on the main thread, read by
    /// walks on background queues. The lock makes access safe, not meaningful — set it at
    /// start-up so a walk cannot observe half of a settings change.
    public static var skip: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return storedSkip }
        set { lock.lock(); defer { lock.unlock() }; storedSkip = newValue }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedSkip: Set<String> = defaultSkip

    /// Source file extensions searched for usages.
    public static let exts: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "py", "rb", "php", "go", "rs",
        "java", "c", "cpp", "cc", "h", "hpp", "cs", "kt", "dart", "lua", "scala",
    ]

    /// Analyses the impact of the changed lines (1-based) in `file` across the project at `root`.
    ///
    /// - Parameter enclosingSymbol: Given a character offset and the file text, returns the
    ///   breadcrumb trail of enclosing symbols, innermost **last**.
    /// - Returns: One ``SymbolImpact`` per changed symbol that has any usages.
    /// - Note: Blocking — reads and walks the whole project tree. Call off the main thread.
    public static func analyze(file: URL, root: URL, changedLines: Set<Int>,
                               enclosingSymbol: (_ charOffset: Int, _ text: String) -> [String]) -> [SymbolImpact] {
        analyze(files: [(file, changedLines)], root: root, enclosingSymbol: enclosingSymbol)[file] ?? []
    }

    /// Batch form of ``analyze(file:root:changedLines:enclosingSymbol:)`` for a whole changeset:
    /// the tree is walked and every file read ONCE, with all symbols matched in that pass —
    /// per-file calls re-pay the full walk per symbol, which takes minutes on large changesets.
    ///
    /// - Returns: Each input file's impacts, as the per-file call gives them; unreadable files get `[]`.
    /// - Note: Blocking — walks and reads the whole project tree. Call off the main thread.
    public static func analyze(files: [(file: URL, changedLines: Set<Int>)], root: URL,
                               enclosingSymbol: (_ charOffset: Int, _ text: String) -> [String]) -> [URL: [SymbolImpact]] {
        var perFileSymbols: [(URL, [String])] = []
        var allSymbols: [String] = []   // ordered, deduped across files
        for (file, changedLines) in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                perFileSymbols.append((file, []))
                continue
            }
            let symbols = changedSymbols(content: content, changedLines: changedLines, enclosingSymbol: enclosingSymbol)
            perFileSymbols.append((file, symbols))
            for name in symbols where !allSymbols.contains(name) { allSymbols.append(name) }
        }
        let hits = allSymbols.isEmpty ? [:] : usages(of: allSymbols, in: sourceFiles(root), root: root)
        var out: [URL: [SymbolImpact]] = [:]
        for (file, symbols) in perFileSymbols {
            out[file] = symbols.compactMap { name -> SymbolImpact? in
                guard let (callers, tests) = hits[name], !callers.isEmpty || !tests.isEmpty else { return nil }
                return SymbolImpact(symbol: name, callers: callers, tests: tests)
            }
        }
        return out
    }

    /// Project-wide references to one named symbol — the "Find References" entry point.
    /// NAME-based, not semantic: it matches every whole-word `name` (fields, strings) and cannot
    /// tell same-named methods apart, so present it as "References", not a call hierarchy.
    ///
    /// - Returns: Callers and covering tests, or nil when nothing matches.
    /// - Note: Blocking — walks and reads the project tree. Call off the main thread.
    public static func references(to name: String, root: URL) -> SymbolImpact? {
        guard name.count > 1 else { return nil }
        let (callers, tests) = usages(of: name, in: sourceFiles(root), root: root)
        guard !callers.isEmpty || !tests.isEmpty else { return nil }
        return SymbolImpact(symbol: name, callers: callers, tests: tests)
    }

    /// Distinct innermost enclosing symbols of the changed lines.
    private static func changedSymbols(content: String, changedLines: Set<Int>,
                                       enclosingSymbol: (Int, String) -> [String]) -> [String] {
        let ns = content as NSString
        var seen: [String] = []
        for line in changedLines.sorted() {
            let crumbs = enclosingSymbol(charOffset(line, ns), content)
            if let name = crumbs.last, name.count > 1, !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    /// Converts a 1-based git line number to a UTF-16 offset. Counts lines the way
    /// git does — by `\n` only — never by Unicode separators (U+2028/U+2029/U+0085),
    /// which `NSString.lineRange` treats as breaks and would skew the offset.
    private static func charOffset(_ line: Int, _ ns: NSString) -> Int {
        var cur = 1, idx = 0
        while cur < line, idx < ns.length {
            if ns.character(at: idx) == 0x0A { cur += 1 }
            idx += 1
        }
        return min(idx, ns.length)
    }

    /// Whole-word searches `files` for `name`, splitting hits into (callers, tests).
    /// Skips files ≥ 500 KB and stops past 300 total hits.
    private static func usages(of name: String, in files: [URL], root: URL) -> ([BlastLocation], [BlastLocation]) {
        usages(of: [name], in: files, root: root)[name] ?? ([], [])
    }

    /// One search slot per symbol: its precompiled regex, the hits so far, and
    /// whether its per-symbol 300-hit cap has been reached.
    private struct SymbolSlot {
        let name: String
        let regex: NSRegularExpression
        var callers: [BlastLocation] = []
        var tests: [BlastLocation] = []
        var capped = false
    }

    /// Whole-word searches `files` for every symbol in `names` in a SINGLE pass —
    /// each file is read and line-split once, and every symbol's regex runs
    /// against each already-split line. Skips files ≥ 500 KB; each symbol keeps
    /// its own past-300-hits stop (matching the per-symbol search exactly).
    private static func usages(of names: [String], in files: [URL], root: URL) -> [String: ([BlastLocation], [BlastLocation])] {
        // `\b` next to a non-word character inverts its meaning (\b==\b never matches
        // ` a == b `), so only anchor the ends of the name that are word characters —
        // fully non-word names (operators like `==`) fall back to a literal search.
        func isWordChar(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c == "_" || c.isLetter || c.isNumber
        }
        var slots: [SymbolSlot] = names.compactMap { name in
            let pattern = (isWordChar(name.first) ? "\\b" : "")
                + NSRegularExpression.escapedPattern(for: name)
                + (isWordChar(name.last) ? "\\b" : "")
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return SymbolSlot(name: name, regex: re)
        }
        fileLoop: for f in files {
            guard let content = try? String(contentsOf: f, encoding: .utf8), content.utf8.count < 500_000 else { continue }
            let isTest = isTestFile(f, root: root)
            let relPath = rel(f, root)
            for (i, line) in content.components(separatedBy: "\n").enumerated() {
                let r = NSRange(location: 0, length: (line as NSString).length)
                var allCapped = true
                for s in slots.indices {
                    guard !slots[s].capped else { continue }
                    allCapped = false
                    guard slots[s].regex.firstMatch(in: line, range: r) != nil else { continue }
                    let loc = BlastLocation(file: relPath, line: i + 1, text: line.trimmingCharacters(in: .whitespacesAndNewlines), absPath: f.path, isTest: isTest)
                    if isTest { slots[s].tests.append(loc) } else { slots[s].callers.append(loc) }
                    if slots[s].callers.count + slots[s].tests.count > 300 { slots[s].capped = true }
                }
                if allCapped { break fileLoop }
            }
        }
        var out: [String: ([BlastLocation], [BlastLocation])] = [:]
        for slot in slots { out[slot.name] = (slot.callers, slot.tests) }
        return out
    }

    /// Classifies from the root-relative path only (so the checkout location can't
    /// flip it) and matches whole path components / filename word boundaries — never
    /// raw substrings, which would hit "latest", "InspectorPanel", "PerspectiveView"…
    private static func isTestFile(_ f: URL, root: URL) -> Bool {
        let words = ["test", "tests", "spec", "specs"]
        let dirNames: Set<String> = ["test", "tests", "__tests__", "spec", "specs", "testing"]
        let parts = rel(f, root).split(separator: "/")
        for dir in parts.dropLast() where dirNames.contains(dir.lowercased()) { return true }
        let stem = f.deletingPathExtension().lastPathComponent
        // CamelCase suffixes (MyTests, FooSpec) — capitalized, so "latest" can't match.
        if ["Test", "Tests", "Spec", "Specs"].contains(where: { stem.hasSuffix($0) }) { return true }
        let lower = stem.lowercased()
        for word in words {
            if lower == word { return true }
            for sep in [".", "_", "-"] where lower.hasSuffix(sep + word) || lower.hasPrefix(word + sep) { return true }
        }
        return false
    }

    /// Walks `root` for source files (by ``exts``), pruning ``skip`` directories
    /// and capping the walk at 6000 files.
    private static func sourceFiles(_ root: URL) -> [URL] {
        var out: [URL] = []
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        for case let url as URL in en {
            if skip.contains(url.lastPathComponent) { en.skipDescendants(); continue }
            if exts.contains(url.pathExtension.lowercased()) { out.append(url) }
            if out.count > 6000 { break }
        }
        return out
    }

    /// Root-relative path of `url`, or just its filename if it's outside `root`.
    private static func rel(_ url: URL, _ root: URL) -> String {
        // Resolve symlinks on both sides — the enumerator can yield /private/var/…
        // for a /var/… root, which would otherwise defeat the prefix check.
        let u = url.resolvingSymlinksInPath().path, r = root.resolvingSymlinksInPath().path
        return u.hasPrefix(r) ? String(u.dropFirst(r.count).drop(while: { $0 == "/" })) : url.lastPathComponent
    }
}
