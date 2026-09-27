//
//  AddedLineSurfaceTests.swift
//  ChangeFactsTests
//
//  Environment names and hosts on added lines, per language; minus what HEAD already used.
//
//  Created by David Sherlock on 9/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ChangeFacts

final class AddedLineSurfaceTests: XCTestCase {
    typealias Surface = AddedLineSurface

    func testJavaScriptFormsAndHosts() {
        let js =
            "const key = process.env.STRIPE_KEY;\nconst dsn = process.env['SENTRY_DSN'];\n// see https://docs.example.com and https://github.com/x/y\nfetch('https://api.stripe.com/v1/charges');\nfetch(`http://localhost:3000/x`);\nconst hook = 'https://hooks.slack.com/services/T/B';\n"
        XCTAssertEqual(
            Surface.scan(js, path: "src/pay.js"),
            Surface.Findings(envNames: ["SENTRY_DSN", "STRIPE_KEY"], hosts: ["api.stripe.com", "hooks.slack.com"]),
            "process.env in both forms; hosts from string URLs, not from comments, never localhost")
    }

    func testEveryLanguagesEnvironmentReads() {
        XCTAssertEqual(
            Surface.scan("k = os.environ['A_KEY']\nu = os.getenv(\"B_URL\")\nv = os.environ.get('C')\n", path: "app.py").envNames,
            ["A_KEY", "B_URL", "C"])
        XCTAssertEqual(Surface.scan("ENV['D_TOKEN'] || ENV.fetch(\"E_HOST\")\n", path: "config.rb").envNames, ["D_TOKEN", "E_HOST"])
        XCTAssertEqual(
            Surface.scan("v := os.Getenv(\"F_PORT\")\nw, ok := os.LookupEnv(\"G\")\n", path: "main.go").envNames, ["F_PORT", "G"])
        XCTAssertEqual(Surface.scan("let t = ProcessInfo.processInfo.environment[\"H_TOKEN\"]\n", path: "App.swift").envNames, ["H_TOKEN"])
        XCTAssertEqual(
            Surface.scan("$k = env('I_KEY'); $j = getenv(\"J\"); $l = $_ENV['L'];\n", path: "cfg.php").envNames, ["I_KEY", "J", "L"])
        XCTAssertEqual(Surface.scan("String k = System.getenv(\"K_URL\");\n", path: "Cfg.java").envNames, ["K_URL"])
        XCTAssertEqual(Surface.scan("let m = std::env::var(\"M_KEY\")?;\n", path: "main.rs").envNames, ["M_KEY"])
        XCTAssertEqual(Surface.scan("System.get_env(\"N_DB\")\n", path: "config.exs").envNames, ["N_DB"])
    }

    func testOnlyWhatTheFileDidNotAlreadyUse() {
        XCTAssertEqual(
            Surface.findings(
                oldText: "a = process.env.OLD_KEY\nfetch('https://api.old.com')\n",
                newText:
                    "b = 1\na = process.env.OLD_KEY\nc = process.env.NEW_KEY\nfetch('https://api.old.com')\nfetch('https://api.new.com')\n",
                path: "x.js", addedLines: [1, 2, 3, 4, 5]),
            Surface.Findings(envNames: ["NEW_KEY"], hosts: ["api.new.com"]), "a moved line adds nothing")
        XCTAssertEqual(
            Surface.findings(
                oldText: nil, newText: "x = process.env.FRESH\n/* https://in.a.comment.io */\n", path: "y.ts", addedLines: nil),
            Surface.Findings(envNames: ["FRESH"], hosts: []), "an untracked file reports all; a comment's host does not count")
    }

    func testSkipsAndIgnoredHosts() {
        XCTAssertFalse(Surface.isScannable("package.json"))
        XCTAssertFalse(Surface.isScannable("yarn.lock"))
        XCTAssertFalse(Surface.isScannable("README.md"))
        XCTAssertFalse(Surface.isScannable("src/pay.test.js"))
        XCTAssertFalse(Surface.isScannable("node_modules/x/i.js"))
        XCTAssertTrue(Surface.isScannable("src/pay.js"))
        XCTAssertTrue(
            Surface.scan(
                "<svg xmlns=\"http://www.w3.org/2000/svg\"/>; fetch('https://example.com'); fetch('https://json-schema.org/x')",
                path: "a.js"
            ).hosts.isEmpty)
    }

    func testTooltip() {
        XCTAssertEqual(
            Surface.tooltip(Surface.Findings(envNames: ["A", "B"], hosts: ["api.x.com"])),
            "Reads new environment variables: A, B · Calls new host: api.x.com")
        XCTAssertEqual(Surface.tooltip(Surface.Findings(envNames: ["A"], hosts: [])), "Reads new environment variable: A")
        XCTAssertNil(Surface.tooltip(Surface.Findings(envNames: [], hosts: [])))
    }
}
