//
//  TestRuns.swift
//  ChangeFacts
//
//  The test runs a shell line made and what each reported, read from the runner's own summary.
//
//  Created by David Sherlock on 9/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The test runs a shell line shows (`swift test`, `pytest`, `go test`, `jest`, `rspec`, … one
/// reader per runner family) and what each REPORTED, read from the runner's own summary line
/// ("Executed 12 tests, with 0 failures", "Tests: 1 failed, 4 passed, 5 total").
///
/// An unreadable summary is `.unknown`, never guessed from the exit status; facts about how the
/// work was checked, not a verdict on it.
public enum TestRuns {

    /// What a run reported: no failures, some, or nothing readable.
    public enum Outcome: Sendable, Equatable { case passed, failed, unknown }

    /// The counts a runner's summary reported.
    public struct Report: Equatable, Sendable {
        /// Tests reported passing; nil when the summary gave no count.
        public let passed: Int?
        /// Tests reported failing; nil when the summary gave no count.
        public let failed: Int?
        /// The run's outcome as the counts decide it.
        public let outcome: Outcome

        /// Creates a report from its parts.
        public init(passed: Int?, failed: Int?, outcome: Outcome) {
            self.passed = passed
            self.failed = failed
            self.outcome = outcome
        }

        /// No summary could be read.
        public static let unknown = Report(passed: nil, failed: nil, outcome: .unknown)

        /// A report from the counts: `.failed` when any failed, `.passed` otherwise, `.unknown`
        /// when neither count was read.
        static func verdict(_ passed: Int?, _ failed: Int?) -> Report {
            guard passed != nil || failed != nil else { return .unknown }
            return Report(passed: passed, failed: failed, outcome: (failed ?? 0) > 0 ? .failed : .passed)
        }
    }

    /// One test run: the runner, the segment that invoked it, and what it reported.
    public struct Run: Equatable, Sendable {
        /// "swift test", "pytest", "go test" — the runner by its own name.
        public let runner: String
        /// The shell segment that ran it.
        public let command: String
        /// Tests reported passing; nil when the summary gave no count.
        public let passed: Int?
        /// Tests reported failing; nil when the summary gave no count.
        public let failed: Int?
        /// The run's outcome as the counts decide it.
        public let outcome: Outcome
        /// Whatever the caller attached: a transcript's `HH:MM`, or `""`.
        public let timestamp: String

        /// Creates a run from its parts.
        public init(runner: String, command: String, passed: Int?, failed: Int?, outcome: Outcome, timestamp: String) {
            self.runner = runner
            self.command = command
            self.passed = passed
            self.failed = failed
            self.outcome = outcome
            self.timestamp = timestamp
        }

        /// "swift test: 12 passed, 0 failed", "pytest: 40 passed, 2 failed", "go test: FAIL",
        /// "npm test: no summary".
        public var summary: String {
            switch (outcome, passed, failed) {
            case (.unknown, _, _):
                return String(
                    localized: "\(runner): no summary", bundle: .module,
                    comment: "Test run row; the argument is the test runner, such as npm test. The runner printed no readable result")
            case (_, let p?, let f?):
                return String(
                    localized: "\(runner): \(p) passed, \(f) failed", bundle: .module,
                    comment: "Test run row: the test runner, then how many tests passed and failed")
            case (_, let p?, nil):
                return String(
                    localized: "\(runner): \(p) passed", bundle: .module,
                    comment: "Test run row: the test runner, then how many tests passed")
            case (_, nil, let f?):
                return String(
                    localized: "\(runner): \(f) failed", bundle: .module,
                    comment: "Test run row: the test runner, then how many tests failed")
            default:
                return outcome == .passed
                    ? String(
                        localized: "\(runner): passed", bundle: .module,
                        comment: "Test run row: the test runner, then its verdict with no counts")
                    : String(
                        localized: "\(runner): FAIL", bundle: .module,
                        comment: "Test run row: the test runner, then its verdict with no counts")
            }
        }
    }

    // MARK: - Test files

    /// A test file, by the paths and names the frameworks use: a `test`, `tests`, `__tests__`,
    /// `spec`, `specs` or `testing` folder, a `.test.` / `.spec.` / `_test.` / `_spec.` name,
    /// `test_*.py`, `*Tests.swift`, `*Test.java` / `.kt` / `.cs` / `.php` / `.scala`.
    public static func isTestPath(_ path: String) -> Bool {
        let p = "/" + path.lowercased()
        if ["/test/", "/tests/", "/__tests__/", "/spec/", "/specs/", "/testing/"].contains(where: { p.contains($0) }) { return true }
        let original = (path as NSString).lastPathComponent
        let name = original.lowercased()
        if [".test.", ".spec.", "_test.", "_spec."].contains(where: { name.contains($0) }) || name.hasPrefix("test_") { return true }
        // CamelCase suites: FooTests.swift, UserTest.java — a capital T, so `attest.go` is not one.
        return original.range(of: #"Tests?\.(swift|java|kt|cs|php|scala)$"#, options: .regularExpression) != nil
    }

    /// "12 changed files, none are tests" / "12 changed files, 3 are tests"; `nil` for no files.
    public static func testFilesTally(_ paths: [String]) -> String? {
        guard !paths.isEmpty else { return nil }
        let tests = paths.filter(isTestPath).count
        if tests == 0 {
            return String(
                localized: "\(paths.count) changed files, none are tests", bundle: .module, comment: "Tool-tip on the changed-files count")
        }
        return String(
            localized: "\(paths.count) changed files, \(tests) are tests", bundle: .module,
            comment: "Tool-tip on the changed-files count: how many files changed, then how many of them are test files")
    }

    // MARK: - Runs

    /// The test runs one shell line made, each read against the line's output — a line's
    /// segments share one result, so a `swift build && swift test` reports the Swift suite.
    ///
    /// - Parameters:
    ///   - command: The line as the agent ran it.
    ///   - output: What the tool returned (its tail is enough: summaries come last).
    ///   - isError: Whether the tool reported an error — never decisive on its own.
    ///   - timestamp: Carried onto each run, for a row.
    public static func runs(in command: String, output: String, isError: Bool, timestamp: String = "") -> [Run] {
        ShellCommandLine.segments(of: command).compactMap { segment in
            guard let runner = runner(of: segment) else { return nil }
            let report = parse(runner: runner, output: output, isError: isError)
            return Run(
                runner: runner, command: segment, passed: report.passed, failed: report.failed,
                outcome: report.outcome, timestamp: timestamp)
        }
    }

    /// The test runner a shell segment invokes, by its own name, or `nil`.
    public static func runner(of segment: String) -> String? {
        guard let call = ShellCommandLine.invocation(of: segment) else { return nil }
        let tool = call.tool, args = call.arguments
        let sub = args.first(where: { !$0.hasPrefix("-") }) ?? ""
        switch tool {
        case "swift": return sub == "test" ? "swift test" : nil
        case "xcodebuild": return args.contains("test") || args.contains("test-without-building") ? "xcodebuild test" : nil
        case "npm", "pnpm", "yarn", "bun":
            let script = args.first == "run" || args.first == "run-script" ? (args.dropFirst().first ?? "") : (args.first ?? "")
            if script == "test" || script.hasPrefix("test:") || script == "t" { return "\(tool) test" }
            return tool == "bun" && script == "test" ? "bun test" : nil
        case "jest", "vitest", "mocha", "ava", "tap", "karma": return tool
        case "playwright", "cypress": return sub == "test" || sub == "run" ? "\(tool) test" : nil
        case "pytest", "py.test": return "pytest"
        case "-m":  // python -m pytest / unittest: the interpreter rule left "-m" as the tool
            return ["pytest", "unittest"].contains(args.first ?? "") ? args.first! : nil
        case "go": return sub == "test" ? "go test" : nil
        case "cargo": return sub == "test" || sub == "nextest" ? "cargo test" : nil
        case "rspec": return "rspec"
        case "rails", "rake": return sub == "test" || sub.hasPrefix("test:") || sub == "spec" ? "\(tool) test" : nil
        case "phpunit", "pest": return tool
        case "artisan": return sub == "test" ? "artisan test" : nil
        case "mix": return sub == "test" ? "mix test" : nil
        case "dotnet": return sub == "test" ? "dotnet test" : nil
        case "gradle", "gradlew": return args.contains("test") || args.contains("check") ? "gradle test" : nil
        case "mvn", "mvnw": return args.contains("test") || args.contains("verify") ? "mvn test" : nil
        case "flutter", "dart": return sub == "test" ? "\(tool) test" : nil
        case "deno": return sub == "test" ? "deno test" : nil
        case "ctest": return "ctest"
        case "make", "just": return sub == "test" || sub == "check" ? "\(tool) \(sub)" : nil
        default: return nil
        }
    }

    // MARK: - Reading the summary

    /// The counts a runner's summary reports, read from the END of its output. `isError` alone
    /// never decides: a runner that failed without a summary is `.unknown`, and said so.
    public static func parse(runner: String, output: String, isError: Bool) -> Report {
        let report: Report?
        switch runner {
        case "swift test", "xcodebuild test": report = xctest(output)
        case "npm test", "pnpm test", "yarn test", "bun test", "jest", "vitest", "playwright test", "cypress test", "ava", "tap", "karma",
            "mocha":
            report = javascript(output)
        case "pytest", "unittest": report = python(output)
        case "go test": report = go(output)
        case "cargo test": report = cargo(output)
        case "rspec": report = rspec(output)
        case "rails test", "rake test": report = minitest(output)
        case "phpunit", "pest", "artisan test": report = php(output)
        case "mix test": report = exunit(output)
        case "dotnet test": report = dotnet(output)
        case "flutter test", "dart test": report = dart(output)
        case "gradle test", "mvn test": report = jvm(output)
        case "deno test": report = deno(output)
        case "ctest": report = ctest(output)
        default: report = nil
        }
        return report ?? .unknown
    }

    private static func last(_ pattern: String, _ text: String) -> [String]? { RegexMatches.last(pattern, in: text) }
    private static func int(_ s: String) -> Int? { Int(s.replacingOccurrences(of: ",", with: "")) }
    private static func count(_ pattern: String, _ text: String) -> Int { RegexMatches.all(pattern, in: text).count }

    /// XCTest and Swift Testing, through `swift test` or `xcodebuild test`.
    private static func xctest(_ text: String) -> Report? {
        if let m = last(#"Executed (\d+) tests?, with (\d+) failures?"#, text), let t = int(m[1]), let f = int(m[2]) {
            return .verdict(t - f, f)
        }
        if let m = last(#"Test run with (\d+) tests? (?:in .*? )?passed"#, text), let t = int(m[1]) { return .verdict(t, 0) }
        if let m = last(#"Test run with (\d+) tests? (?:in .*? )?failed after .*? with (\d+) issues?"#, text), let t = int(m[1]),
            let f = int(m[2])
        {
            return .verdict(t - f, f)
        }
        if text.contains("** TEST SUCCEEDED **") { return Report(passed: nil, failed: nil, outcome: .passed) }
        if text.contains("** TEST FAILED **") { return Report(passed: nil, failed: nil, outcome: .failed) }
        return nil
    }

    /// jest, vitest, mocha, bun / playwright, tap / node:test — whichever wrote the summary.
    private static func javascript(_ text: String) -> Report? {
        if let m = last(#"Tests:\s+(?:(\d+) failed, )?(?:(\d+) skipped, )?(?:(\d+) todo, )?(\d+) passed, (\d+) total"#, text) {  // jest
            return .verdict(int(m[4]), int(m[1].isEmpty ? "0" : m[1]))
        }
        // vitest
        if let m = last(#"Tests\s+(?:(\d+) failed \| )?(\d+) passed"#, text) { return .verdict(int(m[2]), int(m[1].isEmpty ? "0" : m[1])) }
        if let m = last(#"(\d+) passing"#, text) { return .verdict(int(m[1]), int(last(#"(\d+) failing"#, text)?[1] ?? "0")) }  // mocha
        // bun, playwright
        if let m = last(#"(\d+) pass(?:ed)?\b"#, text) { return .verdict(int(m[1]), int(last(#"(\d+) fail(?:ed)?\b"#, text)?[1] ?? "0")) }
        // tap / node:test
        if let m = last(#"# pass\s+(\d+)"#, text) { return .verdict(int(m[1]), int(last(#"# fail\s+(\d+)"#, text)?[1] ?? "0")) }
        return nil
    }

    /// pytest's summary lists what happened in whatever order it happened ("2 failed, 40
    /// passed", "40 passed, 2 failed", "1 error"), so each count is read on its own; unittest
    /// prints "Ran N tests" then OK or FAILED.
    private static func python(_ text: String) -> Report? {
        let p = last(#"(\d+) passed\b"#, text).flatMap { int($0[1]) }
        let f = last(#"(\d+) failed\b"#, text).flatMap { int($0[1]) }
        let e = last(#"(\d+) errors?\b"#, text).flatMap { int($0[1]) }
        if p != nil || f != nil || e != nil { return .verdict(p ?? 0, (f ?? 0) + (e ?? 0)) }
        if text.contains("no tests ran") { return Report(passed: 0, failed: 0, outcome: .passed) }
        if let m = last(#"Ran (\d+) tests?"#, text), let t = int(m[1]) {  // unittest
            if text.contains("\nOK") || text.hasSuffix("OK") { return .verdict(t, 0) }
            if let f = last(#"FAILED \((?:failures=(\d+))?(?:, )?(?:errors=(\d+))?"#, text) {
                let n = (int(f[1]) ?? 0) + (int(f[2]) ?? 0); return .verdict(t - n, n)
            }
        }
        return nil
    }

    /// `go test`: a `--- FAIL` per failing test, `FAIL` or `ok` per package.
    private static func go(_ text: String) -> Report? {
        let fails = count(#"(?m)^--- FAIL"#, text)
        if fails > 0 { return Report(passed: nil, failed: fails, outcome: .failed) }
        if count(#"(?m)^FAIL\b"#, text) > 0 { return Report(passed: nil, failed: nil, outcome: .failed) }
        if count(#"(?m)^(?:ok|PASS)\b"#, text) > 0 { return Report(passed: nil, failed: nil, outcome: .passed) }
        return nil
    }

    /// `cargo test`: one "test result" line per target, summed.
    private static func cargo(_ text: String) -> Report? {
        let results = RegexMatches.all(#"test result: (ok|FAILED)\. (\d+) passed; (\d+) failed"#, in: text)
        guard !results.isEmpty else { return nil }
        return .verdict(results.compactMap { int($0[2]) }.reduce(0, +), results.compactMap { int($0[3]) }.reduce(0, +))
    }

    private static func rspec(_ text: String) -> Report? {
        guard let m = last(#"(\d+) examples?, (\d+) failures?"#, text), let t = int(m[1]), let f = int(m[2]) else { return nil }
        return .verdict(t - f, f)
    }

    /// Rails / minitest: "20 runs, 41 assertions, 1 failures, 1 errors, 0 skips".
    private static func minitest(_ text: String) -> Report? {
        guard let m = last(#"(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors"#, text),
            let t = int(m[1]), let f = int(m[2]), let e = int(m[3])
        else { return nil }
        return .verdict(t - f - e, f + e)
    }

    /// PHPUnit's "OK (15 tests…)" or "Tests: 15, … Failures: 2", and Pest's "Tests: 1 failed, 4 passed".
    private static func php(_ text: String) -> Report? {
        if let m = last(#"OK \((\d+) tests?"#, text) { return .verdict(int(m[1]), 0) }
        if let m = last(#"Tests: (\d+), Assertions: \d+(?:, Errors: (\d+))?(?:, Failures: (\d+))?"#, text), let t = int(m[1]) {
            let n = (int(m[2]) ?? 0) + (int(m[3]) ?? 0)
            return .verdict(t - n, n)
        }
        // pest
        if let m = last(#"Tests:\s+(?:(\d+) failed, )?(\d+) passed"#, text) { return .verdict(int(m[2]), int(m[1].isEmpty ? "0" : m[1])) }
        return nil
    }

    private static func exunit(_ text: String) -> Report? {
        guard let m = last(#"(\d+) tests?, (\d+) failures?"#, text), let t = int(m[1]), let f = int(m[2]) else { return nil }
        return .verdict(t - f, f)
    }

    private static func dotnet(_ text: String) -> Report? {
        if let m = last(#"(?:Passed|Failed)!\s+- Failed:\s+(\d+), Passed:\s+(\d+)"#, text) { return .verdict(int(m[2]), int(m[1])) }
        if let m = last(#"Total tests: (\d+)[\s\S]*?Passed: (\d+)[\s\S]*?Failed: (\d+)"#, text) { return .verdict(int(m[2]), int(m[3])) }
        return nil
    }

    /// Flutter and Dart: the running "+12 -1:" counter, then "All tests passed!" or "Some tests failed."
    private static func dart(_ text: String) -> Report? {
        if text.contains("All tests passed!") { return Report(passed: int(last(#"\+(\d+)"#, text)?[1] ?? ""), failed: 0, outcome: .passed) }
        if text.contains("Some tests failed.") {
            return Report(passed: int(last(#"\+(\d+)"#, text)?[1] ?? ""), failed: int(last(#"-(\d+):"#, text)?[1] ?? ""), outcome: .failed)
        }
        return nil
    }

    /// Gradle and Maven: Surefire's "Tests run: 30, Failures: 1, Errors: 0", else the build verdict.
    private static func jvm(_ text: String) -> Report? {
        let sure = RegexMatches.all(#"Tests run: (\d+), Failures: (\d+), Errors: (\d+)"#, in: text)
        if let m = sure.last, let t = int(m[1]), let f = int(m[2]), let e = int(m[3]) { return .verdict(t - f - e, f + e) }
        if text.contains("BUILD SUCCESSFUL") { return Report(passed: nil, failed: nil, outcome: .passed) }
        if text.contains("BUILD FAILED") { return Report(passed: nil, failed: nil, outcome: .failed) }
        return nil
    }

    private static func deno(_ text: String) -> Report? {
        guard let m = last(#"(ok|FAILED) \| (\d+) passed \| (\d+) failed"#, text) else { return nil }
        return .verdict(int(m[2]), int(m[3]))
    }

    private static func ctest(_ text: String) -> Report? {
        guard let m = last(#"(\d+)% tests passed, (\d+) tests failed out of (\d+)"#, text), let f = int(m[2]), let t = int(m[3]) else {
            return nil
        }
        return .verdict(t - f, f)
    }
}
