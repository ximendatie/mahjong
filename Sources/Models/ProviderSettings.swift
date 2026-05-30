import Foundation

struct AgentProviderSetting: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var detail: String
    var isEnabled: Bool
}

enum ProviderDiagnosticStatus: String, Codable, Sendable {
    case ok
    case disabled
    case noData
    case missingPath
    case failed

    var title: String {
        switch self {
        case .ok: "OK"
        case .disabled: "Disabled"
        case .noData: "No Data"
        case .missingPath: "Missing Path"
        case .failed: "Failed"
        }
    }
}

struct ProviderDiagnostic: Identifiable, Equatable, Sendable {
    let id: String
    var displayName: String
    var status: ProviderDiagnosticStatus
    var message: String
    var dataPaths: [String]
    var lastCheckedAt: Date?
}
