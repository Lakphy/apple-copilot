import SwiftUI

public struct CopilotActions {
    public let send: () -> Void
    public let cancel: () -> Void
    public let canSend: Bool
    public let isWorking: Bool
}

private struct CopilotActionsKey: FocusedValueKey {
    typealias Value = CopilotActions
}

public struct CopilotSettingsActions {
    public let save: () -> Void
    public let canSave: Bool

    public init(save: @escaping () -> Void, canSave: Bool) {
        self.save = save
        self.canSave = canSave
    }
}

private struct CopilotSettingsActionsKey: FocusedValueKey {
    typealias Value = CopilotSettingsActions
}

public extension FocusedValues {
    var copilotActions: CopilotActions? {
        get { self[CopilotActionsKey.self] }
        set { self[CopilotActionsKey.self] = newValue }
    }

    var copilotSettingsActions: CopilotSettingsActions? {
        get { self[CopilotSettingsActionsKey.self] }
        set { self[CopilotSettingsActionsKey.self] = newValue }
    }
}
