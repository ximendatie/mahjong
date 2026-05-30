import Foundation

protocol AgentTaskProvider: Sendable {
    var providerID: AgentProviderID { get }
    var providerName: String { get }

    func fetchTasks() async -> [AgentTask]
}
