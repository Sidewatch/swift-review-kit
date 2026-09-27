//
//  DependencyManifest.swift
//  ChangeFacts
//
//  Recognises a dependency manifest or lockfile from its filename.
//
//  Created by David Sherlock on 9/11/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Recognises a dependency manifest or lockfile from its filename.
///
/// An agent editing `Package.swift` is not doing the same thing as an agent editing a source
/// file: it is pulling in code you have not read, from a registry, on a name it may well have
/// invented. That is the highest-risk edit an agent can make and the easiest to miss, because
/// in a list of twenty changed files it looks like row eleven.
///
/// This renders a FACT and nothing else: the file's name says it is a manifest. There is no
/// score, no severity, no opinion about the dependency. Matching is on the name alone — never
/// on contents — so it costs one string comparison per row and cannot be wrong about a file it
/// has not read.
public enum DependencyManifest {

    /// Exact filenames that declare or lock dependencies, mapped to the ecosystem people call
    /// them by. Exact names only: a `*.lock` glob would claim `.terraform.lock.hcl` and
    /// `Podfile.lock` alike and say the wrong ecosystem for both.
    private static let known: [String: String] = [
        "Package.swift": "Swift Package Manager", "Package.resolved": "Swift Package Manager",
        "Podfile": "CocoaPods", "Podfile.lock": "CocoaPods",
        "Cartfile": "Carthage", "Cartfile.resolved": "Carthage",
        "package.json": "npm", "package-lock.json": "npm",
        "yarn.lock": "Yarn", "pnpm-lock.yaml": "pnpm", "bun.lockb": "Bun",
        "Cargo.toml": "Cargo", "Cargo.lock": "Cargo",
        "go.mod": "Go modules", "go.sum": "Go modules",
        "Gemfile": "Bundler", "Gemfile.lock": "Bundler",
        "requirements.txt": "pip", "pyproject.toml": "Python", "poetry.lock": "Poetry",
        "Pipfile": "Pipenv", "Pipfile.lock": "Pipenv", "uv.lock": "uv",
        "composer.json": "Composer", "composer.lock": "Composer",
        "pom.xml": "Maven", "build.gradle": "Gradle", "build.gradle.kts": "Gradle",
        "gradle.lockfile": "Gradle",
        "pubspec.yaml": "Pub", "pubspec.lock": "Pub",
        "mix.exs": "Hex", "mix.lock": "Hex",
        "Gopkg.toml": "dep", "Gopkg.lock": "dep",
        "deno.json": "Deno", "deno.lock": "Deno",
    ]

    /// The ecosystem this path declares dependencies for, or `nil` when it is an ordinary file.
    ///
    /// - Parameter path: A repo-relative or absolute path; only the last component is read.
    /// - Returns: The ecosystem's display name, e.g. `"npm"`.
    public static func ecosystem(forPath path: String) -> String? {
        known[(path as NSString).lastPathComponent]
    }

    /// Whether `path` names a dependency manifest or lockfile.
    public static func isManifest(_ path: String) -> Bool { ecosystem(forPath: path) != nil }

    /// The row's tool tip: says what it is and why it is marked, without telling the reviewer
    /// what to conclude.
    public static func tooltip(forPath path: String) -> String? {
        ecosystem(forPath: path).map {
            "\($0) dependency manifest — this change alters what third-party code the project pulls in."
        }
    }
}
