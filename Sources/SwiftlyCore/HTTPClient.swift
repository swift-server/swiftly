import _StringProcessing
import AsyncHTTPClient
import Foundation
import NIO
import NIOFoundationCompat
import NIOHTTP1

public protocol HTTPRequestExecutor {
    func execute(_ request: HTTPClientRequest, timeout: TimeAmount) async throws -> HTTPClientResponse
}

/// An `HTTPRequestExecutor` backed by an `HTTPClient`.
internal struct HTTPRequestExecutorImpl: HTTPRequestExecutor {
    fileprivate static let client = HTTPClientWrapper()

    public func execute(_ request: HTTPClientRequest, timeout: TimeAmount) async throws -> HTTPClientResponse {
        try await Self.client.inner.execute(request, timeout: timeout)
    }
}

private func makeRequest(url: String) -> HTTPClientRequest {
    var request = HTTPClientRequest(url: url)
    request.headers.add(name: "User-Agent", value: "swiftly/\(SwiftlyCore.version)")
    return request
}

/// HTTPClient wrapper used for interfacing with various REST APIs and downloading things.
public struct SwiftlyHTTPClient {
    private struct Response {
        let status: HTTPResponseStatus
        let buffer: ByteBuffer
    }

    private let executor: HTTPRequestExecutor

    /// The GitHub authentication token to use for any requests made to the GitHub API.
    public var githubToken: String?

    public init(executor: HTTPRequestExecutor? = nil) {
        self.executor = executor ?? HTTPRequestExecutorImpl()
    }

    private func get(url: String, headers: [String: String]) async throws -> Response {
        var request = makeRequest(url: url)

        for (k, v) in headers {
            request.headers.add(name: k, value: v)
        }

        let response = try await self.executor.execute(request, timeout: .seconds(30))

        // if defined, the content-length headers announces the size of the body
        let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init) ?? 1024 * 1024
        return Response(status: response.status, buffer: try await response.body.collect(upTo: expectedBytes))
    }

    /// Decode the provided type `T` from the JSON body of the response from a GET request
    /// to the given URL.
    public func getFromJSON<T: Decodable>(
        url: String,
        type: T.Type,
        headers: [String: String] = [:]
    ) async throws -> T {
        let response = try await self.get(url: url, headers: headers)

        guard case .ok = response.status else {
            var message = "received status \"\(response.status)\" when reaching \(url)"
            if let json = response.buffer.getString(at: 0, length: response.buffer.readableBytes) {
                message += ": \(json)"
            }
            throw Error(message: message)
        }

        return try JSONDecoder().decode(type.self, from: response.buffer)
    }

    /// Return an array of released Swift versions that match the given filter, up to the provided
    /// limit (default unlimited).
    ///
    /// TODO: retrieve these directly from swift.org instead of through GitHub.
    public func getReleaseToolchains(
        limit: Int? = nil,
        filter: ((ToolchainVersion.StableRelease) -> Bool)? = nil
    ) async throws -> [ToolchainVersion.StableRelease] {
        let filterMap = { (gh: GitHubTag) -> ToolchainVersion.StableRelease? in
            guard let release = try gh.parseStableRelease() else {
                return nil
            }

            if let filter {
                guard filter(release) else {
                    return nil
                }
            }

            return release
        }

        return try await self.mapGitHubTags(limit: limit, filterMap: filterMap) { page in
            try await self.getReleases(page: page)
        }
    }

    /// Return an array of Swift snapshots that match the given filter, up to the provided
    /// limit (default unlimited).
    ///
    /// TODO: retrieve these directly from swift.org instead of through GitHub.
    public func getSnapshotToolchains(
        limit: Int? = nil,
        filter: ((ToolchainVersion.Snapshot) -> Bool)? = nil
    ) async throws -> [ToolchainVersion.Snapshot] {
        let filter = { (gh: GitHubTag) -> ToolchainVersion.Snapshot? in
            guard let snapshot = try gh.parseSnapshot() else {
                return nil
            }

            if let filter {
                guard filter(snapshot) else {
                    return nil
                }
            }

            return snapshot
        }

        return try await self.mapGitHubTags(limit: limit, filterMap: filter) { page in
            try await self.getTags(page: page)
        }
    }

    public struct DownloadProgress {
        public let receivedBytes: Int
        public let totalBytes: Int?
    }

    public struct DownloadNotFoundError: LocalizedError {
        public let url: String
    }

    public func downloadFile(
        url: URL,
        to destination: URL,
        reportProgress: ((DownloadProgress) -> Void)? = nil
    ) async throws {
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? fileHandle.close()
        }

        let request = makeRequest(url: url.absoluteString)
        let response = try await self.executor.execute(request, timeout: .seconds(30))

        switch response.status {
        case .ok:
            break
        case .notFound:
            throw SwiftlyHTTPClient.DownloadNotFoundError(url: url.path)
        default:
            throw Error(message: "Received \(response.status) when trying to download \(url)")
        }

        // if defined, the content-length headers announces the size of the body
        let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init)

        var lastUpdate = Date()
        var receivedBytes = 0
        for try await buffer in response.body {
            receivedBytes += buffer.readableBytes

            try buffer.withUnsafeReadableBytes { bufferPtr in
                try fileHandle.write(contentsOf: bufferPtr)
            }

            let now = Date()
            if let reportProgress, lastUpdate.distance(to: now) > 0.25 || receivedBytes == expectedBytes {
                lastUpdate = now
                reportProgress(SwiftlyHTTPClient.DownloadProgress(
                    receivedBytes: receivedBytes,
                    totalBytes: expectedBytes
                ))
            }
        }

        try fileHandle.synchronize()
    }
}

private class HTTPClientWrapper {
    fileprivate let inner = HTTPClient(eventLoopGroupProvider: .singleton)

    deinit {
        try? self.inner.syncShutdown()
    }
}
