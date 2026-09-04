import Foundation
import ProcessRunner

/// Posts the Notes-for-Agent draft to the current branch's GitHub pull request
/// as **inline review comments**: one `event: COMMENT` review whose `comments`
/// array pins each note to its `file:line` on the `RIGHT` side of the diff (the
/// modern line-based review API — no diff-position math). Notes on files that
/// aren't part of the PR's diff are folded into the review's top-level `body`
/// (the API rejects paths outside the diff with a 422).
///
/// Fallback chain, fully automatic:
/// 1. Inline review via `gh api POST /repos/{owner}/{repo}/pulls/{n}/reviews`.
/// 2. On a 422 whose error body names specific comment paths, retry **once**
///    with those comments folded into the review body.
/// 3. On any other failure (or an unidentifiable 422), the whole batch posts as
///    today's single consolidated comment: `gh pr review --comment --body-file`.
public enum PRReviewExporter {

    /// The outcome of one export, for the panel's status label.
    public enum Outcome: Equatable, Sendable {
        /// The inline review posted: `inline` comments pinned to lines, `inBody` folded into the review body.
        case inline(inline: Int, inBody: Int)
        /// The inline path failed but the consolidated single-comment fallback posted.
        case consolidated
        /// Every path failed; `message` is the first error line for the status label.
        case failure(String)
    }

    /// Exports `comments` to the branch's PR. Blocking (runs `gh` several times) — call off-main.
    ///
    /// - Parameters:
    ///   - gh: Absolute path of the `gh` CLI.
    ///   - repoRoot: The repository root `gh` should run in.
    ///   - comments: The draft's notes; `file` is repo-relative (how the API wants `path`).
    ///   - consolidatedMarkdown: The full-batch markdown used by every consolidated fallback.
    public static func export(gh: String, repoRoot: URL, comments: [ReviewComment],
                       consolidatedMarkdown: String) -> Outcome {
        guard let ownerRepo = nameWithOwner(gh: gh, in: repoRoot),
              let prNumber = pullRequestNumber(gh: gh, in: repoRoot) else {
            return consolidatedFallback(gh: gh, in: repoRoot, markdown: consolidatedMarkdown)
        }

        // Pre-split: notes on files the PR doesn't touch go straight to the body.
        // `changedPaths` is best-effort — nil (query failed) means "assume in-diff"
        // and let the 422 retry sort out any stragglers.
        let changedPaths = prChangedPaths(gh: gh, in: repoRoot)
        var inline = comments, inBody = [ReviewComment]()
        if let changed = changedPaths {
            inline = comments.filter { changed.contains($0.file) }
            inBody = comments.filter { !changed.contains($0.file) }
        }
        guard !inline.isEmpty else {
            // Nothing can be pinned to the diff — the consolidated comment already
            // carries the whole batch, so just post that.
            return consolidatedFallback(gh: gh, in: repoRoot, markdown: consolidatedMarkdown)
        }

        // Attempt the inline review; on an identifiable 422 retry once with the
        // rejected paths' comments folded into the body.
        for attempt in 0 ..< 2 {
            guard let payload = reviewPayload(inline: inline, inBody: inBody) else { break }
            let r = run(gh, args: ["api", "repos/\(ownerRepo)/pulls/\(prNumber)/reviews",
                                   "--method", "POST", "--input", "-"],
                        in: repoRoot, stdin: payload)
            if r.status == 0 { return .inline(inline: inline.count, inBody: inBody.count) }

            guard attempt == 0, r.stderr.contains("HTTP 422") else { break }
            let rejected = rejectedPaths(inErrorBody: r.stdout,
                                         candidates: Set(inline.map(\.file)))
            guard !rejected.isEmpty else { break }
            inBody += inline.filter { rejected.contains($0.file) }
            inline = inline.filter { !rejected.contains($0.file) }
            guard !inline.isEmpty else { break }
        }
        return consolidatedFallback(gh: gh, in: repoRoot, markdown: consolidatedMarkdown)
    }

    // MARK: - gh queries

    /// `owner/repo` via `gh repo view --json nameWithOwner`; nil on any failure.
    private static func nameWithOwner(gh: String, in root: URL) -> String? {
        let r = run(gh, args: ["repo", "view", "--json", "nameWithOwner"], in: root)
        guard r.status == 0,
              let obj = JSONObject.parse(r.stdout),
              let name = obj["nameWithOwner"] as? String, !name.isEmpty else { return nil }
        return name
    }

    /// The branch's PR number via `gh pr view --json number`; nil when the branch has no PR.
    private static func pullRequestNumber(gh: String, in root: URL) -> Int? {
        let r = run(gh, args: ["pr", "view", "--json", "number"], in: root)
        guard r.status == 0,
              let obj = JSONObject.parse(r.stdout),
              let number = obj["number"] as? Int else { return nil }
        return number
    }

    /// The repo-relative paths the PR touches, via `gh pr view --json files`.
    /// Nil when the query fails — callers then assume every file is in the diff.
    private static func prChangedPaths(gh: String, in root: URL) -> Set<String>? {
        let r = run(gh, args: ["pr", "view", "--json", "files"], in: root)
        guard r.status == 0,
              let obj = JSONObject.parse(r.stdout),
              let files = obj["files"] as? [[String: Any]] else { return nil }
        return Set(files.compactMap { $0["path"] as? String })
    }

    // MARK: - Payload

    /// The `POST …/reviews` JSON body: `event: COMMENT`, a top-level `body`
    /// carrying the out-of-diff notes (empty string when there are none), and a
    /// `comments` array of `{path, line, side: "RIGHT", body}`. Built with
    /// `JSONSerialization` so note text is never string-interpolated into JSON.
    static func reviewPayload(inline: [ReviewComment], inBody: [ReviewComment]) -> Data? {
        let payload: [String: Any] = [
            "event": "COMMENT",
            "body": bodyMarkdown(inBody),
            "comments": inline.map { c -> [String: Any] in
                ["path": c.file,
                 "line": c.line,
                 "side": "RIGHT",
                 "body": "**[\(c.severity.rawValue)]** \(c.note)"]
            },
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// The review's top-level body: the out-of-diff notes as a bullet list, or ""
    /// when every note landed inline.
    static func bodyMarkdown(_ notes: [ReviewComment]) -> String {
        guard !notes.isEmpty else { return "" }
        var out = "Notes on files outside this PR's diff:\n\n"
        for c in notes.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
            // Indent continuation lines so a multi-line note stays inside its bullet.
            let note = c.note.replacingOccurrences(of: "\n", with: "\n  ")
            out += "- **[\(c.severity.rawValue)]** `\(c.file):\(c.line)` — \(note)\n"
        }
        return out.trimmed
    }

    /// Scans a 422 response body for `candidates` paths named in its `errors`
    /// array (entries can be strings or objects). Only paths the API explicitly
    /// echoed back are returned — an empty set means the reject is unidentifiable
    /// and the caller should fall back for the whole batch.
    static func rejectedPaths(inErrorBody data: Data, candidates: Set<String>) -> Set<String> {
        guard let obj = JSONObject.parse(data) else { return [] }
        var texts: [String] = []
        if let message = obj["message"] as? String { texts.append(message) }
        for e in obj["errors"] as? [Any] ?? [] {
            if let s = e as? String { texts.append(s) }
            if let d = e as? [String: Any] {
                texts += d.values.compactMap { $0 as? String }
            }
        }
        return candidates.filter { path in texts.contains { $0.contains(path) } }
    }

    // MARK: - Consolidated fallback

    /// Today's behavior, kept as the terminal fallback: the whole batch as one
    /// PR comment via `gh pr review --comment --body-file`.
    private static func consolidatedFallback(gh: String, in root: URL, markdown: String) -> Outcome {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-export-\(UUID().uuidString).md")
        do { try markdown.write(to: tmp, atomically: true, encoding: .utf8) }
        catch { return .failure("Could not write review file") }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let r = run(gh, args: ["pr", "review", "--comment", "--body-file", tmp.path], in: root)
        guard r.status == 0 else { return .failure(firstErrorLine(of: r)) }
        return .consolidated
    }

    /// The first stderr line of a failed run (e.g. "no pull requests found for
    /// branch …"), for the panel's status label.
    private static func firstErrorLine(of r: (status: Int32, stdout: Data, stderr: String)) -> String {
        let line = r.stderr
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? "gh exited with status \(r.status)"
        return line.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Process plumbing

    /// Runs `tool args` in `dir`, optionally feeding `stdin`, and returns the
    /// exit status plus captured stdout (raw — it's parsed as JSON) and stderr.
    /// stdout is drained on a background queue while stderr is read here, so
    /// neither pipe can fill up and deadlock the child. Blocking — call off-main.
    private static func run(_ tool: String, args: [String], in dir: URL,
                            stdin input: Data? = nil) -> (status: Int32, stdout: Data, stderr: String) {
        // This copy drained stdout concurrently but wrote stdin AFTER starting the drain
        // and read stderr on the calling thread — safe in practice, but only by ordering.
        // Subprocess makes the safe ordering structural.
        let result = ProcessRunner.run(tool, args, directory: dir, input: input)
        guard result.launched else { return (-1, Data(), "Could not launch gh") }
        return (result.status, result.stdout, result.errorText)
    }
}
