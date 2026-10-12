import Foundation

public enum CopilotError: Error, LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case missingAPIKey
    case providerChanged
    case httpStatus(Int)
    case invalidResponse
    case emptyResponse
    case streamInterrupted
    case networkUnavailable
    case networkFailure(Int)
    case storageUnavailable
    case conversationDeleted
    case conversationConflict
    case credentialUnavailable(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .missingAPIKey: "请在设置中填写并保存 API Key。"
        case .providerChanged: "此对话使用另一 API 服务。请恢复原来的协议与地址，保存对应 API Key 后继续。"
        case .httpStatus(let status):
            switch status {
            case 400, 422: "API 请求参数无效（\(status)）。请检查所选协议与模型 ID。"
            case 401, 403: "API 拒绝访问（\(status)）。请检查 API Key 与模型权限。"
            case 402: "API 服务余额不足（402）。请检查服务账户余额。"
            case 404: "API 端点或模型不存在（404）。请检查完整请求地址与模型 ID。"
            case 429: "API 请求过多或额度不足（429）。请稍后重试或检查服务额度。"
            case 300..<400: "API 地址发生重定向。请在设置中填写最终服务地址。"
            default: "API 返回错误（\(status)）。请检查地址、协议和模型，稍后重试。"
            }
        case .invalidResponse: "无法读取 API 返回内容。请检查所选协议是否与服务一致。"
        case .emptyResponse: "模型未返回文本。请调整提示词或模型后重试。"
        case .streamInterrupted: "回复未完整生成。已接收的内容保留在当前页面，可以重新发送。"
        case .networkUnavailable: "无法连接 API 服务。请检查网络和 Base URL 后重试。"
        case .networkFailure(let code):
            switch URLError.Code(rawValue: code) {
            case .timedOut: "API 请求超时（\(code)）。服务可能正在排队或思考，请稍后重试。"
            case .cannotFindHost, .dnsLookupFailed: "无法解析 API 域名（\(code)）。请检查 Base URL、DNS 和网络连接。"
            case .cannotConnectToHost: "无法连接 API 服务器（\(code)）。请检查已保存的请求地址及服务是否运行；localhost 指当前设备。"
            case .notConnectedToInternet: "设备无法访问网络（\(code)）。请检查网络连接、应用联网权限和 VPN。"
            case .networkConnectionLost: "API 连接已中断（\(code)）。请检查网络或 VPN 后重试。"
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                .clientCertificateRejected, .clientCertificateRequired:
                "API 的 HTTPS 安全连接失败（\(code)）。请检查证书、设备时间及代理或 VPN 配置。"
            case .appTransportSecurityRequiresSecureConnection:
                "系统阻止了不安全的 API 连接（\(code)）。请使用 HTTPS 地址。"
            default: "API 网络请求失败（\(code)）。请检查已保存的请求地址和网络后重试。"
            }
        case .storageUnavailable: "无法保存本地数据。请检查设备存储空间或重新打开应用。"
        case .conversationDeleted: "此对话已被删除。请开始新翻译。"
        case .conversationConflict: "此对话的数据已变化。请重新打开历史记录。"
        case .credentialUnavailable(let status): "无法访问钥匙串（\(status)）。请解锁设备，并检查应用签名与共享钥匙串配置。"
        }
    }
}

/// Never pass arbitrary server/error descriptions into UI; they may echo credentials or source text.
func safeMessage(for error: any Error) -> String {
    (error as? CopilotError)?.errorDescription ?? CopilotError.storageUnavailable.errorDescription!
}
