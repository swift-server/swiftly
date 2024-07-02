import Foundation
import SwiftlyCore

/// `Platform` implementation for Linux systems.
/// This implementation can be reused for any supported Linux platform.
/// TODO: replace dummy implementations
public struct Linux: Platform {
    public init() {}

    public var appDataDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: dir)
        } else {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
        }
    }

    public var swiftlyBinDir: URL {
        SwiftlyCore.mockedHomeDir.map { $0.appendingPathComponent("bin", isDirectory: true) }
            ?? ProcessInfo.processInfo.environment["SWIFTLY_BIN_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    public var swiftlyToolchainsDir: URL {
        self.swiftlyHomeDir.appendingPathComponent("toolchains", isDirectory: true)
    }

    public var toolchainFileExtension: String {
        "tar.gz"
    }

    public func isSystemDependencyPresent(_: SystemDependency) -> Bool {
        true
    }

    private static let skipVerificationMessage: String = "To skip signature verification, specify the --no-verify flag."

    public func verifySystemPrerequisitesForInstall(requireSignatureValidation: Bool) throws {
        // The only prerequisite at the moment is that gpg is installed and the Swift project's keys have been imported.
        guard requireSignatureValidation else {
            return
        }

        guard (try? self.runProgram("gpg", "--version", quiet: true)) != nil else {
            throw Error(message: "gpg not installed, cannot perform signature verification. To set up gpg for " +
                "toolchain signature validation, follow the instructions at " +
                "https://www.swift.org/install/linux/#installation-via-tarball. " + Self.skipVerificationMessage)
        }

        let foundKeys = (try? self.runProgram(
            "gpg",
            "--list-keys",
            "swift-infrastructure@forums.swift.org",
            "swift-infrastructure@swift.org",
            quiet: true
        )) != nil
        guard foundKeys else {
            throw Error(message: "Swift PGP keys not imported, cannot perform signature verification. " +
                "To enable verification, import the keys with the following command: " +
                "'wget -q -O - https://swift.org/keys/all-keys.asc | gpg --import -' " +
                Self.skipVerificationMessage)
        }

        SwiftlyCore.print("Refreshing Swift PGP keys...")
        do {
            try self.runProgram(
                "gpg",
                "--quiet",
                "--keyserver",
                "hkp://keyserver.ubuntu.com",
                "--refresh-keys",
                "Swift"
            )
        } catch {
            throw Error(message: "Failed to refresh PGP keys: \(error)")
        }
    }

    public func install(from tmpFile: URL, version: ToolchainVersion) throws {
        guard tmpFile.fileExists() else {
            throw Error(message: "\(tmpFile) doesn't exist")
        }

        if !self.swiftlyToolchainsDir.fileExists() {
            try FileManager.default.createDirectory(at: self.swiftlyToolchainsDir, withIntermediateDirectories: false)
        }

        SwiftlyCore.print("Extracting toolchain...")
        let toolchainDir = self.swiftlyToolchainsDir.appendingPathComponent(version.name)

        if toolchainDir.fileExists() {
            try FileManager.default.removeItem(at: toolchainDir)
        }

        try extractArchive(atPath: tmpFile) { name in
            // drop swift-a.b.c-RELEASE etc name from the extracted files.
            let relativePath = name.drop { c in c != "/" }.dropFirst()

            // prepend /path/to/swiftlyHomeDir/toolchains/<toolchain> to each file name
            return toolchainDir.appendingPathComponent(String(relativePath))
        }
    }

    public func uninstall(_ toolchain: ToolchainVersion) throws {
        let toolchainDir = self.swiftlyToolchainsDir.appendingPathComponent(toolchain.name)
        try FileManager.default.removeItem(at: toolchainDir)
    }

    public func use(_ toolchain: ToolchainVersion, currentToolchain: ToolchainVersion?) throws -> Bool {
        let toolchainBinURL = self.swiftlyToolchainsDir
            .appendingPathComponent(toolchain.name, isDirectory: true)
            .appendingPathComponent("usr", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)

        // Delete existing symlinks from previously in-use toolchain.
        if let currentToolchain {
            try self.unUse(currentToolchain: currentToolchain)
        }

        // Ensure swiftly doesn't overwrite any existing executables without getting confirmation first.
        let swiftlyBinDirContents = try FileManager.default.contentsOfDirectory(atPath: self.swiftlyBinDir.path)
        let toolchainBinDirContents = try FileManager.default.contentsOfDirectory(atPath: toolchainBinURL.path)
        let willBeOverwritten = Set(toolchainBinDirContents).intersection(swiftlyBinDirContents)
        if !willBeOverwritten.isEmpty {
            SwiftlyCore.print("The following existing executables will be overwritten:")

            for executable in willBeOverwritten {
                SwiftlyCore.print("  \(self.swiftlyBinDir.appendingPathComponent(executable).path)")
            }

            let proceed = SwiftlyCore.readLine(prompt: "Proceed? (y/n)") ?? "n"

            guard proceed == "y" else {
                SwiftlyCore.print("Aborting use")
                return false
            }
        }

        for executable in toolchainBinDirContents {
            let linkURL = self.swiftlyBinDir.appendingPathComponent(executable)
            let executableURL = toolchainBinURL.appendingPathComponent(executable)

            // Deletion confirmed with user above.
            try linkURL.deleteIfExists()

            try FileManager.default.createSymbolicLink(
                atPath: linkURL.path,
                withDestinationPath: executableURL.path
            )
        }

        return true
    }

    public func unUse(currentToolchain: ToolchainVersion) throws {
        let currentToolchainBinURL = self.swiftlyToolchainsDir
            .appendingPathComponent(currentToolchain.name, isDirectory: true)
            .appendingPathComponent("usr", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)

        for existingExecutable in try FileManager.default.contentsOfDirectory(atPath: currentToolchainBinURL.path) {
            guard existingExecutable != "swiftly" else {
                continue
            }

            let url = self.swiftlyBinDir.appendingPathComponent(existingExecutable)
            let vals = try url.resourceValues(forKeys: [.isSymbolicLinkKey])

            guard let islink = vals.isSymbolicLink, islink else {
                throw Error(message: "Found executable not managed by swiftly in SWIFTLY_BIN_DIR: \(url.path)")
            }
            let symlinkDest = url.resolvingSymlinksInPath()
            guard symlinkDest.deletingLastPathComponent() == currentToolchainBinURL else {
                throw Error(message: "Found symlink that points to non-swiftly managed executable: \(symlinkDest.path)")
            }

            try self.swiftlyBinDir.appendingPathComponent(existingExecutable).deleteIfExists()
        }
    }

    public func listAvailableSnapshots(version _: String?) async -> [Snapshot] {
        []
    }

    public func getExecutableName(forArch: String) -> String {
        "swiftly-\(forArch)-unknown-linux-gnu"
    }

    public func currentToolchain() throws -> ToolchainVersion? { nil }

    public func getTempFilePath() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("swiftly-\(UUID())")
    }

    public func verifySignature(httpClient: SwiftlyHTTPClient, archiveDownloadURL: URL, archive: URL) async throws {
        SwiftlyCore.print("Downloading toolchain signature...")
        let sigFile = self.getTempFilePath()
        FileManager.default.createFile(atPath: sigFile.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: sigFile)
        }

        try await httpClient.downloadFile(
            url: archiveDownloadURL.appendingPathExtension("sig"),
            to: sigFile
        )

        SwiftlyCore.print("Verifying toolchain signature...")
        do {
            try self.runProgram("gpg", "--verify", sigFile.path, archive.path)
        } catch {
            throw Error(message: "Toolchain signature verification failed: \(error)")
        }
    }

    public static let currentPlatform: any Platform = Linux()
}
