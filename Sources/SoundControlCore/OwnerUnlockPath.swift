/// Where the owner's check is shown. Touch ID runs inline in the overlay; without it the system password prompt is used.
public enum OwnerUnlockPath: Sendable, Equatable {
    case inlineTouchID
    case systemPrompt

    public init(hasBiometry: Bool) {
        self = hasBiometry ? .inlineTouchID : .systemPrompt
    }
}
