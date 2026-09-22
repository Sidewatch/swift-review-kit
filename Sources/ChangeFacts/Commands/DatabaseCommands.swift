//
//  DatabaseCommands.swift
//  ChangeFacts
//
//  The database commands a shell line ran — psql, prisma, rails db:*, sqlite3 … — as facts with
//  a severity: what the SQL they carry is, or what the subcommand does by its own documentation.
//
//  Created by David Sherlock on 9/20/26.
//

import Foundation

/// The database commands a shell line shows were RUN — `psql -c "DELETE …"`, `prisma migrate
/// reset`, `rails db:drop`, `sqlite3 app.db < fix.sql` — as facts with a severity: what the SQL
/// they carry is (`DestructiveSQL`), or what the subcommand does by its own documentation (a
/// `migrate reset` drops and recreates the database; a `migrate` does not).
///
/// The line is split into the segments a shell runs (`ShellCommandLine`), each is peeled of its
/// wrappers, and the tool left at the front is classified. Inline SQL comes from `-c` /
/// `--command` (psql), `-e` / `--execute` (mysql), the positional argument (sqlite3, duckdb),
/// `--eval` (mongosh), and a heredoc body. A script the agent ran (`./scripts/reset-db.sh`) is
/// not seen through; a file it fed (`-f`, `<`) is named, not read.
public enum DatabaseCommands {

    /// One database command, as it was run and what it did.
    public struct Command: Equatable, Sendable {
        /// The segment as the agent ran it (trimmed), heredoc body included.
        public let text: String
        /// "psql", "prisma", "rails"…
        public let tool: String
        /// `nil`: informational (a migrate, a dump, a shell opened).
        public let severity: DestructiveSQL.Severity?
        /// "DELETE without WHERE on users", "migrate reset (drops and recreates the database)".
        public let summary: String
        /// Whatever the caller attached: a transcript's `HH:MM`, or `""`.
        public let timestamp: String

        public init(text: String, tool: String, severity: DestructiveSQL.Severity?, summary: String, timestamp: String) {
            self.text = text
            self.tool = tool
            self.severity = severity
            self.summary = summary
            self.timestamp = timestamp
        }
    }

    /// Every database command in one shell line, in order.
    ///
    /// - Parameters:
    ///   - command: The line as the agent ran it, every `&&` link and heredoc included.
    ///   - timestamp: Carried onto each command, for a row.
    public static func detect(_ command: String, timestamp: String = "") -> [Command] {
        ShellCommandLine.segments(of: command).compactMap { classify($0, timestamp: timestamp) }
    }

    // MARK: - Classifying

    /// The command a segment is, or `nil` when it is not a database tool.
    static func classify(_ segment: String, timestamp: String) -> Command? {
        guard let call = ShellCommandLine.invocation(of: segment) else { return nil }
        let tool = call.tool, args = call.arguments, heredoc = call.heredoc
        let joined = args.joined(separator: " ")
        func sqlVerdict(_ sql: String?, prefix: String) -> (DestructiveSQL.Severity?, String)? {
            guard let sql, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let findings = DestructiveSQL.findings(in: sql, path: "command.sql")
            if let worst = findings.first(where: { $0.severity == .destructive }) ?? findings.first {
                let more = findings.count > 1 ? " (+\(findings.count - 1) more)" : ""
                return (worst.severity, prefix + worst.summary + more)
            }
            return (nil, prefix + firstLine(sql))
        }
        func option(_ names: [String]) -> String? {
            for (i, a) in args.enumerated() {
                for n in names {
                    if a == n, i + 1 < args.count { return args[i + 1] }
                    if a.hasPrefix(n + "=") { return String(a.dropFirst(n.count + 1)) }
                    if n.count == 2, a.hasPrefix(n), a.count > 2, !a.hasPrefix("--") { return String(a.dropFirst(2)) }
                }
            }
            return nil
        }
        func file(_ names: [String]) -> String? {
            if let f = option(names) { return f }
            if let lt = args.firstIndex(of: "<"), lt + 1 < args.count { return args[lt + 1] }
            return nil
        }
        func make(_ severity: DestructiveSQL.Severity?, _ summary: String) -> Command {
            Command(text: segment, tool: tool, severity: severity, summary: summary, timestamp: timestamp)
        }
        let sub = args.first(where: { !$0.hasPrefix("-") }) ?? ""
        let sub2 = args.drop(while: { $0.hasPrefix("-") }).dropFirst().first(where: { !$0.hasPrefix("-") }) ?? ""

        switch tool {
        case "psql", "pgcli":
            if let v = sqlVerdict(option(["-c", "--command"]) ?? heredoc, prefix: "") { return make(v.0, v.1) }
            if let f = file(["-f", "--file"]) { return make(.caution, "runs \((f as NSString).lastPathComponent)") }
            return make(nil, "opens a psql session")
        case "mysql", "mariadb", "mycli":
            if let v = sqlVerdict(option(["-e", "--execute"]) ?? heredoc, prefix: "") { return make(v.0, v.1) }
            if let f = file([]) { return make(.caution, "runs \((f as NSString).lastPathComponent)") }
            return make(nil, "opens a mysql session")
        case "sqlite3", "litecli", "duckdb":
            let positional = args.filter { !$0.hasPrefix("-") }
            let inline = positional.count >= 2 ? positional[1...].joined(separator: " ") : nil
            if let v = sqlVerdict(inline ?? heredoc, prefix: "") { return make(v.0, v.1) }
            if let f = file([]) { return make(.caution, "runs \((f as NSString).lastPathComponent)") }
            return make(nil, "opens \(positional.first.map { ($0 as NSString).lastPathComponent } ?? "a database")")
        case "clickhouse-client", "cqlsh":
            if let v = sqlVerdict(option(["-q", "--query", "-e", "--execute"]) ?? heredoc, prefix: "") { return make(v.0, v.1) }
            return make(nil, "opens a session")
        case "mongosh", "mongo":
            let script = (option(["--eval"]) ?? heredoc ?? "")
            if script.range(of: #"dropDatabase\s*\("#, options: .regularExpression) != nil { return make(.destructive, "dropDatabase()") }
            if script.range(of: #"\.drop\s*\("#, options: .regularExpression) != nil { return make(.destructive, "collection drop()") }
            if script.range(of: #"deleteMany\s*\(\s*\{\s*\}"#, options: .regularExpression) != nil { return make(.destructive, "deleteMany({}) — every document") }
            return make(nil, script.isEmpty ? "opens a mongo shell" : firstLine(script))
        case "redis-cli":
            if joined.range(of: #"(?i)\bFLUSH(ALL|DB)\b"#, options: .regularExpression) != nil { return make(.destructive, joined.uppercased().contains("FLUSHALL") ? "FLUSHALL — every key" : "FLUSHDB — every key in the database") }
            return make(nil, joined.isEmpty ? "opens redis-cli" : firstLine(joined))
        case "dropdb": return make(.destructive, "dropdb \(sub) — drops the database")
        case "createdb": return make(nil, "createdb \(sub)")
        case "pg_dump", "mysqldump", "mongodump": return make(nil, "\(tool) — a backup")
        case "pg_restore": return make(args.contains("--clean") || args.contains("-c") ? .caution : nil, args.contains("--clean") || args.contains("-c") ? "pg_restore --clean — drops objects before restoring" : "pg_restore")
        case "prisma":
            if sub == "migrate", sub2 == "reset" { return make(.destructive, "prisma migrate reset — drops and recreates the database") }
            if sub == "db", sub2 == "push", args.contains("--force-reset") { return make(.destructive, "prisma db push --force-reset — drops and recreates the database") }
            if sub == "db", sub2 == "push", args.contains("--accept-data-loss") { return make(.destructive, "prisma db push --accept-data-loss") }
            if sub == "db", sub2 == "execute" { if let v = sqlVerdict(heredoc, prefix: "prisma db execute: ") { return make(v.0, v.1) }; return make(.caution, "prisma db execute \(file(["--file"]).map { "(\(($0 as NSString).lastPathComponent))" } ?? "")") }
            return make(nil, "prisma \(sub) \(sub2)".trimmingCharacters(in: .whitespaces))
        case "knex":
            if sub == "migrate:rollback" { return make(args.contains("--all") ? .destructive : .caution, "knex migrate:rollback\(args.contains("--all") ? " --all" : "")") }
            return make(nil, "knex \(sub)")
        case "sequelize", "sequelize-cli":
            if sub == "db:drop" { return make(.destructive, "sequelize db:drop") }
            if sub == "db:migrate:undo:all" { return make(.destructive, "sequelize db:migrate:undo:all") }
            if sub == "db:migrate:undo" { return make(.caution, "sequelize db:migrate:undo") }
            return make(nil, "sequelize \(sub)")
        case "typeorm":
            if sub == "schema:drop" { return make(.destructive, "typeorm schema:drop") }
            if sub == "migration:revert" { return make(.caution, "typeorm migration:revert") }
            return make(nil, "typeorm \(sub)")
        case "alembic":
            if sub == "downgrade" {
                let target = args.drop(while: { $0 != "downgrade" }).dropFirst().first ?? ""   // "base", "-1", a revision
                return make(target == "base" ? .destructive : .caution, "alembic downgrade \(target)".trimmingCharacters(in: .whitespaces))
            }
            return make(nil, "alembic \(sub)")
        case "flyway":
            if sub == "clean" { return make(.destructive, "flyway clean — drops every object in the schema") }
            if sub == "undo" { return make(.caution, "flyway undo") }
            return make(nil, "flyway \(sub)")
        case "liquibase":
            if sub == "dropAll" || sub == "drop-all" { return make(.destructive, "liquibase dropAll") }
            if sub.hasPrefix("rollback") { return make(.caution, "liquibase \(sub)") }
            return make(nil, "liquibase \(sub)")
        case "rails", "rake":
            let task = args.first(where: { $0.hasPrefix("db:") }) ?? ""
            let destructive = ["db:drop", "db:reset", "db:purge", "db:schema:load", "db:structure:load", "db:truncate_all", "db:setup"]
            if destructive.contains(where: { task == $0 || task.hasPrefix($0 + ":") }) { return make(.destructive, "\(tool) \(task)") }
            if task.hasPrefix("db:rollback") || task.hasPrefix("db:migrate:down") { return make(.caution, "\(tool) \(task)") }
            if task.hasPrefix("db:") { return make(nil, "\(tool) \(task)") }
            return nil
        case "manage.py", "django-admin":
            if sub == "flush" { return make(.destructive, "manage.py flush — deletes every row") }
            if sub == "migrate", args.contains("zero") { return make(.destructive, "manage.py migrate … zero — unapplies the app's migrations") }
            if sub == "dbshell" { if let v = sqlVerdict(heredoc, prefix: "dbshell: ") { return make(v.0, v.1) }; return make(nil, "manage.py dbshell") }
            if ["migrate", "makemigrations", "sqlmigrate", "loaddata", "dumpdata", "showmigrations"].contains(sub) { return make(nil, "manage.py \(sub)") }
            return nil
        case "artisan":
            if ["migrate:fresh", "migrate:reset", "migrate:refresh", "db:wipe"].contains(sub) { return make(.destructive, "artisan \(sub)") }
            if sub == "migrate:rollback" { return make(.caution, "artisan migrate:rollback") }
            if sub.hasPrefix("migrate") || sub.hasPrefix("db:") { return make(nil, "artisan \(sub)") }
            return nil
        case "mix":
            if sub == "ecto.drop" || sub == "ecto.reset" { return make(.destructive, "mix \(sub)") }
            if sub == "ecto.rollback" { return make(.caution, "mix ecto.rollback") }
            if sub.hasPrefix("ecto.") { return make(nil, "mix \(sub)") }
            return nil
        case "supabase":
            if sub == "db", sub2 == "reset" { return make(.destructive, "supabase db reset") }
            if sub == "db" { return make(nil, "supabase db \(sub2)") }
            return nil
        case "atlas":
            if sub == "schema", sub2 == "clean" { return make(.destructive, "atlas schema clean") }
            return sub == "migrate" || sub == "schema" ? make(nil, "atlas \(sub) \(sub2)") : nil
        case "dbmate":
            if sub == "drop" { return make(.destructive, "dbmate drop") }
            if sub == "down" || sub == "rollback" { return make(.caution, "dbmate \(sub)") }
            return make(nil, "dbmate \(sub)")
        case "goose":
            if sub == "reset" { return make(.destructive, "goose reset") }
            if sub == "down" || sub == "down-to" { return make(.caution, "goose \(sub)") }
            return make(nil, "goose \(sub)")
        case "migrate":
            // golang-migrate: the verb follows `-path db -database $URL`, whose VALUES are not
            // flags, so the first bare word is "db" — the verb is the first of its own verbs seen.
            let verbs = ["up", "down", "drop", "force", "goto", "version", "create"]
            let verb = args.first(where: { verbs.contains($0) }) ?? ""
            if verb == "drop" { return make(.destructive, "migrate drop") }
            if verb == "down" { return make(args.contains("-all") ? .destructive : .caution, "migrate down\(args.contains("-all") ? " -all" : "")") }
            return verb == "up" || verb == "force" || verb == "goto" ? make(nil, "migrate \(verb)") : nil
        case "drizzle-kit": return make(nil, "drizzle-kit \(sub)")
        case "wrangler":
            guard sub == "d1" else { return nil }
            if let v = sqlVerdict(option(["--command"]), prefix: "d1: ") { return make(v.0, v.1) }
            return make(nil, "wrangler d1 \(sub2)")
        case "turso":
            guard sub == "db" else { return nil }
            if let v = sqlVerdict(heredoc, prefix: "turso: ") { return make(v.0, v.1) }
            return make(sub2 == "destroy" ? .destructive : nil, "turso db \(sub2)")
        default:
            return nil
        }
    }

    /// The first line of `s`, trimmed and cut to 120 characters.
    static func firstLine(_ s: String) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 120 ? String(trimmed.prefix(119)) + "…" : trimmed
    }
}
