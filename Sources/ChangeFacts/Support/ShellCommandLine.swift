//
//  ShellCommandLine.swift
//  ChangeFacts
//
//  A shell command line as the shell would run it: its segments, its words, and the tool each
//  segment invokes once the wrappers agents type are peeled.
//
//  Created by David Sherlock on 9/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A shell command line read the way a shell runs it.
///
/// `segments(of:)` splits on `&&`, `||`, `;`, `|` and newlines outside quotes, keeping a heredoc
/// with the segment that opened it and joining backslash-continued lines. `words(_:)` splits one
/// segment into its words with quotes removed. `invocation(of:)` peels `sudo`, `time`, `env`,
/// environment assignments and the runners agents type (`npx`, `bunx`, `pnpm dlx`, `bundle exec`,
/// `poetry run`, `uv run`, `docker compose exec svc`, `docker exec -it name`, `kubectl exec pod --`,
/// `sh -c '…'`, `ssh host '…'`) and names the tool left at the front — the script for an
/// interpreter (`python manage.py migrate` is `manage.py`), the binary for everything else.
public enum ShellCommandLine {

    /// One command a segment invokes, once the wrappers around it are peeled.
    public struct Invocation: Equatable, Sendable {
        /// "psql", "prisma", "manage.py" — the last path component of the tool.
        public let tool: String
        /// The words after the tool, quotes removed.
        public let arguments: [String]
        /// The heredoc body the segment carried, without its opening line, or `nil`.
        public let heredoc: String?

        public init(tool: String, arguments: [String], heredoc: String?) {
            self.tool = tool
            self.arguments = arguments
            self.heredoc = heredoc
        }
    }

    // MARK: - Segments

    /// The segments a shell would run, split on `&&`, `||`, `;`, `|` and newlines outside
    /// quotes; a heredoc (`<<EOF` … `EOF`) stays with the segment that opened it; a line ending
    /// in a backslash continues into the next.
    ///
    /// - Parameter command: The command line as the agent ran it.
    /// - Returns: The trimmed, non-empty segments in order.
    public static func segments(of command: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inSingle = false, inDouble = false
        var heredocTag: String? = nil
        var heredocPending: String? = nil
        var continued = false
        let lines = command.components(separatedBy: "\n")
        for (n, rawLine) in lines.enumerated() {
            // A line continued with a trailing backslash joins the next, its indentation dropped.
            let line = continued ? String(rawLine.drop(while: { $0 == " " || $0 == "\t" })) : rawLine
            continued = false
            if let tag = heredocTag {
                current += "\n" + line
                if line.trimmingCharacters(in: CharacterSet(charactersIn: "\t")) == tag {
                    heredocTag = nil
                    if n < lines.count - 1 { out.append(current); current = "" }   // the command ended with its body
                }
                continue
            }
            var i = line.startIndex
            while i < line.endIndex {
                let c = line[i]
                let next = line.index(after: i) < line.endIndex ? line[line.index(after: i)] : nil
                if inSingle { current.append(c); if c == "'" { inSingle = false }; i = line.index(after: i); continue }
                if inDouble {
                    current.append(c)
                    if c == "\\", let next { current.append(next); i = line.index(i, offsetBy: 2); continue }
                    if c == "\"" { inDouble = false }
                    i = line.index(after: i); continue
                }
                if c == "'" { inSingle = true; current.append(c); i = line.index(after: i); continue }
                if c == "\"" { inDouble = true; current.append(c); i = line.index(after: i); continue }
                if c == "\\", let next { current.append(c); current.append(next); i = line.index(i, offsetBy: 2); continue }
                if c == "<", next == "<" {
                    let (tag, end) = heredocOpener(in: line, at: i)
                    if !tag.isEmpty { heredocPending = tag }
                    current += String(line[i..<end])
                    i = end
                    continue
                }
                if (c == "&" && next == "&") || (c == "|" && next == "|") {
                    out.append(current); current = ""
                    i = line.index(i, offsetBy: 2); continue
                }
                if c == ";" || c == "|" {
                    out.append(current); current = ""
                    i = line.index(after: i); continue
                }
                current.append(c)
                i = line.index(after: i)
            }
            if let pending = heredocPending { heredocTag = pending; heredocPending = nil; continue }
            if n < lines.count - 1, !inSingle, !inDouble, heredocTag == nil {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if trimmed.hasSuffix("\\") { current = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) + " "; continued = true; continue }   // a continued line
                out.append(current); current = ""
            } else if inSingle || inDouble {
                current.append("\n")
            }
        }
        out.append(current)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The tag of a heredoc opener starting at `i` (`<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"`,
    /// `<< EOF`) and the index just past it. The body starts on the next line.
    private static func heredocOpener(in line: String, at i: String.Index) -> (tag: String, end: String.Index) {
        var j = line.index(i, offsetBy: 2)
        if j < line.endIndex, line[j] == "-" { j = line.index(after: j) }
        var tag = ""
        var k = j
        while k < line.endIndex, line[k] == " " { k = line.index(after: k) }
        if k < line.endIndex, line[k] == "'" || line[k] == "\"" {
            let q = line[k]; k = line.index(after: k)
            while k < line.endIndex, line[k] != q { tag.append(line[k]); k = line.index(after: k) }
            if k < line.endIndex { k = line.index(after: k) }
        } else {
            while k < line.endIndex, line[k].isLetter || line[k].isNumber || line[k] == "_" { tag.append(line[k]); k = line.index(after: k) }
        }
        return (tag, k)
    }

    // MARK: - Words

    /// The words of one shell line: quotes group, backslash escapes, and the quotes are removed.
    /// An empty quoted string is a word.
    public static func words(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inSingle = false, inDouble = false, hadQuote = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inSingle { if c == "'" { inSingle = false } else { current.append(c) }; i = line.index(after: i); continue }
            if inDouble {
                if c == "\\", line.index(after: i) < line.endIndex { i = line.index(after: i); current.append(line[i]); i = line.index(after: i); continue }
                if c == "\"" { inDouble = false } else { current.append(c) }
                i = line.index(after: i); continue
            }
            switch c {
            case "'": inSingle = true; hadQuote = true
            case "\"": inDouble = true; hadQuote = true
            case "\\":
                if line.index(after: i) < line.endIndex { i = line.index(after: i); current.append(line[i]) }
            case " ", "\t":
                if !current.isEmpty || hadQuote { words.append(current); current = ""; hadQuote = false }
            default: current.append(c)
            }
            i = line.index(after: i)
        }
        if !current.isEmpty || hadQuote { words.append(current) }
        return words
    }

    // MARK: - The tool at the front

    /// The tool a segment invokes with its arguments, once environment assignments, `sudo`,
    /// `time`, `env` and the runners are peeled; `nil` for an empty segment.
    ///
    /// - Parameter segment: One segment from ``segments(of:)``, heredoc body included.
    public static func invocation(of segment: String) -> Invocation? {
        var body = segment
        var heredoc: String? = nil
        if let nl = body.firstIndex(of: "\n") {
            heredoc = String(body[body.index(after: nl)...])
            body = String(body[..<nl])
        }
        let words = peelWrappers(words(body))
        guard let first = words.first else { return nil }
        var tool = (first as NSString).lastPathComponent
        var args = Array(words.dropFirst())
        let scriptLike = args.first.map { $0.contains(".") || $0.contains("/") } ?? false
        if interpreters.contains(tool) || ((tool == "bun" || tool == "deno") && scriptLike) {
            // python manage.py migrate / php artisan migrate / node ace migration:run — but
            // `bun test` and `deno test` are the runtime's own subcommands, not a script.
            guard let script = args.first else { return nil }
            tool = (script as NSString).lastPathComponent
            args.removeFirst()
        }
        return Invocation(tool: tool, arguments: args, heredoc: heredoc)
    }

    /// Runtimes whose first argument is the script that is really running.
    private static let interpreters: Set<String> = ["python", "python3", "php", "ruby", "node"]

    /// The wrappers that stand in front of a tool without being it.
    private static let wrappers: Set<String> = [
        "sudo", "time", "env", "nohup", "exec", "command", "npx", "bunx", "yarn", "poetry", "pipenv", "uv",
        "bundle", "pnpm", "npm", "docker", "docker-compose", "kubectl", "ssh", "sh", "bash", "zsh",
    ]

    /// `words` with every leading environment assignment and wrapper removed, repeatedly,
    /// until the first word is the tool itself.
    private static func peelWrappers(_ input: [String]) -> [String] {
        var words = input
        var peeled = true
        while peeled, !words.isEmpty {
            peeled = false
            let w = words[0]
            if w.range(of: #"^[A-Za-z_][A-Za-z0-9_]*=.*"#, options: .regularExpression) != nil { words.removeFirst(); peeled = true; continue }
            guard wrappers.contains(w) else { break }
            guard let rest = peelWrapper(w, from: words) else { break }
            words = rest
            if !words.isEmpty, words[0] != w { peeled = true }
        }
        return words
    }

    /// `words` with the wrapper `w` at its front removed, or `nil` when `w` is not acting as
    /// a wrapper here (`npm install`, `docker build`).
    private static func peelWrapper(_ w: String, from input: [String]) -> [String]? {
        var words = input
        switch w {
        case "sudo", "time", "env", "nohup", "exec", "command", "npx", "bunx":
            words.removeFirst()
            // sudo -u postgres psql …: the flag's value is not the tool.
            while let f = words.first, f.hasPrefix("-") {
                words.removeFirst()
                if w == "sudo", ["-u", "--user", "-g", "--group"].contains(f), !words.isEmpty { words.removeFirst() }
            }
        case "yarn":
            words.removeFirst()
            if words.first == "exec" || words.first == "run" { words.removeFirst() }
        case "poetry", "pipenv", "uv", "bundle":
            guard words.count > 1, words[1] == "run" || words[1] == "exec" else { return nil }
            words.removeFirst(2)
        case "pnpm", "npm":
            guard words.count > 1, ["dlx", "exec", "x"].contains(words[1]) else { return nil }
            words.removeFirst(2)
            words = words.drop { $0.hasPrefix("-") }.map { $0 }
        case "docker", "docker-compose":
            // docker compose exec [flags] SERVICE cmd… / docker exec [flags] CONTAINER cmd…
            var k = 1
            if w == "docker", k < words.count, words[k] == "compose" { k += 1 }
            guard k < words.count, words[k] == "exec" || words[k] == "run" else { return nil }
            k += 1
            while k < words.count, words[k].hasPrefix("-") { k += (["-e", "--env", "-u", "--user", "-w", "--workdir"].contains(words[k]) ? 2 : 1) }
            guard k < words.count else { return nil }
            words.removeFirst(k + 1)   // the service / container name too
        case "kubectl":
            guard words.count > 1, words[1] == "exec", let dash = words.firstIndex(of: "--") else { return nil }
            words.removeFirst(dash + 1)
        case "ssh":
            // ssh host 'cmd' — the command is the last argument.
            guard let last = words.last, words.count > 2 else { return nil }
            words = Self.words(last)
        case "sh", "bash", "zsh":
            guard words.count > 2, words[1] == "-c" else { return nil }
            words = Self.words(words[2])
        default:
            return nil
        }
        return words
    }
}
