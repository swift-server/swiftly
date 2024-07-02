import Foundation

public protocol Platform {
    /// The platform-specific location on disk where applications are
    /// supposed to store their custom data.
    var appDataDirectory: URL { get }

    /// The directory which stores the swiftly executable itself as well as symlinks
    /// to executables in the "bin" directory of the active toolchain.
    ///
    /// If a mocked home directory is set, this will be the "bin" subdirectory of the home directory.
    /// If not, this will be the SWIFTLY_BIN_DIR environment variable if set. If that's also unset,
    /// this will default to the platform's default location.
    var swiftlyBinDir: URL { get }

    /// The "toolchains" subdirectory that contains the Swift toolchains managed by swiftly.
    var swiftlyToolchainsDir: URL { get }

    /// The file extension of the downloaded toolchain for this platform.
    /// e.g. for Linux systems this is "tar.gz" and on macOS it's "pkg".
    var toolchainFileExtension: String { get }

    /// Checks whether a given system dependency has been installed yet or not.
    /// This will only really be used on Linux.
    func isSystemDependencyPresent(_ dependency: SystemDependency) -> Bool

    /// Installs a toolchain from a file on disk pointed to by the given URL.
    /// After this completes, a user can “use” the toolchain.
    func install(from: URL, version: ToolchainVersion) throws

    /// Uninstalls a toolchain associated with the given version.
    /// If this version is in use, the next latest version will be used afterwards.
    func uninstall(_ version: ToolchainVersion) throws

    /// Select the toolchain associated with the given version.
    /// Returns whether the selection was successful.
    func use(_ version: ToolchainVersion, currentToolchain: ToolchainVersion?) throws -> Bool

    /// Clear the current active toolchain.
    func unUse(currentToolchain: ToolchainVersion) throws

    /// Get a list of snapshot builds for the platform. If a version is specified, only
    /// return snapshots associated with the version.
    /// This will likely have a default implementation.
    func listAvailableSnapshots(version: String?) async -> [Snapshot]

    /// Get the name of the release binary for this platform with the given CPU arch.
    func getExecutableName(forArch: String) -> String

    /// Get a path pointing to a unique, temporary file.
    /// This does not need to actually create the file.
    func getTempFilePath() -> URL

    /// Verifies that the system meets the requirements needed to install a toolchain.
    /// `requireSignatureValidation` specifies whether the system's support for toolchain signature validation should be verified.
    ///
    /// Throws if system does not meet the requirements.
    func verifySystemPrerequisitesForInstall(requireSignatureValidation: Bool) throws

    /// Downloads the signature file associated with the archive and verifies it matches the downloaded archive.
    /// Throws an error if the signature does not match.
    /// On Linux, signature verification will be skipped if gpg is not installed.
    func verifySignature(httpClient: SwiftlyHTTPClient, archiveDownloadURL: URL, archive: URL) async throws
}

extension Platform {
    /// The location on disk where swiftly will store its configuration, installed toolchains, and symlinks to
    /// the active location.
    ///
    /// The structure of this directory looks like the following:
    ///
    /// ```
    /// homeDir/
    ///   |
    ///   -- toolchains/
    ///   |
    ///   -- config.json
    /// ```
    ///
    public var swiftlyHomeDir: URL {
        SwiftlyCore.mockedHomeDir
            ?? ProcessInfo.processInfo.environment["SWIFTLY_HOME_DIR"].map { URL(fileURLWithPath: $0) }
            ?? self.appDataDirectory.appendingPathComponent("swiftly", isDirectory: true)
    }

    /// The URL of the configuration file in swiftly's home directory.
    public var swiftlyConfigFile: URL {
        self.swiftlyHomeDir.appendingPathComponent("config.json")
    }

#if os(macOS) || os(Linux)
    public func runProgram(_ args: String..., quiet: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        if quiet {
            process.standardOutput = nil
            process.standardError = nil
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Error(message: "\(args.first!) exited with non-zero status: \(process.terminationStatus)")
        }
    }
#endif
}

public struct SystemDependency {}

public struct Snapshot: Decodable {}
