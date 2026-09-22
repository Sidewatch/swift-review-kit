//
//  SchemaDDL.swift
//  ChangeFacts
//
//  The schema files agents write — Prisma, a Rails schema.rb, Django models — as the SQL DDL the
//  ER diagram and the schema diff already understand.
//
//  Created by David Sherlock on 9/20/26.
//

import Foundation

/// Turns a schema written in a framework's own language into CREATE TABLE statements SQLite
/// can build in memory (the `DatabaseView` diagram's input), so the data model an agent wrote
/// shows as tables, columns and foreign keys without a database. Types keep the framework's
/// names where SQLite has none (VARCHAR(120), DECIMAL(10,2), DATETIME, BOOLEAN) — a diagram
/// and a diff both want the declared type, not what SQLite would coerce it to. Defaults are
/// carried when they are literals; a function default (`now()`) is dropped, since the model's
/// shape is the fact here, not the value.
///
/// Prisma: models with `@id`, `@unique`, `?` for nullable, `@map`/`@@map`, `@db.X(n)`,
/// `@relation(fields:references:)` as the foreign key, list relations skipped (virtual),
/// `@@index` / `@@unique` as indexes, enums as TEXT. Rails: `create_table` blocks with
/// `t.<type>`, `t.references` (a `_id` column, a foreign key when asked), `t.timestamps`,
/// `t.index`, `add_foreign_key`, `add_index`. Django: `class X(models.Model)` fields, `db_table`,
/// abstract models skipped, `ForeignKey` / `OneToOneField` as `<name>_id` with a foreign key,
/// `ManyToManyField` skipped (its join table is the framework's), `unique_together` as an index.
/// Drizzle and SQLAlchemy are not read.
public enum SchemaDDL {

    /// Files this can read, by name: `*.prisma`, `schema.rb`, `models.py`.
    public static func isSchemaFile(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        return name.hasSuffix(".prisma") || name == "schema.rb" || name == "models.py"
    }

    /// The DDL for `text` read as `path`'s kind; nil when the path is not a schema file.
    public static func ddl(for text: String, path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name.hasSuffix(".prisma") { return prisma(text) }
        if name == "schema.rb" { return rails(text) }
        if name == "models.py" { return django(text) }
        return nil
    }

    public static func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    // MARK: - Prisma

    public static func prisma(_ text: String) -> String {
        let clean = stripComments(text, line: "//")
        var enums = Set<String>()
        for m in matches(#"\benum\s+(\w+)\s*\{"#, clean) { enums.insert(group(m, 1, clean)) }
        // Model names first, so a field whose type is a model is a relation field; and every
        // model's field → column map (`@map`), so relations and indexes name the COLUMN.
        var modelNames = Set<String>()
        var columnMaps: [String: [String: String]] = [:]
        for m in matches(#"\bmodel\s+(\w+)\s*\{([^}]*)\}"#, clean) {
            let model = group(m, 1, clean)
            modelNames.insert(model)
            var map: [String: String] = [:]
            for line in group(m, 2, clean).components(separatedBy: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 2, !parts[0].hasPrefix("@@") else { continue }
                if let mapped = matches(#"@map\("([^"]+)"\)"#, line).first { map[parts[0]] = group(mapped, 1, line) }
            }
            columnMaps[model] = map
        }
        var out: [String] = []
        for m in matches(#"\bmodel\s+(\w+)\s*\{([^}]*)\}"#, clean) {
            let model = group(m, 1, clean)
            let body = group(m, 2, clean)
            var table = model
            let colName: (String) -> String = { columnMaps[model]?[$0] ?? $0 }
            var columns: [String] = []
            var constraints: [String] = []
            var indexes: [String] = []
            var compositeId: [String]? = nil
            for rawLine in body.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                if line.hasPrefix("@@map(") { table = firstString(in: line) ?? table; continue }
                if line.hasPrefix("@@id(") { compositeId = bracketList(in: line).map(colName); continue }
                if line.hasPrefix("@@unique(") || line.hasPrefix("@@index(") {
                    let cols = bracketList(in: line).map(colName)
                    let unique = line.hasPrefix("@@unique(")
                    indexes.append("CREATE \(unique ? "UNIQUE " : "")INDEX \(quote("\(table)_\(cols.joined(separator: "_"))_\(unique ? "key" : "idx")")) ON \(quote(table)) (\(cols.map(quote).joined(separator: ", ")));")
                    continue
                }
                if line.hasPrefix("@@") { continue }
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 2 else { continue }
                let field = parts[0]
                var type = parts[1]
                let attrs = parts.dropFirst(2).joined(separator: " ")
                let isList = type.hasSuffix("[]")
                let optional = type.hasSuffix("?")
                type = type.trimmingCharacters(in: CharacterSet(charactersIn: "?[]"))
                if modelNames.contains(type) {
                    // A relation field: the foreign key lives on the `fields:` columns.
                    if !isList, let rel = matches(#"@relation\(([^)]*)\)"#, attrs).first {
                        let inner = group(rel, 1, attrs)
                        let fields = list(named: "fields", in: inner).map(colName)
                        let refs = list(named: "references", in: inner).map { columnMaps[type]?[$0] ?? $0 }
                        if !fields.isEmpty, fields.count == refs.count {
                            let target = modelTable(type, clean)
                            constraints.append("FOREIGN KEY (\(fields.map(quote).joined(separator: ", "))) REFERENCES \(quote(target)) (\(refs.map(quote).joined(separator: ", ")))")
                        }
                    }
                    continue
                }
                if isList { continue }   // scalar lists are Postgres arrays; not a column the diagram draws
                var column = field
                if let mapped = matches(#"@map\("([^"]+)"\)"#, attrs).first { column = group(mapped, 1, attrs) }
                var sqlType = prismaType(type, isEnum: enums.contains(type))
                if let native = matches(#"@db\.(\w+)(\([^)]*\))?"#, attrs).first {
                    sqlType = group(native, 1, attrs).uppercased() + (native.range(at: 2).location == NSNotFound ? "" : group(native, 2, attrs))
                }
                var decl = "\(quote(column)) \(sqlType)"
                if attrs.contains("@id") && compositeId == nil { decl += " PRIMARY KEY" }
                else if !optional { decl += " NOT NULL" }
                if attrs.contains("@unique") { decl += " UNIQUE" }
                if let def = matches(#"@default\(([^)]*)\)"#, attrs).first, let literal = literalDefault(group(def, 1, attrs)) { decl += " DEFAULT \(literal)" }
                columns.append(decl)
                _ = field
            }
            if let compositeId { constraints.append("PRIMARY KEY (\(compositeId.map(quote).joined(separator: ", ")))") }
            out.append("CREATE TABLE \(quote(table)) (\n  " + (columns + constraints).joined(separator: ",\n  ") + "\n);")
            out += indexes
        }
        return out.joined(separator: "\n")
    }

    private static func modelTable(_ model: String, _ text: String) -> String {
        guard let m = matches(#"\bmodel\s+"# + NSRegularExpression.escapedPattern(for: model) + #"\s*\{([^}]*)\}"#, text).first else { return model }
        let body = group(m, 1, text)
        if let map = matches(#"@@map\("([^"]+)"\)"#, body).first { return group(map, 1, body) }
        return model
    }

    private static func prismaType(_ t: String, isEnum: Bool) -> String {
        if isEnum { return "TEXT" }
        switch t {
        case "String": return "TEXT"
        case "Int": return "INTEGER"
        case "BigInt": return "BIGINT"
        case "Float": return "REAL"
        case "Decimal": return "DECIMAL"
        case "Boolean": return "BOOLEAN"
        case "DateTime": return "DATETIME"
        case "Json": return "JSON"
        case "Bytes": return "BLOB"
        default: return t.uppercased()
        }
    }

    // MARK: - Rails schema.rb

    public static func rails(_ text: String) -> String {
        let clean = stripComments(text, line: "#")
        var out: [String] = []
        var laterStatements: [String] = []
        for m in matches(#"create_table\s+"([^"]+)"([^\n]*)\bdo\s*\|t\|(.*?)^\s*end\b"#, clean, anchorsMatchLines: true) {
            let table = group(m, 1, clean)
            let options = group(m, 2, clean)
            let body = group(m, 3, clean)
            var columns: [String] = []
            var constraints: [String] = []
            if !options.contains("id: false") {
                let idType = matches(#"id:\s*:(\w+)"#, options).first.map { group($0, 1, options) } ?? "bigint"
                let pkName = matches(#"primary_key:\s*"([^"]+)""#, options).first.map { group($0, 1, options) } ?? "id"
                columns.append("\(quote(pkName)) \(railsType(idType, opts: "")) PRIMARY KEY")
            }
            for rawLine in body.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("t.") else { continue }
                if line.hasPrefix("t.timestamps") {
                    columns.append("\(quote("created_at")) DATETIME NOT NULL")
                    columns.append("\(quote("updated_at")) DATETIME NOT NULL")
                    continue
                }
                if line.hasPrefix("t.index ") {
                    let cols = bracketList(in: line)
                    let unique = line.contains("unique: true")
                    let name = matches(#"name:\s*"([^"]+)""#, line).first.map { group($0, 1, line) } ?? "index_\(table)_on_\(cols.joined(separator: "_and_"))"
                    laterStatements.append("CREATE \(unique ? "UNIQUE " : "")INDEX \(quote(name)) ON \(quote(table)) (\(cols.map(quote).joined(separator: ", ")));")
                    continue
                }
                guard let call = matches(#"^t\.(\w+)\s+"([^"]+)"(.*)$"#, line).first else { continue }
                let kind = group(call, 1, line), name = group(call, 2, line), opts = group(call, 3, line)
                if kind == "references" || kind == "belongs_to" {
                    let column = name + "_id"
                    var decl = "\(quote(column)) BIGINT"
                    if opts.contains("null: false") { decl += " NOT NULL" }
                    columns.append(decl)
                    if opts.contains("foreign_key: true") || opts.contains("foreign_key: {") {
                        let target = matches(#"to_table:\s*:?"?(\w+)"#, opts).first.map { group($0, 1, opts) } ?? plural(name)
                        constraints.append("FOREIGN KEY (\(quote(column))) REFERENCES \(quote(target)) (\(quote("id")))")
                    }
                    continue
                }
                var decl = "\(quote(name)) \(railsType(kind, opts: opts))"
                if opts.contains("null: false") { decl += " NOT NULL" }
                if let def = matches(#"default:\s*("[^"]*"|[-\d.]+|true|false|nil)"#, opts).first {
                    let raw = group(def, 1, opts)
                    if raw != "nil" { decl += " DEFAULT \(raw == "true" ? "1" : raw == "false" ? "0" : raw.replacingOccurrences(of: "\"", with: "'"))" }
                }
                columns.append(decl)
            }
            out.append("CREATE TABLE \(quote(table)) (\n  " + (columns + constraints).joined(separator: ",\n  ") + "\n);")
        }
        // Foreign keys declared after the tables become ALTER-less: re-emit as index-like facts
        // SQLite can hold — a table constraint needs the CREATE, so we rewrite the CREATE.
        for m in matches(#"add_foreign_key\s+"([^"]+)",\s*"([^"]+)"([^\n]*)"#, clean) {
            let from = group(m, 1, clean), to = group(m, 2, clean), opts = group(m, 3, clean)
            let column = matches(#"column:\s*"([^"]+)""#, opts).first.map { group($0, 1, opts) } ?? singular(to) + "_id"
            let primary = matches(#"primary_key:\s*"([^"]+)""#, opts).first.map { group($0, 1, opts) } ?? "id"
            if let i = out.firstIndex(where: { $0.hasPrefix("CREATE TABLE \(quote(from)) (") }) {
                out[i] = out[i].replacingOccurrences(of: "\n);", with: ",\n  FOREIGN KEY (\(quote(column))) REFERENCES \(quote(to)) (\(quote(primary)))\n);")
            }
        }
        for m in matches(#"add_index\s+"([^"]+)",\s*(\[[^\]]*\]|"[^"]+")([^\n]*)"#, clean) {
            let table = group(m, 1, clean), colsRaw = group(m, 2, clean), opts = group(m, 3, clean)
            let cols = colsRaw.hasPrefix("[") ? bracketList(in: colsRaw) : [colsRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))]
            let unique = opts.contains("unique: true")
            let name = matches(#"name:\s*"([^"]+)""#, opts).first.map { group($0, 1, opts) } ?? "index_\(table)_on_\(cols.joined(separator: "_and_"))"
            laterStatements.append("CREATE \(unique ? "UNIQUE " : "")INDEX \(quote(name)) ON \(quote(table)) (\(cols.map(quote).joined(separator: ", ")));")
        }
        return (out + laterStatements).joined(separator: "\n")
    }

    private static func railsType(_ kind: String, opts: String) -> String {
        let limit = matches(#"limit:\s*(\d+)"#, opts).first.map { group($0, 1, opts) }
        switch kind {
        case "string": return "VARCHAR(\(limit ?? "255"))"
        case "text": return "TEXT"
        case "integer": return "INTEGER"
        case "bigint", "bigserial": return "BIGINT"
        case "serial": return "INTEGER"
        case "boolean": return "BOOLEAN"
        case "datetime", "timestamp": return "DATETIME"
        case "date": return "DATE"
        case "time": return "TIME"
        case "float": return "REAL"
        case "decimal", "numeric":
            let p = matches(#"precision:\s*(\d+)"#, opts).first.map { group($0, 1, opts) }
            let s = matches(#"scale:\s*(\d+)"#, opts).first.map { group($0, 1, opts) }
            return p.map { "DECIMAL(\($0)\(s.map { ",\($0)" } ?? ""))" } ?? "DECIMAL"
        case "json", "jsonb": return kind.uppercased()
        case "uuid": return "UUID"
        case "binary", "blob": return "BLOB"
        default: return kind.uppercased()
        }
    }

    // MARK: - Django models.py

    public static func django(_ text: String) -> String {
        let clean = stripComments(text, line: "#") + "\n"   // a final line without a newline is still a body line
        var out: [String] = []
        var laterIndexes: [String] = []
        // Each class body is the run of indented (or blank) lines under it: one line per
        // iteration, so a blank line's newline never swallows the next line's indentation.
        // (An unambiguous line alternation: "indented content" or "empty" — the earlier
        // `[ \t]+[^\n]*|[ \t]*` let a whitespace line match both ways and backtracked for minutes.)
        let classes = matches(#"(?m)^class\s+(\w+)\s*\(([^)]*)\)\s*:[ \t]*\n((?:[ \t]+[^\n]*\n|\n)*)"#, clean)
        var tableNames: [String: String] = [:]
        var abstract = Set<String>()
        var bodies: [String: String] = [:]
        for m in classes {
            let name = group(m, 1, clean), body = group(m, 3, clean)
            bodies[name] = body
            if body.range(of: #"abstract\s*=\s*True"#, options: .regularExpression) != nil { abstract.insert(name); continue }
            tableNames[name] = matches(#"db_table\s*=\s*["']([^"']+)["']"#, body).first.map { group($0, 1, body) } ?? name.lowercased()
        }
        for m in classes {
            let name = group(m, 1, clean), bases = group(m, 2, clean)
            guard !abstract.contains(name) else { continue }
            // An abstract base's fields come first, as Django lays the table out.
            let inherited = bases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { abstract.contains($0) }.compactMap { bodies[$0] }
            let body = joinContinuations(inherited.joined(separator: "\n") + "\n" + group(m, 3, clean))
            guard bases.contains("Model") || bases.split(separator: ",").contains(where: { tableNames[$0.trimmingCharacters(in: .whitespaces)] != nil || abstract.contains($0.trimmingCharacters(in: .whitespaces)) }) else { continue }
            let table = tableNames[name] ?? name.lowercased()
            var columns: [String] = []
            var constraints: [String] = []
            var hasPK = false
            for f in matches(#"(?m)^[ \t]+(\w+)\s*=\s*models\.(\w+)\(([^\n]*)\)[ \t]*$"#, body) {
                let field = group(f, 1, body), kind = group(f, 2, body), args = group(f, 3, body)
                if kind == "ManyToManyField" { continue }
                let nullable = args.range(of: #"null\s*=\s*True"#, options: .regularExpression) != nil
                let primary = args.range(of: #"primary_key\s*=\s*True"#, options: .regularExpression) != nil
                let unique = args.range(of: #"unique\s*=\s*True"#, options: .regularExpression) != nil
                if kind == "ForeignKey" || kind == "OneToOneField" {
                    let target = args.split(separator: ",").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) } ?? ""
                    let targetTable = tableNames[target] ?? target.lowercased()
                    let column = field + "_id"
                    var decl = "\(quote(column)) INTEGER"
                    if !nullable { decl += " NOT NULL" }
                    if kind == "OneToOneField" || unique { decl += " UNIQUE" }
                    columns.append(decl)
                    constraints.append("FOREIGN KEY (\(quote(column))) REFERENCES \(quote(targetTable)) (\(quote("id")))")
                    continue
                }
                var decl = "\(quote(field)) \(djangoType(kind, args: args))"
                if primary { decl += " PRIMARY KEY"; hasPK = true } else if !nullable { decl += " NOT NULL" }
                if unique { decl += " UNIQUE" }
                if let def = matches(#"default\s*=\s*(["'][^"']*["']|[-\d.]+|True|False)"#, args).first {
                    let raw = group(def, 1, args)
                    decl += " DEFAULT \(raw == "True" ? "1" : raw == "False" ? "0" : raw.replacingOccurrences(of: "\"", with: "'"))"
                }
                columns.append(decl)
            }
            if !hasPK { columns.insert("\(quote("id")) INTEGER PRIMARY KEY", at: 0) }
            for ut in matches(#"unique_together\s*=\s*[\[\(]\s*\(([^)]*)\)"#, body) {
                let cols = group(ut, 1, body).components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }.filter { !$0.isEmpty }
                    .map { tableNames.keys.contains(where: { _ in false }) ? $0 : $0 }
                // A foreign-key field in the tuple is its `_id` column.
                let mapped = cols.map { c in columns.contains(where: { $0.hasPrefix(quote(c + "_id")) }) ? c + "_id" : c }
                laterIndexes.append("CREATE UNIQUE INDEX \(quote("\(table)_\(mapped.joined(separator: "_"))_uniq")) ON \(quote(table)) (\(mapped.map(quote).joined(separator: ", ")));")
            }
            out.append("CREATE TABLE \(quote(table)) (\n  " + (columns + constraints).joined(separator: ",\n  ") + "\n);")
        }
        return (out + laterIndexes).joined(separator: "\n")
    }

    private static func djangoType(_ kind: String, args: String) -> String {
        let maxLength = matches(#"max_length\s*=\s*(\d+)"#, args).first.map { group($0, 1, args) }
        switch kind {
        case "CharField", "EmailField", "URLField", "SlugField": return "VARCHAR(\(maxLength ?? "255"))"
        case "FileField", "ImageField", "FilePathField": return "VARCHAR(\(maxLength ?? "100"))"
        case "TextField": return "TEXT"
        case "IntegerField", "PositiveIntegerField", "SmallIntegerField", "PositiveSmallIntegerField", "AutoField": return "INTEGER"
        case "BigIntegerField", "BigAutoField", "PositiveBigIntegerField": return "BIGINT"
        case "BooleanField", "NullBooleanField": return "BOOLEAN"
        case "DateTimeField": return "DATETIME"
        case "DateField": return "DATE"
        case "TimeField": return "TIME"
        case "DurationField": return "BIGINT"
        case "FloatField": return "REAL"
        case "DecimalField":
            let d = matches(#"max_digits\s*=\s*(\d+)"#, args).first.map { group($0, 1, args) }
            let p = matches(#"decimal_places\s*=\s*(\d+)"#, args).first.map { group($0, 1, args) }
            return d.map { "DECIMAL(\($0)\(p.map { ",\($0)" } ?? ""))" } ?? "DECIMAL"
        case "JSONField": return "JSON"
        case "UUIDField": return "UUID"
        case "BinaryField": return "BLOB"
        case "GenericIPAddressField": return "VARCHAR(39)"
        default: return kind.replacingOccurrences(of: "Field", with: "").uppercased()
        }
    }

    // MARK: - Helpers

    /// Lines inside unbalanced parentheses joined into one, so a field written across lines
    /// (`models.ForeignKey(\n  User,\n  on_delete=…\n)`) reads as one declaration.
    public static func joinContinuations(_ text: String) -> String {
        var out: [String] = []
        var depth = 0
        var current = ""
        for line in text.components(separatedBy: "\n") {
            if depth > 0 { current += " " + line.trimmingCharacters(in: .whitespaces) } else { current = line }
            depth += line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
            if depth <= 0 { out.append(current); current = ""; depth = 0 }
        }
        if !current.isEmpty { out.append(current) }
        return out.joined(separator: "\n")
    }

    public static func stripComments(_ text: String, line marker: String) -> String {
        text.components(separatedBy: "\n").map { l in
            // A marker inside a string literal is kept: only strip when no quote precedes it.
            guard let r = l.range(of: marker) else { return l }
            let before = l[..<r.lowerBound]
            let quotes = before.filter { $0 == "\"" || $0 == "'" }.count
            return quotes % 2 == 0 ? String(before) : l
        }.joined(separator: "\n")
    }

    public static func matches(_ pattern: String, _ text: String, anchorsMatchLines: Bool = false) -> [NSTextCheckingResult] {
        var opts: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if anchorsMatchLines { opts.insert(.anchorsMatchLines) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return [] }
        return re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    public static func group(_ m: NSTextCheckingResult, _ i: Int, _ text: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : (text as NSString).substring(with: r)
    }

    public static func firstString(in s: String) -> String? { matches(#""([^"]+)""#, s).first.map { group($0, 1, s) } }

    /// `[a, b]` → ["a", "b"], quotes and spaces removed.
    public static func bracketList(in s: String) -> [String] {
        guard let m = matches(#"\[([^\]]*)\]"#, s).first else { return [] }
        return group(m, 1, s).components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"':")) }.filter { !$0.isEmpty }
    }

    public static func list(named name: String, in s: String) -> [String] {
        guard let m = matches(name + #"\s*:\s*\[([^\]]*)\]"#, s).first else { return [] }
        return group(m, 1, s).components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A default SQLite can hold as a literal; nil for `now()`, `uuid()`, `autoincrement()`.
    public static func literalDefault(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        if v == "true" { return "1" }
        if v == "false" { return "0" }
        if v.hasPrefix("\"") { return "'" + v.dropFirst().dropLast().replacingOccurrences(of: "'", with: "''") + "'" }
        if Double(v) != nil { return v }
        if v.range(of: #"^[A-Z_]+$"#, options: .regularExpression) != nil { return "'\(v)'" }   // an enum value
        return nil
    }

    public static func plural(_ s: String) -> String {
        if s.hasSuffix("y"), !s.hasSuffix("ey"), !s.hasSuffix("ay") { return String(s.dropLast()) + "ies" }
        if s.hasSuffix("s") || s.hasSuffix("x") || s.hasSuffix("ch") || s.hasSuffix("sh") { return s + "es" }
        return s + "s"
    }

    public static func singular(_ s: String) -> String {
        if s.hasSuffix("ies") { return String(s.dropLast(3)) + "y" }
        if s.hasSuffix("ses") || s.hasSuffix("xes") || s.hasSuffix("ches") || s.hasSuffix("shes") { return String(s.dropLast(2)) }
        if s.hasSuffix("s") { return String(s.dropLast()) }
        return s
    }
}
