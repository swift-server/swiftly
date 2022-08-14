import Foundation
import SwiftlyCore
/// `Platform` implementation for Linux systems.
/// This implementation can be reused for any supported Linux platform.
/// TODO: replace dummy implementations
public struct Linux: Platform {
    private let platform: Config.PlatformDefinition

    public init(platform: Config.PlatformDefinition) {
        self.platform = platform
    }

    public var name: String {
        self.platform.name
    }

    public var fullName: String {
        self.platform.fullName
    }

    public var namePretty: String {
        self.platform.namePretty
    }

    public var toolchainFileExtension: String {
        "tar.gz"
    }

    public func isSystemDependencyPresent(_: SystemDependency) -> Bool {
        true
    }

    public func install(from _: URL, version _: ToolchainVersion) throws {}

    public func uninstall(version _: ToolchainVersion) throws {}

    public func use(_: ToolchainVersion) throws {}

    public func listToolchains(selector _: ToolchainSelector?) -> [ToolchainVersion] {
        []
    }

    public func listAvailableSnapshots(version _: String?) async -> [Snapshot] {
        []
    }

    public func selfUpdate() async throws {}

    public func currentToolchain() throws -> ToolchainVersion? { nil }

    public func getTempFilePath() -> URL {
        return URL(fileURLWithPath: "/tmp/swiftly-\(UUID())")
    }

    public static let currentPlatform: any Platform = {
        do {
            let config = try Config.load()
            return Linux(platform: config.platform)
        } catch {
            fatalError("error loading config: \(error)")
        }
    }()
}
