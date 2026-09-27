//
//  DestructiveSQL.swift
//  ChangeFacts
//
//  Finds the statements a change adds that can lose data: DROP, TRUNCATE, an unconditioned
//  DELETE or UPDATE, a column type change — in SQL, and in the migration DSLs agents write.
//
//  Created by David Sherlock on 9/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The statements a change ADDS that can lose data, as facts on the lines that add them.
///
/// `DROP TABLE`/`DATABASE`/`SCHEMA`, `DROP COLUMN`, `TRUNCATE` and an unconditioned `DELETE` or
/// `UPDATE` are destructive; a column type change or a migration with no down step is a caution.
/// The migration DSLs (Rails, Django, Alembic, Knex, Laravel, Ecto, EF Core) count too, and raw
/// SQL inside them is read as SQL. Comments, `.sql` string literals, index/view drops, prose,
/// tests and vendored trees never count; a dump is one finding. A statement counts when any of
/// its lines was added.
public enum DestructiveSQL {

    /// Destructive: rows are lost. Caution: data may or may not survive.
    public enum Severity: String, Sendable, Equatable { case destructive, caution }

    /// One statement or DSL call, on the line it starts.
    public struct Finding: Equatable, Sendable {
        /// 1-based line in the scanned text where the statement starts.
        public let line: Int
        /// 1-based last line of the statement (its `;`, or the call's closing line).
        public let endLine: Int
        /// Destructive or caution.
        public let severity: Severity
        /// "DROP TABLE users", "DELETE without WHERE on sessions", "column type changed: users.email".
        public let summary: String

        /// Creates a finding.
        public init(line: Int, endLine: Int, severity: Severity, summary: String) {
            self.line = line
            self.endLine = endLine
            self.severity = severity
            self.summary = summary
        }
    }

    /// Which comment and string rules to read the file with. `nil`: not a file SQL runs from.
    public enum Dialect: Sendable, Equatable { case sql, ruby, python, javascript, php, elixir, csharp, go, java, other }

    /// The dialect `path`'s extension implies; nil for files SQL does not run from (prose, data).
    public static func dialect(forPath path: String) -> Dialect? {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "sql", "psql", "ddl", "dml", "pgsql", "mysql", "hql": return .sql
        case "rb", "rake": return .ruby
        case "py": return .python
        case "js", "mjs", "cjs", "ts", "mts", "cts", "jsx", "tsx": return .javascript
        case "php": return .php
        case "ex", "exs": return .elixir
        case "cs": return .csharp
        case "go": return .go
        case "java", "kt", "kts", "scala", "groovy": return .java
        case "sh", "bash", "zsh", "swift", "rs", "c", "cc", "cpp", "m", "mm", "dart", "pl", "lua", "r": return .other
        default: return nil   // md, txt, json, yaml, csv, html, lock files, images…
        }
    }

    /// Tests and vendored trees: SQL there runs against a test database or is not the change's.
    public static func isSkippedPath(_ path: String) -> Bool {
        let p = "/" + path.lowercased()
        let name = (path as NSString).lastPathComponent.lowercased()
        if ["/node_modules/", "/vendor/", "/.build/", "/dist/", "/build/"].contains(where: { p.contains($0) }) { return true }
        if ["/test/", "/tests/", "/__tests__/", "/spec/", "/specs/", "/testing/"].contains(where: { p.contains($0) }) { return true }
        return [".test.", ".spec.", "_test.", "_spec."].contains(where: { name.contains($0) }) || name.hasPrefix("test_")
    }

    /// pg_dump, mysqldump, MariaDB and SQLite `.dump` output, by their headers.
    public static func isDatabaseDump(_ text: String) -> Bool {
        let head = String(text.prefix(4096))
        if head.contains("PostgreSQL database dump") || head.contains("MySQL dump") || head.contains("MariaDB dump") { return true }
        if head.contains("Dumping data for table") { return true }
        return head.contains("PRAGMA foreign_keys=OFF;") && head.contains("BEGIN TRANSACTION;")
    }

    /// A migration file, by the paths and names the frameworks use.
    public static func looksLikeMigration(_ path: String) -> Bool {
        let p = path.lowercased()
        if p.contains("migrat") || p.contains("/alembic/") || p.contains("/versions/") || p.contains("/db/migrate") { return true }
        let name = (path as NSString).lastPathComponent
        if name.range(of: #"^\d{3,}_"#, options: .regularExpression) != nil { return true }   // 001_…, 20260920120000_…
        return name.range(of: #"^V\d+(_\d+)*__"#, options: .regularExpression) != nil         // Flyway
    }

    // MARK: - The scan

    /// Every finding in `text`, read as `path`'s dialect; with `addedLines`, only statements that
    /// touch one of those lines. Empty for a prose or data file, a test, a vendored file.
    public static func findings(in text: String, path: String, addedLines: Set<Int>? = nil) -> [Finding] {
        guard let dialect = dialect(forPath: path), !isSkippedPath(path) else { return [] }
        if isDatabaseDump(text) {
            let drops = matches(of: #"(?i)\bDROP\s+TABLE\b"#, in: text).count
            let f = Finding(line: 1, endLine: 1, severity: .destructive,
                            summary: "database dump" + (drops > 0 ? " (\(drops) DROP TABLE)" : ""))
            if let addedLines, !addedLines.isEmpty, addedLines.min()! > 200 { return [] }   // an edit deep in an existing dump
            return [f]
        }
        let clean = stripped(text, dialect: dialect)
        let starts = lineStarts(clean)
        func line(at offset: Int) -> Int { lineNumber(at: offset, starts: starts) }
        var out: [Finding] = []

        // --- SQL, whichever file it sits in
        for m in matches(of: #"(?i)\bDROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?((?:[\w"`\[\]]+\.)?[\w"`\[\]]+)"#, in: clean) {
            out.append(Finding(line: line(at: m.range.location), endLine: line(at: m.range.location), severity: .destructive, summary: "DROP TABLE \(ident(m, 1, clean))"))
        }
        for m in matches(of: #"(?i)\bDROP\s+(DATABASE|SCHEMA)\s+(?:IF\s+EXISTS\s+)?([\w"`\[\]]+)"#, in: clean) {
            out.append(Finding(line: line(at: m.range.location), endLine: line(at: m.range.location), severity: .destructive, summary: "DROP \(ident(m, 1, clean).uppercased()) \(ident(m, 2, clean))"))
        }
        for m in matches(of: #"(?i)\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?((?:[\w"`\[\]]+\.)?[\w"`\[\]]+)\b([^;]*?)\bDROP\s+(?!INDEX\b|CONSTRAINT\b|DEFAULT\b|NOT\s+NULL\b|PRIMARY\b|FOREIGN\b|CHECK\b|IDENTITY\b|PARTITION\b|KEY\b|TRIGGER\b)(?:COLUMN\s+)?(?:IF\s+EXISTS\s+)?([\w"`\[\]]+)"#, in: clean) {
            let at = m.range.location
            out.append(Finding(line: line(at: at), endLine: line(at: at + m.range.length), severity: .destructive, summary: "DROP COLUMN \(ident(m, 1, clean)).\(ident(m, 3, clean))"))
        }
        for m in matches(of: #"(?i)\bTRUNCATE\s+(?:TABLE\s+)?(?:ONLY\s+)?((?:[\w"`\[\]]+\.)?[\w"`\[\]]+)"#, in: clean) {
            out.append(Finding(line: line(at: m.range.location), endLine: line(at: m.range.location), severity: .destructive, summary: "TRUNCATE \(ident(m, 1, clean))"))
        }
        for m in matches(of: #"(?i)\bDELETE\s+FROM\s+(?:ONLY\s+)?((?:[\w"`\[\]]+\.)?[\w"`\[\]]+)"#, in: clean) {
            let body = statementBody(from: m.range.location, in: clean, dialect: dialect)
            if let why = unconditioned(body) {
                out.append(Finding(line: line(at: m.range.location), endLine: line(at: m.range.location + body.count), severity: .destructive, summary: "DELETE \(why) on \(ident(m, 1, clean))"))
            }
        }
        for m in matches(of: #"(?i)\bUPDATE\s+(?:ONLY\s+)?((?:[\w"`\[\]]+\.)?[\w"`\[\]]+)\s+SET\b"#, in: clean) {
            let body = statementBody(from: m.range.location, in: clean, dialect: dialect)
            if let why = unconditioned(body) {
                out.append(Finding(line: line(at: m.range.location), endLine: line(at: m.range.location + body.count), severity: .destructive, summary: "UPDATE \(why) on \(ident(m, 1, clean))"))
            }
        }
        for m in matches(of: #"(?i)\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?((?:[\w"`\[\]]+\.)?[\w"`\[\]]+)\b[^;]*?\b(?:ALTER\s+(?:COLUMN\s+)?([\w"`\[\]]+)\s+(?:SET\s+DATA\s+)?TYPE\b|MODIFY\s+(?:COLUMN\s+)?([\w"`\[\]]+)\s+\w|CHANGE\s+(?:COLUMN\s+)?([\w"`\[\]]+)\s+[\w"`\[\]]+\s+\w|ALTER\s+COLUMN\s+([\w"`\[\]]+)\s+(?:VARCHAR|NVARCHAR|CHAR|INT|BIGINT|SMALLINT|TINYINT|DECIMAL|NUMERIC|FLOAT|REAL|TEXT|DATE|DATETIME|TIMESTAMP|BOOLEAN|BIT|UUID|JSON|JSONB|BLOB|BYTEA)\b)"#, in: clean) {
            let column = [2, 3, 4, 5].compactMap { m.range(at: $0).location == NSNotFound ? nil : ident(m, $0, clean) }.first ?? "?"
            out.append(Finding(line: line(at: m.range.location), endLine: line(at: m.range.location + m.range.length), severity: .caution, summary: "column type changed: \(ident(m, 1, clean)).\(column)"))
        }

        // --- Migration DSLs
        let dsl: [(pattern: String, severity: Severity, summary: (NSTextCheckingResult) -> String)]
        switch dialect {
        case .ruby: dsl = [
            (#"\bdrop_table[\s(]+:?["']?(\w+)"#, .destructive, { "drop_table \(ident($0, 1, clean))" }),
            (#"\bremove_columns?[\s(]+:?["']?(\w+)["']?\s*,\s*:?["']?(\w+)"#, .destructive, { "remove_column \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
            (#"\bremove_(?:reference|belongs_to)[\s(]+:?["']?(\w+)["']?\s*,\s*:?["']?(\w+)"#, .destructive, { "remove_reference \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
            (#"\bchange_column[\s(]+:?["']?(\w+)["']?\s*,\s*:?["']?(\w+)"#, .caution, { "column type changed: \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
        ]
        case .python: dsl = [
            (#"migrations\.DeleteModel\(\s*(?:name\s*=\s*)?["'](\w+)"#, .destructive, { "DeleteModel \(ident($0, 1, clean))" }),
            (#"migrations\.RemoveField\(\s*(?:model_name\s*=\s*)?["'](\w+)["']\s*,\s*(?:name\s*=\s*)?["'](\w+)"#, .destructive, { "RemoveField \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
            (#"migrations\.AlterField\(\s*(?:model_name\s*=\s*)?["'](\w+)["']\s*,\s*(?:name\s*=\s*)?["'](\w+)"#, .caution, { "column type changed: \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
            (#"\bop\.drop_table\(\s*["'](\w+)"#, .destructive, { "op.drop_table \(ident($0, 1, clean))" }),
            (#"\bop\.drop_column\(\s*["'](\w+)["']\s*,\s*["'](\w+)"#, .destructive, { "op.drop_column \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
            (#"\bop\.alter_column\(\s*["'](\w+)["']\s*,\s*["'](\w+)["'][^)]*\btype_\s*="#, .caution, { "column type changed: \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
        ]
        case .javascript: dsl = [
            (#"\.dropTable(?:IfExists)?\(\s*["'`](\w+)"#, .destructive, { "dropTable \(ident($0, 1, clean))" }),
            (#"\.dropColumns?\(\s*\[?\s*["'`](\w+)"#, .destructive, { "dropColumn \(ident($0, 1, clean))" }),
            (#"\.removeColumn\(\s*["'`](\w+)["'`]\s*,\s*["'`](\w+)"#, .destructive, { "removeColumn \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
            (#"\.changeColumn\(\s*["'`](\w+)["'`]\s*,\s*["'`](\w+)"#, .caution, { "column type changed: \(ident($0, 1, clean)).\(ident($0, 2, clean))" }),
        ]
        case .php: dsl = [
            (#"Schema::drop(?:IfExists)?\(\s*["'](\w+)"#, .destructive, { "Schema::drop \(ident($0, 1, clean))" }),
            (#"->dropColumn\(\s*\[?\s*["'](\w+)"#, .destructive, { "dropColumn \(ident($0, 1, clean))" }),
            (#"\$table->\w+\(\s*["'](\w+)["'][^;]*?->change\(\)"#, .caution, { "column type changed: \(ident($0, 1, clean))" }),
        ]
        case .elixir: dsl = [
            (#"\bdrop(?:_if_exists)?\s+(?:if_exists\s+)?table\(\s*:?["']?(\w+)"#, .destructive, { "drop table \(ident($0, 1, clean))" }),
            (#"^\s*remove\s+:(\w+)"#, .destructive, { "remove :\(ident($0, 1, clean))" }),
            (#"^\s*modify\s+:(\w+)"#, .caution, { "column type changed: \(ident($0, 1, clean))" }),
        ]
        case .csharp: dsl = [
            (#"\.DropTable\(\s*(?:name\s*:\s*)?"(\w+)"#, .destructive, { "DropTable \(ident($0, 1, clean))" }),
            (#"\.DropColumn(?:<\w+>)?\(\s*(?:name\s*:\s*)?"(\w+)""#, .destructive, { "DropColumn \(ident($0, 1, clean))" }),
            (#"\.AlterColumn<\w+>\(\s*(?:name\s*:\s*)?"(\w+)""#, .caution, { "column type changed: \(ident($0, 1, clean))" }),
        ]
        default: dsl = []
        }
        for rule in dsl {
            for m in matches(of: rule.pattern, in: clean, anchorsMatchLines: true) {
                out.append(Finding(line: line(at: m.range.location), endLine: line(at: m.range.location + m.range.length), severity: rule.severity, summary: rule.summary(m)))
            }
        }

        // --- A migration with no way back
        if looksLikeMigration(path), let missing = missingDownStep(clean, dialect: dialect) {
            out.append(Finding(line: 1, endLine: max(1, starts.count), severity: .caution, summary: missing))
        }

        out.sort { $0.line != $1.line ? $0.line < $1.line : $0.summary < $1.summary }
        var seen = Set<String>()
        out = out.filter { seen.insert("\($0.line)|\($0.summary)").inserted }
        if let addedLines {
            out = out.filter { f in addedLines.contains { $0 >= f.line && $0 <= f.endLine } }
        }
        return out
    }

    /// "a migration with no down step" when the file has an up and no down, by framework.
    public static func missingDownStep(_ text: String, dialect: Dialect) -> String? {
        func has(_ p: String) -> Bool { text.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
        switch dialect {
        case .javascript:
            let up = has(#"\b(?:exports\.up|export\s+(?:const|async\s+function|function)\s+up|async\s+up\s*\(|\bup\s*:\s*async|\bup\s*\()"#)
            let down = has(#"\b(?:exports\.down|export\s+(?:const|async\s+function|function)\s+down|async\s+down\s*\(|\bdown\s*:\s*async|\bdown\s*\()"#)
            if up && !down { return "no down migration" }
            if up, has(#"\b(?:async\s+)?down\s*\([^)]*\)\s*(?::\s*\w+(?:<\w+>)?\s*)?\{\s*\}"#) { return "down migration is empty" }
        case .python:
            if has(#"\bdef\s+upgrade\s*\("#), has(#"\bdef\s+downgrade\s*\([^)]*\)\s*(?:->\s*\w+\s*)?:\s*(?:#[^\n]*\n\s*)?pass\b"#) { return "downgrade is a pass" }
            if has(#"\bdef\s+upgrade\s*\("#), !has(#"\bdef\s+downgrade\s*\("#) { return "no downgrade" }
        case .ruby:
            if has(#"\bdef\s+up\b"#), !has(#"\bdef\s+down\b"#) { return "no down migration" }
        case .php:
            if has(#"function\s+up\s*\("#), !has(#"function\s+down\s*\("#) { return "no down migration" }
            if has(#"function\s+down\s*\([^)]*\)(?:\s*:\s*void)?\s*\{\s*\}"#) { return "down migration is empty" }
        default: break
        }
        return nil
    }

    /// "Destructive SQL added — line 12: DROP TABLE users; line 30: DELETE without WHERE on sessions".
    public static func tooltip(for findings: [Finding]) -> String? {
        guard !findings.isEmpty else { return nil }
        let destructive = findings.filter { $0.severity == .destructive }.count
        let head = destructive > 0 ? "Destructive SQL added" : "SQL caution added"
        let shown = findings.prefix(6).map { "line \($0.line): \($0.summary)" }
        let more = findings.count > 6 ? "; and \(findings.count - 6) more" : ""
        return head + " — " + shown.joined(separator: "; ") + more
    }

    // MARK: - Diff chunks (All Changes, diff tabs)

    /// Marks for one file's diff chunk (its `diff --git` header through its hunks), keyed by
    /// VISIBLE line index — the position in `DiffLineLocator.visibleLines(in:)` — so a renderer
    /// puts each mark on the line it belongs to. Statements are read from the hunks' NEW side
    /// (context and added lines together), and only those touching an added line are marked.
    public static func marks(forChunk chunk: [String], path: String) -> [Int: Finding] {
        guard dialect(forPath: path) != nil, !isSkippedPath(path) else { return [:] }
        var newText: [String] = []
        var visibleForNewLine: [Int] = []   // newText index → visible index
        var added = Set<Int>()
        var inHunk = false
        var visible = -1
        for raw in chunk {
            // Mirror DiffLineLocator.visibleLines: header lines before the first @@ are not visible.
            if raw.hasPrefix("@@") {
                inHunk = true
                visible += 1
                if !newText.isEmpty { newText.append(";"); visibleForNewLine.append(-1) }   // no statement spans hunks
                continue
            }
            guard inHunk else { continue }
            visible += 1
            if raw.hasPrefix("+") || raw.hasPrefix(" ") || raw.isEmpty {
                newText.append(raw.isEmpty ? "" : String(raw.dropFirst()))
                visibleForNewLine.append(visible)
                if raw.hasPrefix("+") { added.insert(newText.count) }
            }
        }
        guard !added.isEmpty else { return [:] }
        var out: [Int: Finding] = [:]
        for f in findings(in: newText.joined(separator: "\n"), path: path, addedLines: added) {
            let idx = f.line - 1
            guard visibleForNewLine.indices.contains(idx), visibleForNewLine[idx] >= 0 else { continue }
            let v = visibleForNewLine[idx]
            if let existing = out[v] { out[v] = Finding(line: existing.line, endLine: existing.endLine, severity: existing.severity == .destructive ? .destructive : f.severity, summary: existing.summary + "; " + f.summary) }
            else { out[v] = f }
        }
        return out
    }

    // MARK: - Text plumbing

    /// Comments blanked (per dialect), and in SQL files the single-quoted literals too; every
    /// newline kept so offsets still map to lines.
    public static func stripped(_ text: String, dialect: Dialect) -> String {
        let hash = dialect == .ruby || dialect == .python || dialect == .elixir || dialect == .php || dialect == .other || dialect == .sql
        let slash = dialect == .javascript || dialect == .php || dialect == .csharp || dialect == .go || dialect == .java || dialect == .other
        let dashes = dialect == .sql || dialect == .other
        let blankLiterals = dialect == .sql
        let chars = Array(text.utf16)
        var out = chars
        var i = 0
        var inSingle = false, inDouble = false, inBacktick = false, inLine = false, inBlock = false
        var tripleDouble = false, tripleSingle = false
        let nl = UInt16(10)
        func at(_ k: Int) -> UInt16 { k < chars.count ? chars[k] : 0 }
        while i < chars.count {
            let c = chars[i]
            if inLine { if c == nl { inLine = false } else { out[i] = 32 }; i += 1; continue }
            if inBlock {
                if c == 42, at(i + 1) == 47 { out[i] = 32; out[i + 1] = 32; inBlock = false; i += 2 } else { if c != nl { out[i] = 32 }; i += 1 }
                continue
            }
            if tripleDouble || tripleSingle {
                let q: UInt16 = tripleDouble ? 34 : 39
                if c == q, at(i + 1) == q, at(i + 2) == q { tripleDouble = false; tripleSingle = false; i += 3 } else { i += 1 }
                continue
            }
            if inSingle {
                if c == 92 { if blankLiterals { out[i] = 32; if i + 1 < chars.count, chars[i + 1] != nl { out[i + 1] = 32 } }; i += 2; continue }
                if c == 39 { if at(i + 1) == 39 && dialect == .sql { if blankLiterals { out[i] = 32; out[i + 1] = 32 }; i += 2; continue }; inSingle = false }
                else if blankLiterals, c != nl { out[i] = 32 }
                i += 1; continue
            }
            if inDouble { if c == 92 { i += 2; continue }; if c == 34 { inDouble = false }; i += 1; continue }
            if inBacktick { if c == 96 { inBacktick = false }; i += 1; continue }
            // Not inside anything.
            if dashes, c == 45, at(i + 1) == 45 { inLine = true; out[i] = 32; i += 1; continue }
            if hash, c == 35 { inLine = true; out[i] = 32; i += 1; continue }
            if slash, c == 47, at(i + 1) == 47 { inLine = true; out[i] = 32; i += 1; continue }
            if c == 47, at(i + 1) == 42 { inBlock = true; out[i] = 32; i += 1; continue }
            if dialect == .python, c == 34, at(i + 1) == 34, at(i + 2) == 34 { tripleDouble = true; i += 3; continue }
            if dialect == .python, c == 39, at(i + 1) == 39, at(i + 2) == 39 { tripleSingle = true; i += 3; continue }
            if c == 39 { inSingle = true; i += 1; continue }
            if c == 34, dialect != .sql { inDouble = true; i += 1; continue }
            if c == 96, dialect == .javascript { inBacktick = true; i += 1; continue }
            i += 1
        }
        return String(utf16CodeUnits: out, count: out.count)
    }

    /// The statement from `offset` to its `;`, the end of the string literal it sits in (a code
    /// file), a blank line, or 4 000 characters — whichever comes first.
    public static func statementBody(from offset: Int, in text: String, dialect: Dialect) -> String {
        let ns = text as NSString
        let end = min(ns.length, offset + 4_000)
        var i = offset
        var last: unichar = 0
        while i < end {
            let c = ns.character(at: i)
            if c == 59 { break }                                                     // ;
            if c == 10, last == 10 { break }                                         // blank line
            if dialect != .sql, c == 34 || c == 39 || c == 96 {                      // a closing quote…
                let next = i + 1 < ns.length ? ns.character(at: i + 1) : 0
                if next == 41 || next == 44 || next == 59 || next == 10 || next == 32 || next == 0 { break }   // …then ) , ; newline space
            }
            last = c
            i += 1
        }
        return ns.substring(with: NSRange(location: offset, length: i - offset))
    }

    /// nil when the statement has a real WHERE; else why it is unconditioned.
    public static func unconditioned(_ body: String) -> String? {
        guard body.range(of: #"\bWHERE\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return "without WHERE" }
        if body.range(of: #"\bWHERE\s+(?:1\s*=\s*1|TRUE|1)\s*(?:$|\)|;)"#, options: [.regularExpression, .caseInsensitive]) != nil { return "WHERE 1=1" }
        return nil
    }

    /// Every match of `pattern` in `text`; `.` matches newlines, `^`/`$` lines only when asked.
    public static func matches(of pattern: String, in text: String, anchorsMatchLines: Bool = false) -> [NSTextCheckingResult] {
        var opts: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if anchorsMatchLines { opts.insert(.anchorsMatchLines) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return [] }
        return re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// Capture group `group` as an identifier with its `"`, `` ` `` and `[]` quoting removed; "?" when absent.
    public static func ident(_ m: NSTextCheckingResult, _ group: Int, _ text: String) -> String {
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return "?" }
        return (text as NSString).substring(with: r).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
    }

    /// The UTF-16 offset each line of `text` starts at, for ``lineNumber(at:starts:)``.
    public static func lineStarts(_ text: String) -> [Int] {
        var starts = [0]
        for (i, u) in text.utf16.enumerated() where u == 10 { starts.append(i + 1) }
        return starts
    }

    /// The 1-based line holding UTF-16 `offset`, by binary search over ``lineStarts(_:)``.
    public static func lineNumber(at offset: Int, starts: [Int]) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }
}
