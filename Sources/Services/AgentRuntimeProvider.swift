import Foundation

protocol AgentRuntimeProvider: Sendable {
    var providerID: AgentProviderID { get }
    var providerName: String { get }

    func fetchRuntimes() async -> [AgentRuntime]
}
