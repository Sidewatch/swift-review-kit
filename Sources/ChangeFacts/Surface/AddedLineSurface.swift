//
//  AddedLineSurface.swift
//  ChangeFacts
//
//  What a change adds to the program's surface: environment variables it starts reading, hosts
//  it starts calling.
//
//  Created by David Sherlock on 9/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The environment variables a change starts READING and the hosts it starts CALLING, on the
/// lines it added, in code files only — facts about the program's edges. Names and hosts that
/// the file already used at HEAD (anywhere in it: a moved line adds nothing) are not reported;
/// an untracked file reports all of its own. Comments are blanked first in the file's own
/// syntax, so a URL in a doc comment is not a call. Loopback, example and schema hosts are
/// never reported; manifests, lockfiles, prose, tests and vendored trees are never scanned.
public enum AddedLineSurface {

    /// The environment names and hosts a text uses, each sorted.
    public struct Findings: Equatable, Sendable {
        /// Environment variable names read, e.g. `STRIPE_KEY`.
        public let envNames: [String]
        /// Hosts called, lowercased, e.g. `api.stripe.com`.
        public let hosts: [String]
        /// True when neither a name nor a host was found.
        public var isEmpty: Bool { envNames.isEmpty && hosts.isEmpty }
        /// Creates findings from already-sorted lists.
        public init(envNames: [String], hosts: [String]) { self.envNames = envNames; self.hosts = hosts }
    }

    /// One regex per language's environment read; capture group 1 is the variable name.
    public static let envPatterns: [String] = [
        #"process\.env\.([A-Z][A-Z0-9_]*)"#, #"process\.env\[['"]([A-Z][A-Z0-9_]*)['"]\]"#,
        #"import\.meta\.env\.([A-Z][A-Z0-9_]*)"#, #"Deno\.env\.get\(['"]([A-Z][A-Z0-9_]*)['"]"#, #"Bun\.env\.([A-Z][A-Z0-9_]*)"#,
        #"os\.environ(?:\.get)?\s*[\[(]\s*['"]([A-Z][A-Z0-9_]*)['"]"#, #"os\.getenv\(\s*['"]([A-Z][A-Z0-9_]*)['"]"#,
        #"\bENV(?:\.fetch)?\s*[\[(]\s*['"]([A-Z][A-Z0-9_]*)['"]"#, #"\bgetenv\(\s*['"]([A-Z][A-Z0-9_]*)['"]"#,
        #"os\.Getenv\(\s*"([A-Z][A-Z0-9_]*)""#, #"os\.LookupEnv\(\s*"([A-Z][A-Z0-9_]*)""#,
        #"System\.getenv\(\s*"([A-Z][A-Z0-9_]*)""#, #"Environment\.GetEnvironmentVariable\(\s*"([A-Z][A-Z0-9_]*)""#,
        #"processInfo\.environment\[\s*"([A-Z][A-Z0-9_]*)""#, #"std::env::var(?:_os)?\(\s*"([A-Z][A-Z0-9_]*)""#,
        #"System\.get_env\(\s*"([A-Z][A-Z0-9_]*)""#, #"\benv\(\s*['"]([A-Z][A-Z0-9_]*)['"]"#, #"\$_ENV\[\s*['"]([A-Z][A-Z0-9_]*)['"]"#,
        #"\$\{\{?\s*([A-Z][A-Z0-9_]*)\s*\}\}?"#,
    ]
    /// An `http(s)://` URL; capture group 1 is its host.
    public static let hostPattern = #"https?://([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+)"#
    /// Loopback, example and schema hosts that appear in code without being called.
    public static let ignoredHosts: Set<String> = ["localhost", "example.com", "example.org", "example.net", "www.w3.org", "w3.org", "schema.org", "json-schema.org",
                                            "schemas.microsoft.com", "www.apple.com", "purl.org", "xmlns.com", "www.iana.org", "spec.openapis.org", "json.schemastore.org"]

    /// Every environment name and host `text` uses (comments blanked in `path`'s syntax).
    public static func scan(_ text: String, path: String) -> Findings {
        let dialect = DestructiveSQL.dialect(forPath: path) ?? .other
        let clean = DestructiveSQL.stripped(text, dialect: dialect)
        var names = Set<String>(), hosts = Set<String>()
        for p in envPatterns { for m in RegexMatches.all(p, in: clean) { names.insert(m[1]) } }
        for m in RegexMatches.all(hostPattern, in: clean) {
            let host = m[1].lowercased()
            guard !ignoredHosts.contains(host), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), host != "127.0.0.1", host != "0.0.0.0" else { continue }
            if host.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil, host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { continue }
            hosts.insert(host)
        }
        return Findings(envNames: names.sorted(), hosts: hosts.sorted())
    }

    /// What `newText`'s ADDED lines use that `oldText` did not, anywhere. `addedLines` nil:
    /// every line is added (an untracked file).
    public static func findings(oldText: String?, newText: String, path: String, addedLines: Set<Int>?) -> Findings {
        guard isScannable(path) else { return Findings(envNames: [], hosts: []) }
        let addedText: String
        if let addedLines {
            addedText = newText.components(separatedBy: "\n").enumerated().filter { addedLines.contains($0.offset + 1) }.map(\.element).joined(separator: "\n")
        } else { addedText = newText }
        let fresh = scan(addedText, path: path)
        let before = oldText.map { scan($0, path: path) } ?? Findings(envNames: [], hosts: [])
        return Findings(envNames: fresh.envNames.filter { !before.envNames.contains($0) }, hosts: fresh.hosts.filter { !before.hosts.contains($0) })
    }

    /// Code files only: not manifests, lockfiles, prose, tests or vendored trees.
    public static func isScannable(_ path: String) -> Bool {
        DestructiveSQL.dialect(forPath: path) != nil && !DestructiveSQL.isSkippedPath(path) && !DependencyManifest.isManifest(path)
    }

    /// "Reads new environment variables: STRIPE_KEY, SENTRY_DSN · Calls new hosts: api.stripe.com".
    public static func tooltip(_ f: Findings) -> String? {
        guard !f.isEmpty else { return nil }
        func shown(_ items: [String]) -> String {
            let list = items.prefix(8).joined(separator: ", ")
            guard items.count > 8 else { return list }
            return String(localized: "\(list) and \(items.count - 8) more", bundle: .module,
                          comment: "A shortened list: the first argument is a comma-separated list, the second how many more were left out")
        }
        var parts: [String] = []
        if !f.envNames.isEmpty {
            let names = shown(f.envNames)
            parts.append(f.envNames.count == 1
                ? String(localized: "Reads new environment variable: \(names)", bundle: .module, comment: "Tool-tip on a changed code file; the argument is one environment variable name")
                : String(localized: "Reads new environment variables: \(names)", bundle: .module, comment: "Tool-tip on a changed code file; the argument is a comma-separated list of environment variable names"))
        }
        if !f.hosts.isEmpty {
            let hosts = shown(f.hosts)
            parts.append(f.hosts.count == 1
                ? String(localized: "Calls new host: \(hosts)", bundle: .module, comment: "Tool-tip on a changed code file; the argument is one host name the code now calls")
                : String(localized: "Calls new hosts: \(hosts)", bundle: .module, comment: "Tool-tip on a changed code file; the argument is a comma-separated list of host names the code now calls"))
        }
        return parts.joined(separator: " · ")
    }

}
