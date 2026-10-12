import Foundation

/// A complete HTTP response without access to credentials or transport internals.
public struct HTTPResult: Sendable {
    public let data: Data
    public let statusCode: Int
    public let contentType: String
    public init(data: Data, statusCode: Int, contentType: String = "application/json") {
        self.data = data
        self.statusCode = statusCode
        self.contentType = contentType
    }
}

/// Injectable HTTP I/O shared by model requests and explicit image downloads.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
    func stream(
        _ request: URLRequest,
        onResponse: @escaping @Sendable (Int, String) async throws -> Void,
        onData: @escaping @Sendable (Data) async throws -> Void) async throws
}

public extension HTTPTransport {
    func stream(
        _ request: URLRequest,
        onResponse: @escaping @Sendable (Int, String) async throws -> Void,
        onData: @escaping @Sendable (Data) async throws -> Void
    ) async throws {
        let result = try await send(request)
        try await onResponse(result.statusCode, result.contentType)
        try await onData(result.data)
    }
}

/// All redirects are rejected. Credentials never follow a redirect to a different origin.
public final class URLSessionHTTPTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, Sendable {
    public override init() { super.init() }

    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CopilotError.invalidResponse }
        return HTTPResult(
            data: data, statusCode: response.statusCode,
            contentType: response.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    public func stream(
        _ request: URLRequest,
        onResponse: @escaping @Sendable (Int, String) async throws -> Void,
        onData: @escaping @Sendable (Data) async throws -> Void
    ) async throws {
        let session = makeSession()
        // Cancellation, a decoder error, and normal completion all close the socket.
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw CopilotError.invalidResponse }
            try await onResponse(response.statusCode, response.value(forHTTPHeaderField: "Content-Type") ?? "")
            var chunk = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                chunk.append(byte)
                // Preserve empty lines (AsyncBytes.lines does not) and split UTF-8 only in the decoder.
                if byte == 10 || chunk.count >= 4096 {
                    try await onData(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty { try await onData(chunk) }
        } onCancel: {
            // Also cancel while awaiting a stalled server, before its next byte arrives.
            session.invalidateAndCancel()
        }
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
}
