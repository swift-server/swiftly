import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility

import SwiftlyCore

internal struct SelfUpdate: SwiftlyCommand {
    public static var configuration = CommandConfiguration(
        abstract: "Update the version of swiftly itself."
    )

    public static var httpClient = SwiftlyHTTPClient()

    private enum CodingKeys: CodingKey {}

    internal mutating func run() async throws {
        SwiftlyCore.print("Checking for swiftly updates...")

        let release: SwiftlyGitHubRelease = try await Self.httpClient.getFromGitHub(
            url: "https://api.github.com/repos/swift-server/swiftly/releases/latest"
        )

        let version = try SwiftlyVersion(parsing: release.tag)

        guard version > SwiftlyCore.version else {
            SwiftlyCore.print("Already up to date.")
            return
        }

        SwiftlyCore.print("A new version is available: \(version)")

        let config = try Config.load()
        let executableName = Swiftly.currentPlatform.getExecutableName(forArch: config.platform.getArchitecture())
        let urlString = "https://github.com/swift-server/swiftly/versions/latest/download/\(executableName)"
        guard let downloadURL = URL(string: urlString) else {
            throw Error(message: "Invalid download url: \(urlString)")
        }

        let tmpFile = Swiftly.currentPlatform.getTempFilePath()
        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: tmpFile)
        }

        let animation = PercentProgressAnimation(
            stream: stdoutStream,
            header: "Downloading swiftly \(version)"
        )
        do {
            try await Self.httpClient.downloadFile(
                url: downloadURL,
                to: tmpFile,
                reportProgress: { progress in
                    let downloadedMiB = Double(progress.receivedBytes) / (1024.0 * 1024.0)
                    let totalMiB = Double(progress.totalBytes!) / (1024.0 * 1024.0)

                    animation.update(
                        step: progress.receivedBytes,
                        total: progress.totalBytes!,
                        text: "Downloaded \(String(format: "%.1f", downloadedMiB)) MiB of \(String(format: "%.1f", totalMiB)) MiB"
                    )
                }
            )
        } catch {
            animation.complete(success: false)
            throw error
        }
        animation.complete(success: true)

        let swiftlyExecutable = Swiftly.currentPlatform.swiftlyBinDir.appendingPathComponent("swiftly", isDirectory: false)
        try FileManager.default.removeItem(at: swiftlyExecutable)
        try FileManager.default.moveItem(at: tmpFile, to: swiftlyExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swiftlyExecutable.path)

        SwiftlyCore.print("Successfully updated swiftly to \(version) (was \(SwiftlyCore.version))")
    }
}
