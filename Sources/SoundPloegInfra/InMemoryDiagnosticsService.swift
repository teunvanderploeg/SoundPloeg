import Foundation
import SoundPloegCore

public actor InMemoryDiagnosticsService: DiagnosticsService {
    private var items: [UserMessage] = []

    public init() {}

    public func publish(_ message: UserMessage) async {
        items.append(message)
        if items.count > 25 {
            items.removeFirst(items.count - 25)
        }
    }

    public func clear() async {
        items.removeAll()
    }

    public func messages() async -> [UserMessage] {
        items
    }
}
