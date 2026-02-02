import Foundation

enum SmartWorkflowMode: String, CaseIterable {
    case normal
    case email
    case workChat = "work_chat"

    var displayName: String {
        switch self {
        case .normal:
            return "Normal"
        case .email:
            return "Email Dictation"
        case .workChat:
            return "Work Chat"
        }
    }
}
