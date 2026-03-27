import Foundation

enum APIRoutes {
    enum Auth {
        static let register = "/auth/register"
        static let login = "/auth/login"
        static let logout = "/auth/logout"
        static func invitationByToken(_ token: String) -> String { "/auth/invitations/\(token.urlEncoded)" }
        static let acceptInvitation = "/auth/invitations/accept"
    }

    static let me = "/me"

    enum Clubs {
        static let me = "/clubs/me"
        static let coaches = "/clubs/me/coaches"
    }

    enum Teams {
        static let list = "/teams"
        static func byID(_ id: String) -> String { "/teams/\(id.urlEncoded)" }
    }

    enum Accounts {
        static let list = "/accounts"
        static let invitations = "/accounts/invitations"
    }

    enum Players {
        static let list = "/players"
        static func byID(_ id: String) -> String { "/players/\(id.urlEncoded)" }
        static func invite(_ id: String) -> String { "/players/\(id.urlEncoded)/invite" }
        static func invitationStatus(_ id: String) -> String { "/players/\(id.urlEncoded)/invitation-status" }
    }

    enum Trainings {
        static let list = "/trainings"
        static func byID(_ id: String) -> String { "/trainings/\(id.urlEncoded)" }
        static func attendance(_ trainingID: String) -> String { "/trainings/\(trainingID.urlEncoded)/attendance" }
        static func drills(_ trainingID: String) -> String { "/trainings/\(trainingID.urlEncoded)/drills" }
        static func drillByID(_ trainingID: String, trainingDrillID: String) -> String {
            "/trainings/\(trainingID.urlEncoded)/drills/\(trainingDrillID.urlEncoded)"
        }
        static func roles(_ trainingID: String) -> String { "/trainings/\(trainingID.urlEncoded)/roles" }
        static func generateAIDrills(_ trainingID: String) -> String { "/trainings/\(trainingID.urlEncoded)/drills/generate-ai" }
    }

    enum Matchday {
        static let list = "/matchday"
        static func byID(_ id: String) -> String { "/matchday/\(id.urlEncoded)" }
        static func share(_ id: String) -> String { "/matchday/\(id.urlEncoded)/share" }
        static func summary(_ id: String) -> String { "/matchday/\(id.urlEncoded)/summary" }
        static func teamsAbsence(_ id: String) -> String { "/matchday/\(id.urlEncoded)/teams/absence" }
    }

    enum Public {
        static func matchdayByToken(_ token: String) -> String { "/public/matchday/\(token.urlEncoded)" }
    }

    enum Player {
        static let matchday = "/player/matchday"
        static func summary(_ id: String) -> String { "/player/matchday/\(id.urlEncoded)/summary" }
    }

    enum Drills {
        static let list = "/drills"
        static func byID(_ id: String) -> String { "/drills/\(id.urlEncoded)" }
        static func diagrams(_ drillID: String) -> String { "/drills/\(drillID.urlEncoded)/diagrams" }
        static func generateAIDiagram(_ drillID: String) -> String { "/drills/\(drillID.urlEncoded)/diagrams/generate-ai" }
    }

    enum TrainingDrills {
        static func diagrams(_ trainingDrillID: String) -> String { "/training-drills/\(trainingDrillID.urlEncoded)/diagrams" }
        static func generateAIDiagram(_ trainingDrillID: String) -> String { "/training-drills/\(trainingDrillID.urlEncoded)/diagrams/generate-ai" }
    }

    enum Diagrams {
        static func byID(_ id: String) -> String { "/diagrams/\(id.urlEncoded)" }
    }

    enum Matches {
        static let list = "/matches"
        static func byID(_ id: String) -> String { "/matches/\(id.urlEncoded)" }
        static func byMatchday(_ matchdayID: String) -> String { "/matches?matchdayId=\(matchdayID.urlEncoded)" }
    }

    enum Plannings {
        static let list = "/plannings"
        static func byID(_ id: String) -> String { "/plannings/\(id.urlEncoded)" }
    }

    enum Attendance {
        static let list = "/attendance"
        static func bySession(type: String, sessionID: String) -> String {
            "/attendance?session_type=\(type)&session_id=\(sessionID.urlEncoded)"
        }
    }
}
