//
//  DependencyChanges.swift
//  ChangeFacts
//
//  What a manifest change did to the project's dependencies, by name: adds, removes, bumps.
//
//  Created by David Sherlock on 9/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The dependencies a manifest change ADDS, REMOVES or BUMPS, by name and version, read from
/// the manifest's own declarations (never a lockfile's — a lockfile follows its manifest and
/// its thousands of transitive lines are not the change): package.json / composer.json
/// (JSON), requirements.txt, Pipfile, pyproject.toml (PEP 621 arrays and Poetry tables),
/// Package.swift (`.package(url:…)`), Cargo.toml (inline and sub-table forms), go.mod, Gemfile,
/// Podfile, Cartfile, pubspec.yaml, mix.exs, build.gradle(.kts), pom.xml. A manifest this cannot
/// read keeps the generic "dependency manifest" note. Facts: "adds left-pad 1.3.0, stripe ^12;
/// removes lodash; bumps axios 1.6 → 1.7". What the package IS is the reviewer's to find out.
public enum DependencyChanges {

    /// One dependency the change added, removed or bumped.
    public struct Fact: Equatable, Sendable {
        /// What happened to the dependency.
        public enum Kind: Sendable, Equatable { case added, removed, changed }
        /// Whether it was added, removed or bumped.
        public let kind: Kind
        /// The dependency's name as the manifest declares it.
        public let name: String
        /// The version spec after the change; nil for a removal, "" when the manifest gives none.
        public let version: String?
        /// The version spec before the change; nil for an addition.
        public let oldVersion: String?
        /// The fact as a phrase: "adds left-pad 1.3.0", "removes lodash", "bumps axios 1.6 → 1.7".
        public var summary: String {
            switch kind {
            case .added:
                if let version, !version.isEmpty {
                    return String(
                        localized: "adds \(name) \(version)", bundle: .module,
                        comment: "Dependency change: the first argument is the package name, the second its version")
                }
                return String(localized: "adds \(name)", bundle: .module, comment: "Dependency change: the argument is the package name")
            case .removed:
                return String(localized: "removes \(name)", bundle: .module, comment: "Dependency change: the argument is the package name")
            case .changed:
                return String(
                    localized: "bumps \(name) \(oldVersion ?? "?") → \(version ?? "?")", bundle: .module,
                    comment: "Dependency change: package name, then its old version → new version")
            }
        }
        /// Creates a fact from its parts.
        public init(kind: Kind, name: String, version: String?, oldVersion: String?) {
            self.kind = kind; self.name = name; self.version = version; self.oldVersion = oldVersion
        }
    }

    /// Lockfile names, whose changes follow their manifest and are never read as facts.
    public static let lockfiles: Set<String> = [
        "Package.resolved", "Podfile.lock", "Cartfile.resolved", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb",
        "Cargo.lock", "go.sum", "Gemfile.lock", "poetry.lock", "Pipfile.lock", "uv.lock", "composer.lock", "gradle.lockfile",
        "pubspec.lock", "mix.lock", "Gopkg.lock", "deno.lock",
    ]
    /// Whether `path`'s last component is one of ``lockfiles``.
    public static func isLockfile(_ path: String) -> Bool { lockfiles.contains((path as NSString).lastPathComponent) }

    /// name → version spec ("" when the manifest gives none), or nil when the file is not a
    /// manifest this reads.
    public static func declarations(in text: String, path: String) -> [String: String]? {
        let name = (path as NSString).lastPathComponent
        switch name {
        case "package.json": return json(text, keys: ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"])
        case "composer.json": return json(text, keys: ["require", "require-dev"])
        case "requirements.txt", "requirements-dev.txt", "constraints.txt": return requirements(text)
        case "Pipfile": return tomlTables(text, sections: ["packages", "dev-packages"])
        case "pyproject.toml": return pyproject(text)
        case "Package.swift": return packageSwift(text)
        case "Cargo.toml": return cargo(text)
        case "go.mod": return goMod(text)
        case "Gemfile": return calls(text, pattern: #"^\s*gem\s+['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]+)['"])?"#)
        case "Podfile": return calls(text, pattern: #"^\s*pod\s+['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]+)['"])?"#)
        case "Cartfile": return calls(text, pattern: #"^\s*(?:github|git|binary)\s+"([^"]+)"(?:\s+(.+))?$"#)
        case "pubspec.yaml": return pubspec(text)
        case "mix.exs": return mix(text)
        case "build.gradle", "build.gradle.kts": return gradle(text)
        case "pom.xml": return pom(text)
        default:
            if name.hasPrefix("requirements") && name.hasSuffix(".txt") { return requirements(text) }
            return nil
        }
    }

    /// The facts between two texts of one manifest; empty for a lockfile or an unread manifest.
    public static func facts(oldText: String?, newText: String, path: String) -> [Fact] {
        guard !isLockfile(path), let new = declarations(in: newText, path: path) else { return [] }
        let old = oldText.flatMap { declarations(in: $0, path: path) } ?? [:]
        var out: [Fact] = []
        for (name, version) in new.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            if let before = old[name] {
                if before != version { out.append(Fact(kind: .changed, name: name, version: version, oldVersion: before)) }
            } else {
                out.append(Fact(kind: .added, name: name, version: version, oldVersion: nil))
            }
        }
        for (name, before) in old.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) where new[name] == nil {
            out.append(Fact(kind: .removed, name: name, version: nil, oldVersion: before))
        }
        return out
    }

    /// "Dependencies: adds left-pad 1.3.0, stripe ^12; removes lodash; bumps axios 1.6 → 1.7".
    public static func headline(_ facts: [Fact]) -> String? {
        guard !facts.isEmpty else { return nil }
        func list(_ kind: Fact.Kind) -> String? {
            let items = facts.filter { $0.kind == kind }
            guard !items.isEmpty else { return nil }
            let shown = items.prefix(6).map { f -> String in
                switch kind {
                case .added: return f.name + ((f.version ?? "").isEmpty ? "" : " \(f.version!)")
                case .removed: return f.name
                case .changed: return "\(f.name) \(f.oldVersion ?? "?") → \(f.version ?? "?")"
                }
            }
            var names = shown.joined(separator: ", ")
            if items.count > 6 {
                names = String(
                    localized: "\(names) and \(items.count - 6) more", bundle: .module,
                    comment:
                        "Dependency list: the first argument is a comma-separated list of packages, the second how many more were left out")
            }
            switch kind {
            case .added:
                return String(
                    localized: "adds \(names)", bundle: .module,
                    comment: "Dependency summary clause: the argument is a list of added packages")
            case .removed:
                return String(
                    localized: "removes \(names)", bundle: .module,
                    comment: "Dependency summary clause: the argument is a list of removed packages")
            case .changed:
                return String(
                    localized: "bumps \(names)", bundle: .module,
                    comment: "Dependency summary clause: the argument is a list of packages with old → new versions")
            }
        }
        let clauses = [list(.added), list(.removed), list(.changed)].compactMap { $0 }.joined(separator: "; ")
        return String(
            localized: "Dependencies: \(clauses)", bundle: .module,
            comment: "Tool-tip on a changed dependency manifest; the argument is the semicolon-separated adds/removes/bumps clauses")
    }

    // MARK: - Parsers

    private static func json(_ text: String, keys: [String]) -> [String: String]? {
        guard let data = text.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        var out: [String: String] = [:]
        for key in keys {
            guard let table = obj[key] as? [String: Any] else { continue }
            for (name, v) in table { out[name] = (v as? String) ?? (v as? [String: Any]).flatMap { ($0["version"] as? String) } ?? "" }
        }
        return out
    }

    private static func requirements(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.components(separatedBy: "\n") {
            // a line that IS a comment is empty, not its remainder
            let line = (raw.range(of: "#").map { String(raw[..<$0.lowerBound]) } ?? raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("-") else { continue }
            guard let m = match(#"^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?\s*([<>=!~]=?[^;]*)?"#, line) else { continue }
            out[m[1]] = m[2].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// `[section]` tables of `name = "spec"` / `name = { version = "spec" }` lines.
    private static func tomlTables(_ text: String, sections: [String], prefixMatch: Bool = false) -> [String: String] {
        var out: [String: String] = [:]
        var active = false
        var subTable: String? = nil
        for raw in text.components(separatedBy: "\n") {
            // a line that IS a comment is empty, not its remainder
            let line = (raw.range(of: "#").map { String(raw[..<$0.lowerBound]) } ?? raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                let header = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).trimmingCharacters(in: .whitespaces)
                subTable = nil
                if let hit = sections.first(where: { header == $0 || (prefixMatch && header.hasPrefix($0 + ".")) }) {
                    active = true
                    if header != hit, header.hasPrefix(hit + ".") {
                        subTable = String(header.dropFirst(hit.count + 1)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }
                } else {
                    active = false
                }
                continue
            }
            guard active, let m = match(#"^([A-Za-z0-9_.-]+)\s*=\s*(.+)$"#, line) else { continue }
            if let sub = subTable {
                if m[1] == "version" {
                    out[sub] = m[2].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                } else if out[sub] == nil {
                    out[sub] = ""
                }
                continue
            }
            out[m[1]] = tomlSpec(m[2])
        }
        return out
    }

    private static func tomlSpec(_ value: String) -> String {
        if let v = match(#"version\s*=\s*"([^"]+)""#, value) { return v[1] }
        if value.contains("git") { return "git" }
        if value.contains("path") { return "path" }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    private static func pyproject(_ text: String) -> [String: String] {
        // Poetry's group tables are plain tables named by the group: list the ones present.
        let groups = matches(#"(?m)^\[(tool\.poetry\.group\.[^.\]]+\.dependencies)\]"#, text).map { $0[1] }
        var out = tomlTables(text, sections: ["tool.poetry.dependencies", "tool.poetry.dev-dependencies"] + groups)
        out["python"] = nil
        // PEP 621: dependencies = ["name>=1", "other"] (and optional-dependencies tables), across lines.
        for m in matches(#"(?s)dependencies\s*=\s*\[(.*?)\]"#, text) {
            for item in matches(#""([^"]+)""#, m[1]) {
                guard let d = match(#"^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?\s*([<>=!~]=?[^;]*)?"#, item[1]) else { continue }
                out[d[1]] = d[2].trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }

    private static func packageSwift(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for m in matches(#"(?s)\.package\(([^()]*(?:\([^()]*\)[^()]*)*)\)"#, text) {
            let args = m[1]
            if let url = match(#"url:\s*"([^"]+)""#, args) {
                let name = ((url[1] as NSString).lastPathComponent as NSString).deletingPathExtension
                let version =
                    match(#"(?:from|exact|branch|revision):\s*"([^"]+)""#, args)?[1]
                    ?? match(#""([^"]+)"\s*\.\.[<.]\s*"([^"]+)""#, args).map { "\($0[1])..<\($0[2])" }
                    ?? match(#"\.upToNext(?:Major|Minor)\(from:\s*"([^"]+)""#, args)?[1] ?? ""
                out[name] = version
            } else if let path = match(#"path:\s*"([^"]+)""#, args) {
                out[(path[1] as NSString).lastPathComponent] = "path"
            }
        }
        return out
    }

    private static func cargo(_ text: String) -> [String: String] {
        tomlTables(text, sections: ["dependencies", "dev-dependencies", "build-dependencies", "workspace.dependencies"], prefixMatch: true)
    }

    private static func goMod(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var inBlock = false
        for raw in text.components(separatedBy: "\n") {
            let line = (raw.range(of: "//").map { String(raw[..<$0.lowerBound]) } ?? raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("require (") { inBlock = true; continue }
            if inBlock, line.hasPrefix(")") { inBlock = false; continue }
            let body = line.hasPrefix("require ") ? String(line.dropFirst(8)) : (inBlock ? line : "")
            guard let m = match(#"^([^\s]+)\s+(v[^\s]+)"#, body.trimmingCharacters(in: .whitespaces)) else { continue }
            out[m[1]] = m[2]
        }
        return out
    }

    private static func calls(_ text: String, pattern: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let code = line.range(of: "#").map { String(line[..<$0.lowerBound]) } ?? line
            if let m = match(pattern, code) { out[m[1]] = m.count > 2 ? m[2].trimmingCharacters(in: .whitespaces) : "" }
        }
        return out
    }

    private static func pubspec(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var active = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.range(of: "#").map { String(raw[..<$0.lowerBound]) } ?? raw
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if !line.hasPrefix(" ") {
                active = line.hasPrefix("dependencies:") || line.hasPrefix("dev_dependencies:") || line.hasPrefix("dependency_overrides:")
                continue
            }
            guard active, let m = match(#"^  ([A-Za-z0-9_]+):\s*(.*)$"#, line) else { continue }
            let spec = m[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            out[m[1]] = spec.isEmpty ? "git/path" : spec
        }
        return out
    }

    private static func mix(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for m in matches(#"\{:([a-z0-9_]+),\s*(?:"([^"]+)"|(github|git|path):)"#, text) { out[m[1]] = m[2].isEmpty ? m[3] : m[2] }
        return out
    }

    private static func gradle(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for m in matches(
            #"(?m)^\s*(?:implementation|api|compileOnly|runtimeOnly|testImplementation|testRuntimeOnly|kapt|ksp|annotationProcessor|classpath)\s*\(?\s*['"]([^'":]+):([^'":]+)(?::([^'"]+))?['"]"#,
            text)
        {
            out["\(m[1]):\(m[2])"] = m[3]
        }
        return out
    }

    private static func pom(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for m in matches(#"(?s)<dependency>(.*?)</dependency>"#, text) {
            guard let g = match(#"<groupId>\s*([^<]+?)\s*</groupId>"#, m[1]),
                let a = match(#"<artifactId>\s*([^<]+?)\s*</artifactId>"#, m[1])
            else { continue }
            out["\(g[1]):\(a[1])"] = match(#"<version>\s*([^<]+?)\s*</version>"#, m[1])?[1] ?? ""
        }
        return out
    }

    // MARK: - Regex helpers (groups as strings; a missing group is "")

    /// Every match of `pattern` in `text` as its capture groups; see `RegexMatches`.
    public static func matches(_ pattern: String, _ text: String) -> [[String]] { RegexMatches.all(pattern, in: text) }
    /// The first match of `pattern` in `text`, or `nil`.
    public static func match(_ pattern: String, _ text: String) -> [String]? { RegexMatches.first(pattern, in: text) }
}
