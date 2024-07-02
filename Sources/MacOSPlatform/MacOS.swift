import Foundation
import SwiftlyCore

public struct SwiftPkgInfo: Codable {
    public var CFBundleIdentifier: String

    public init(CFBundleIdentifier: String) {
        self.CFBundleIdentifier = CFBundleIdentifier
    }
}

/// `Platform` implementation for macOS systems.
public struct MacOS: Platform {
    public init() {}

    public var appDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    public var swiftlyBinDir: URL {
        SwiftlyCore.mockedHomeDir.map { $0.appendingPathComponent("bin", isDirectory: true) }
            ?? ProcessInfo.processInfo.environment["SWIFTLY_BIN_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/swiftly/bin", isDirectory: true)
    }

    public var swiftlyToolchainsDir: URL {
        SwiftlyCore.mockedHomeDir.map { $0.appendingPathComponent("Toolchains", isDirectory: true) }
            // The toolchains are always installed here by the installer. We bypass the installer in the case of test mocks
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Toolchains", isDirectory: true)
    }

    public var toolchainFileExtension: String {
        "pkg"
    }

    public func isSystemDependencyPresent(_: SystemDependency) -> Bool {
        // All system dependencies on macOS should be present
        true
    }

    public func verifySystemPrerequisitesForInstall(requireSignatureValidation _: Bool) throws {
        // All system prerequisites should be there for macOS
    }

    public func install(from tmpFile: URL, version: ToolchainVersion) throws {
        guard tmpFile.fileExists() else {
            throw Error(message: "\(tmpFile) doesn't exist")
        }

        if !self.swiftlyToolchainsDir.fileExists() {
            try FileManager.default.createDirectory(at: self.swiftlyToolchainsDir, withIntermediateDirectories: false)
        }

        if SwiftlyCore.mockedHomeDir == nil {
            SwiftlyCore.print("Installing package in user home directory...")
            try runProgram("installer", "-pkg", tmpFile.path, "-target", "CurrentUserHomeDirectory")
        } else {
            // In the case of a mock for testing purposes we won't use the installer, perferring a manual process because
            //  the installer will not install to an arbitrary path, only a volume or user home directory.
            let tmpDir = self.getTempFilePath()
            let toolchainDir = self.swiftlyToolchainsDir.appendingPathComponent("\(version.identifier).xctoolchain", isDirectory: true)
            if !toolchainDir.fileExists() {
                try FileManager.default.createDirectory(at: toolchainDir, withIntermediateDirectories: false)
            }
            try runProgram("pkgutil", "--expand", tmpFile.path, tmpDir.path)
            // There's a slight difference in the location of the special Payload file between official swift packages
            // and the ones that are mocked here in the test framework.
            var payload = tmpDir.appendingPathComponent("Payload")
            if !payload.fileExists() {
                payload = tmpDir.appendingPathComponent("\(version.identifier)-osx-package.pkg/Payload")
            }
            try runProgram("tar", "-C", toolchainDir.path, "-xf", payload.path)
        }
    }

    public func uninstall(_ toolchain: ToolchainVersion) throws {
        SwiftlyCore.print("Uninstalling package in user home directory...")

        let toolchainDir = self.swiftlyToolchainsDir.appendingPathComponent("\(toolchain.identifier).xctoolchain", isDirectory: true)

        let decoder = PropertyListDecoder()
        let infoPlist = toolchainDir.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoPlist) else {
            throw Error(message: "could not open \(infoPlist)")
        }

        guard let pkgInfo = try? decoder.decode(SwiftPkgInfo.self, from: data) else {
            throw Error(message: "could not decode plist at \(infoPlist)")
        }

        try FileManager.default.removeItem(at: toolchainDir)

        let homedir = ProcessInfo.processInfo.environment["HOME"]!
        try? runProgram("pkgutil", "--volume", homedir, "--forget", pkgInfo.CFBundleIdentifier)
    }

    public func use(_ toolchain: ToolchainVersion, currentToolchain: ToolchainVersion?) throws -> Bool {
        let toolchainBinURL = self.swiftlyToolchainsDir
            .appendingPathComponent(toolchain.identifier + ".xctoolchain", isDirectory: true)
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

        SwiftlyCore.print("""
            NOTE: On macOS it is possible that the shell will pick up the system Swift on the path
            instead of the one that swiftly has installed for you. You can run the 'hash -r'
            command to update the shell with the latest PATHs.

                hash -r

            """
        )

        return true
    }

    public func unUse(currentToolchain: ToolchainVersion) throws {
        let currentToolchainBinURL = self.swiftlyToolchainsDir
            .appendingPathComponent(currentToolchain.identifier + ".xctoolchain", isDirectory: true)
            .appendingPathComponent("usr", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)

        for existingExecutable in try FileManager.default.contentsOfDirectory(atPath: currentToolchainBinURL.path) {
            guard existingExecutable != "swiftly" else {
                continue
            }

            let url = self.swiftlyBinDir.appendingPathComponent(existingExecutable)
            let vals = try url.resourceValues(forKeys: [URLResourceKey.isSymbolicLinkKey])

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
        "swiftly-\(forArch)-macos-osx"
    }

    public func currentToolchain() throws -> ToolchainVersion? { nil }

    public func getTempFilePath() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("swiftly-\(UUID()).pkg")
    }

    public func verifySignature(httpClient _: SwiftlyHTTPClient, archiveDownloadURL _: URL, archive _: URL) async throws {
        // No signature verification is required on macOS since the pkg files have their own signing
        //  mechanism and the swift.org downloadables are trusted by stock macOS installations.
    }

    public static let currentPlatform: any Platform = MacOS()
}
