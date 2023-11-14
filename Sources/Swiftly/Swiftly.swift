import ArgumentParser
import Foundation
#if os(Linux)
import LinuxPlatform
#endif
import SwiftlyCore

@main
@available(macOS 10.15, *)
public struct Swiftly: SwiftlyCommand {
    public static let version = SwiftlyVersion(major: 0, minor: 1, patch: 0)

    public static var configuration = CommandConfiguration(
        abstract: "A utility for installing and managing Swift toolchains.",

        version: String(describing: Self.version),

        subcommands: [
            Install.self,
            Use.self,
            Uninstall.self,
            List.self,
            Update.self,
            SelfUpdate.self,
        ]
    )

    /// The list of directories that swiftly needs to exist in order to execute.
    /// If they do not exist when a swiftly command is invoked, they will be created.
    public static var requiredDirectories: [URL] {
        [
            Swiftly.currentPlatform.swiftlyHomeDir,
            Swiftly.currentPlatform.swiftlyBinDir,
            Swiftly.currentPlatform.swiftlyToolchainsDir,
        ]
    }

    public init() {}

#if os(Linux)
    internal static let currentPlatform = Linux.currentPlatform
#endif
}

public protocol SwiftlyCommand: AsyncParsableCommand {}

extension SwiftlyCommand {
    public mutating func validate() throws {
        for requiredDir in Swiftly.requiredDirectories {
            guard requiredDir.fileExists() else {
                do {
                    try FileManager.default.createDirectory(at: requiredDir, withIntermediateDirectories: true)
                } catch {
                    throw Error(message: "Failed to create required directory \"\(requiredDir.path)\": \(error)")
                }
                continue
            }
        }

        // Verify that the configuration exists and can be loaded
        _ = try Config.load()
    }
}
