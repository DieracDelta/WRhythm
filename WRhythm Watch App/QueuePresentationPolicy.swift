import Foundation

enum QueueMutationTarget: Equatable, Sendable {
    case shared
    case local
}

struct QueuePresentationPolicy: Sendable {
    static func canRemove(index: Int, currentIndex: Int, queueCount: Int) -> Bool {
        index >= 0 && index < queueCount && index != currentIndex
    }

    static func mutationTarget(hasSharedSession: Bool) -> QueueMutationTarget {
        hasSharedSession ? .shared : .local
    }

    static func sectionTitle(hasSharedSession: Bool, remoteQueueMatchesLocal: Bool, localTitle: String) -> String {
        hasSharedSession || remoteQueueMatchesLocal ? "Shared Queue" : localTitle
    }

    static func summary(queueCount: Int, currentIndex: Int) -> String {
        guard queueCount > 0 else { return "Nothing queued" }
        let displayIndex = min(max(currentIndex, 0), queueCount - 1) + 1
        return "Track \(displayIndex) of \(queueCount)"
    }
}
