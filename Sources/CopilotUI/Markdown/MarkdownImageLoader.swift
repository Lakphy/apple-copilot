import CopilotCore
import Foundation

enum MarkdownImageLoader {
    @concurrent static func load(_ url: URL) async throws -> String {
        let buffer = ImageBuffer()
        var request = URLRequest(url: url)
        request.setValue("image/png,image/jpeg,image/gif,image/webp", forHTTPHeaderField: "Accept")
        // No cookies or model credentials; redirects are rejected and transfer size is bounded.
        try await URLSessionHTTPTransport().stream(
            request,
            onResponse: { status, type in
                try await buffer.start(status: status, type: type)
            }, onData: { data in try await buffer.append(data) })
        return await buffer.dataURL()
    }

    private actor ImageBuffer {
        private var data = Data()
        private var contentType = ""
        func start(status: Int, type: String) throws {
            let type = type.lowercased().split(separator: ";").first.map(String.init) ?? ""
            guard (200..<300).contains(status), ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(type)
            else {
                throw CopilotError.invalidResponse
            }
            contentType = type
        }
        func append(_ chunk: Data) throws {
            guard data.count + chunk.count <= 8 * 1024 * 1024 else { throw CopilotError.invalidResponse }
            data.append(chunk)
        }
        func dataURL() -> String { "data:\(contentType);base64,\(data.base64EncodedString())" }
    }
}
