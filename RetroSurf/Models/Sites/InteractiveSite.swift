import Foundation

@MainActor
protocol InteractiveSite: AnyObject {
    var descriptor: SiteDescriptor { get }

    func handle(_ request: SiteRequest) async -> SiteResponse
    func snapshot() -> Data
    func restore(from data: Data) throws
}

@MainActor
class BaseInteractiveSite<State: Codable & Sendable>: InteractiveSite {
    let descriptor: SiteDescriptor
    var state: State

    init(descriptor: SiteDescriptor, initialState: State) {
        self.descriptor = descriptor
        self.state = initialState
    }

    func handle(_ request: SiteRequest) async -> SiteResponse {
        fatalError("Subclasses must override handle(_:)")
    }

    func snapshot() -> Data {
        (try? JSONEncoder().encode(state)) ?? Data()
    }

    func restore(from data: Data) throws {
        state = try JSONDecoder().decode(State.self, from: data)
    }
}