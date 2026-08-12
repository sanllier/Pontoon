public enum BridgeEvent: Sendable {

    case nativeCallStarted(id: Int, function: String)
    case nativeCallFinished(id: Int, function: String, outcome: Outcome, duration: Duration)
    case nativeCallFailed(id: Int, function: String?, error: BridgeError)
    case jsCallStarted(id: Int, function: String)
    case jsCallFinished(id: Int, function: String, outcome: Outcome, duration: Duration)
    case jsCallFailed(id: Int, function: String, error: JSCallError)

    // MARK: - Public Nested

    public enum Outcome: Sendable {
        case resolved
        case rejected
    }

}

@MainActor
public protocol BridgeObserver: AnyObject {
    func bridge(_ bridge: Bridge, didReceive event: BridgeEvent)
}
