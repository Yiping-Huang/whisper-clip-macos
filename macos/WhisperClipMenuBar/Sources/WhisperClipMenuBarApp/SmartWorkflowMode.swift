import Foundation

enum SmartWorkflowMode: String, CaseIterable {
    case normal
    case email
    case workChat = "work_chat"
    case technicalTicket = "technical_ticket"

    var displayName: String {
        switch self {
        case .normal:
            return "Simple Polish"
        case .email:
            return "Email Dictation"
        case .workChat:
            return "Work Chat"
        case .technicalTicket:
            return "Technical Ticket"
        }
    }

    static var refinementModes: [SmartWorkflowMode] {
        allCases
    }
}
