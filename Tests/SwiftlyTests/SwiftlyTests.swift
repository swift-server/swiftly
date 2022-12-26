import _StringProcessing
import ArgumentParser
@testable import Swiftly
@testable import SwiftlyCore
import XCTest

struct SwiftlyTestError: LocalizedError {
    let message: String
}

class SwiftlyTests: XCTestCase {
    // Below are some constants that can be used to write test cases.
    static let oldStable = ToolchainVersion(major: 5, minor: 6, patch: 0)
    static let oldStableNewPatch = ToolchainVersion(major: 5, minor: 6, patch: 3)
    static let newStable = ToolchainVersion(major: 5, minor: 7, patch: 0)
    static let oldMainSnapshot = ToolchainVersion(snapshotBranch: .main, date: "2022-09-10")
    static let newMainSnapshot = ToolchainVersion(snapshotBranch: .main, date: "2022-10-22")
    static let oldReleaseSnapshot = ToolchainVersion(snapshotBranch: .release(major: 5, minor: 7), date: "2022-08-27")
    static let newReleaseSnapshot = ToolchainVersion(snapshotBranch: .release(major: 5, minor: 7), date: "2022-08-30")

    static let allToolchains: Set<ToolchainVersion> = [
        oldStable,
        oldStableNewPatch,
        newStable,
        oldMainSnapshot,
        newMainSnapshot,
        oldReleaseSnapshot,
        newReleaseSnapshot,
    ]

    func parseCommand<T: ParsableCommand>(_ commandType: T.Type, _ arguments: [String]) throws -> T {
        let rawCmd = try Swiftly.parseAsRoot(arguments)

        guard let cmd = rawCmd as? T else {
            throw SwiftlyTestError(
                message: "expected \(arguments) to parse as \(commandType) but got \(rawCmd) instead"
            )
        }

        return cmd
    }

    class func getTestHomePath(name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name, isDirectory: true)
    }

    /// Create a fresh swiftly home directory, populate it with a base config, and run the provided closure.
    /// Any swiftly commands executed in the closure will use this new home directory.
    ///
    /// This method requires the SWIFTLY_PLATFORM_NAME, SWIFTLY_PLATFORM_NAME_FULL, and SWIFTLY_PLATFORM_NAME_PRETTY
    /// environment variables to be set.
    ///
    /// The home directory will be deleted after the provided closure has been executed.
    func withTestHome(
        name: String = "testHome",
        _ f: () async throws -> Void
    ) async throws {
        let testHome = Self.getTestHomePath(name: name)
        SwiftlyCore.mockedHomeDir = testHome
        defer {
            SwiftlyCore.mockedHomeDir = nil
        }

        try testHome.deleteIfExists()
        try FileManager.default.createDirectory(at: testHome, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: testHome)
        }

        let getEnv = { varName in
            guard let v = ProcessInfo.processInfo.environment[varName] else {
                throw SwiftlyTestError(message: "environment variable \(varName) must be set in order to run tests")
            }
            return v
        }

        let config = Config(
            inUse: nil,
            installedToolchains: [],
            platform: Config.PlatformDefinition(
                name: try getEnv("SWIFTLY_PLATFORM_NAME"),
                nameFull: try getEnv("SWIFTLY_PLATFORM_NAME_FULL"),
                namePretty: try getEnv("SWIFTLY_PLATFORM_NAME_PRETTY")
            )
        )
        try config.save()

        try await f()
    }

    func withMockedHome(
        homeName: String,
        toolchains: Set<ToolchainVersion>,
        inUse: ToolchainVersion? = nil,
        f: () async throws -> Void
    ) async throws {
        try await self.withTestHome(name: homeName) {
            for toolchain in toolchains {
                try self.installMockedToolchain(toolchain: toolchain)
            }

            if !toolchains.isEmpty {
                var use = try self.parseCommand(Use.self, ["use", inUse?.name ?? "latest"])
                try await use.run()
            } else {
                try FileManager.default.createDirectory(
                    at: Swiftly.currentPlatform.swiftlyBinDir,
                    withIntermediateDirectories: true
                )
            }

            try await f()
        }
    }

    /// Validates that the provided toolchain is the one currently marked as "in use", both by checking the
    /// configuration file and by executing `swift --version` using the swift executable in the `bin` directory.
    /// If nil is provided, this validates that no toolchain is currently in use.
    func validateInUse(expected: ToolchainVersion?) async throws {
        let config = try Config.load()
        XCTAssertEqual(config.inUse, expected)

        let executable = SwiftExecutable(path: Swiftly.currentPlatform.swiftlyBinDir.appendingPathComponent("swift"))

        XCTAssertEqual(executable.exists(), expected != nil)

        guard let expected else {
            return
        }

        let inUseVersion = try await executable.version()
        XCTAssertEqual(inUseVersion, expected)
    }

    /// Validate that all of the provided toolchains have been installed.
    ///
    /// This method ensures that config.json reflects the expected installed toolchains and also
    /// validates that the toolchains on disk match their expected versions via `swift --version`.
    func validateInstalledToolchains(_ toolchains: Set<ToolchainVersion>, description: String) async throws {
        let config = try Config.load()

        guard config.installedToolchains == toolchains else {
            throw SwiftlyTestError(message: "\(description): expected \(toolchains) but got \(config.installedToolchains)")
        }

#if os(Linux)
        // Verify that the toolchains on disk correspond to those in the config.
        for toolchain in toolchains {
            let toolchainDir = Swiftly.currentPlatform.swiftlyHomeDir
                .appendingPathComponent("toolchains")
                .appendingPathComponent(toolchain.name)
            XCTAssertTrue(toolchainDir.fileExists())

            let swiftBinary = toolchainDir
                .appendingPathComponent("usr")
                .appendingPathComponent("bin")
                .appendingPathComponent("swift")

            let executable = SwiftExecutable(path: swiftBinary)
            let actualVersion = try await executable.version()
            XCTAssertEqual(actualVersion, toolchain)
        }
#endif
    }

    /// Install a mocked toolchain associated with the given version that includes the provided list of executables
    /// in its bin directory.
    ///
    /// When executed, the mocked executables will simply print the toolchain version and return.
    func installMockedToolchain(toolchain: ToolchainVersion, executables: [String] = ["swift"]) throws {
        let toolchainDir = Swiftly.currentPlatform.swiftlyToolchainsDir.appendingPathComponent(toolchain.name)
        try FileManager.default.createDirectory(at: toolchainDir, withIntermediateDirectories: true)

        let toolchainBinDir = toolchainDir
            .appendingPathComponent("usr", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: toolchainBinDir,
            withIntermediateDirectories: true
        )

        // create dummy executable file that just prints the toolchain's version
        for executable in executables {
            let executablePath = toolchainBinDir.appendingPathComponent(executable)

            let script = """
            #!/usr/bin/env sh

            echo '\(toolchain.name)'
            """

            let data = script.data(using: .utf8)!
            try data.write(to: executablePath)

            // make the file executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executablePath.path)
        }

        try Config.update { config in
            config.installedToolchains.insert(toolchain)
        }
    }

    /// Get the toolchain version of a mocked executable installed via `installMockedToolchain` at the given URL.
    func getMockedToolchainVersion(at url: URL) throws -> ToolchainVersion {
        let process = Process()
        process.executableURL = url

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        guard let outputData = try outputPipe.fileHandleForReading.readToEnd() else {
            throw SwiftlyTestError(message: "got no output from swift binary at path \(url.path)")
        }

        let toolchainVersion = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .newlines)
        return try ToolchainVersion(parsing: toolchainVersion)
    }
}

public class TestOutputHandler: SwiftlyCore.OutputHandler {
    public var lines: [String]
    private let quiet: Bool

    public init(quiet: Bool) {
        self.lines = []
        self.quiet = quiet
    }

    public func handleOutputLine(_ string: String) {
        self.lines.append(string)

        if !self.quiet {
            Swift.print(string)
        }
    }
}

public class TestInputProvider: SwiftlyCore.InputProvider {
    private var lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    public func readLine() -> String? {
        self.lines.removeFirst()
    }
}

extension SwiftlyCommand {
    /// Run this command, using the provided input as the stdin (in lines). Returns an array of captured
    /// output lines.
    mutating func runWithMockedIO(quiet: Bool = false, input: [String]? = nil) async throws -> [String] {
        let handler = TestOutputHandler(quiet: quiet)
        SwiftlyCore.outputHandler = handler
        defer {
            SwiftlyCore.outputHandler = nil
        }

        if let input {
            SwiftlyCore.inputProvider = TestInputProvider(lines: input)
        }
        defer {
            SwiftlyCore.inputProvider = nil
        }

        try await self.run()
        return handler.lines
    }
}

/// Wrapper around a `swift` executable used to execute swift commands.
public struct SwiftExecutable {
    public let path: URL

    private static let stableRegex: Regex<(Substring, Substring)> =
        try! Regex("swift-([^-]+)-RELEASE")

    private static let snapshotRegex: Regex<(Substring, Substring)> =
        try! Regex("\\(LLVM [a-z0-9]+, Swift ([a-z0-9]+)\\)")

    public func exists() -> Bool {
        self.path.fileExists()
    }

    /// Gets the version of this executable by parsing the `swift --version` output, potentially looking
    /// up the commit hash via the GitHub API.
    public func version() async throws -> ToolchainVersion {
        let process = Process()
        process.executableURL = self.path
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        guard let outputData = try outputPipe.fileHandleForReading.readToEnd() else {
            throw SwiftlyTestError(message: "got no output from swift binary at path \(self.path.path)")
        }

        let outputString = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .newlines)

        if let match = try Self.stableRegex.firstMatch(in: outputString) {
            let versions = match.output.1.split(separator: ".")

            let major = Int(versions[0])!
            let minor = Int(versions[1])!

            let patch: Int
            if versions.count == 3 {
                patch = Int(versions[2])!
            } else {
                patch = 0
            }

            return ToolchainVersion(major: major, minor: minor, patch: patch)
        } else if let match = try Self.snapshotRegex.firstMatch(in: outputString) {
            let commitHash = match.output.1

            // Get the commit hash from swift --version, look up the corresponding tag via GitHub, and confirm
            // that it matches the expected version.
            guard
                let tag: GitHubTag = try await HTTP.mapGitHubTags(
                    limit: 1,
                    filterMap: { tag in
                        guard tag.commit!.sha.starts(with: commitHash) else {
                            return nil
                        }
                        return tag
                    },
                    fetch: HTTP.getTags
                ).first,
                let snapshot = try tag.parseSnapshot()
            else {
                throw SwiftlyTestError(message: "could not find tag matching hash \(commitHash)")
            }

            return .snapshot(snapshot)
        } else if let version = try? ToolchainVersion(parsing: outputString) {
            // This branch is taken if the toolchain in question is mocked.
            return version
        } else {
            throw SwiftlyTestError(message: "bad version: \(outputString)")
        }
    }
}
