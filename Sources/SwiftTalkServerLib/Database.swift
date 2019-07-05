//
//  Database.swift
//  Bits
//
//  Created by Chris Eidhof on 08.08.18.
//

import Foundation
import Database
import LibPQ
import WebServer


let postgres = env.databaseURL.flatMap { URL(string: $0).map { Postgres(url: $0) } } ?? Postgres(host: env.databaseHost, name: env.databaseName, user: env.databaseUser, password: env.databasePassword)


struct FileData: Codable, Insertable {
    var key: String
    var value: String
    
    static let tableName: String = "files"
}

struct GiftData: Codable, Insertable {
    var gifterEmail: String?
    var gifterName: String?
    var gifteeEmail: String
    var gifteeName: String
    var sendAt: Date
    var message: String
    var gifterUserId: UUID?
    var gifteeUserId: UUID?
    var subscriptionId: String?
    var activated: Bool
    var planCode: String
    static let tableName: String = "gifts"
    
    func validate() -> [ValidationError] {
        var result: [(String,String)] = []
        if !gifteeEmail.isValidEmail {
            result.append(("giftee_email", "Their email address is invalid."))
        }
        if sendAt < globals.currentDate() && !sendAt.isToday {
            result.append(("send_at", "The date cannot be in the past."))
        }
        return result
    }
}

extension FileData {
    init(repository: String, path: String, value: String) {
        self.init(key: FileData.key(forRepository: repository, path: path), value: value)
    }
    
    static func key(forRepository repository: String, path: String) -> String {
        return "\(keyPrefix(forRepository: repository))\(path)"
    }
    
    static func keyPrefix(forRepository repository: String) -> String {
        return "\(repository)::"
    }
}

struct SessionData: Codable, Insertable {
    var userId: UUID
    var createdAt: Date
    var updatedAt: Date
    
    init(userId: UUID) {
        self.userId = userId
        self.createdAt = globals.currentDate()
        self.updatedAt = self.createdAt
    }
    
    static let tableName: String = "sessions"
}

struct DownloadData: Codable, Insertable {
    var userId: UUID
    var episodeNumber: Int
    var createdAt: Date
    init(user: UUID, episode: Int) {
        self.userId = user
        self.episodeNumber = episode
        self.createdAt = globals.currentDate()
    }
    
    static let tableName: String = "downloads"
}

extension CSRFToken: Param {
    public init(stringValue string: String?) {
        self.init(.init(stringValue: string!))
    }
    public static var oid = OID.uuid
    public var stringValue: String? { return value.stringValue }
}

struct UserData: Codable, Insertable {
    enum Role: Int, Codable {
        case user = 0
        case collaborator = 1
        case admin = 2
        case teamManager = 3
    }
    var email: String
    var githubUID: Int?
    var githubLogin: String?
    var githubToken: String?
    var avatarURL: String
    var role: Role = .user
    var name: String
    var createdAt: Date
    var recurlyHostedLoginToken: String?
    var downloadCredits: Int = 0
    var downloadCreditsOffset: Int = 0
    var subscriber: Bool = false
    var canceled: Bool = false
    var confirmedNameAndEmail: Bool = false
    private var csrf: UUID
    var teamToken: UUID
    
    var csrfToken: CSRFToken {
        return CSRFToken(csrf)
    }
    
    init(email: String, githubUID: Int? = nil, githubLogin: String? = nil, githubToken: String? = nil, avatarURL: String, name: String, createdAt: Date? = nil, role: Role = .user, downloadCredits: Int = 0, canceled: Bool = false, confirmedNameAndEmail: Bool = false, subscriber: Bool = false) {
        self.email = email
        self.githubUID = githubUID
        self.githubLogin = githubLogin
        self.githubToken = githubToken
        self.avatarURL = avatarURL
        self.name = name
        let now = globals.currentDate()
        self.createdAt = createdAt ?? now
        self.downloadCredits = downloadCredits
        csrf = UUID()
        self.canceled = canceled
        self.confirmedNameAndEmail = confirmedNameAndEmail
        self.subscriber = subscriber
        self.role = role
        self.teamToken = UUID()
    }
    
    static let tableName: String = "users"
}

extension UserData.Role: Param {
    static let oid: OID = Int.oid
    var stringValue: String? { return rawValue.stringValue }
    init(stringValue string: String?) {
        self.init(rawValue: .init(stringValue: string!))!
    }
}

struct TeamMemberData: Codable, Insertable {
    var userId: UUID
    var teamMemberId: UUID
    var createdAt: Date
    var expiredAt: Date?
    
    static let tableName: String = "team_members"
}

extension TeamMemberData {
    init(userId: UUID, teamMemberId: UUID) {
        self.userId = userId
        self.teamMemberId = teamMemberId
        self.createdAt = globals.currentDate()
    }
    
    var activeMonths: Int {
        let endDate = expiredAt ?? globals.currentDate()
        return Int(endDate.numberOfMonths(since: createdAt)) + 1
    }
}

fileprivate let emailRegex = try! NSRegularExpression(pattern: "^[^@]+@(?:[^@.]+?\\.)+.{2,}$", options: [.caseInsensitive])

extension String {
    fileprivate var isValidEmail: Bool {
        return !emailRegex.matches(in: self, options: [], range: NSRange(startIndex..<endIndex, in: self)).isEmpty
    }
}

extension UserData {
    var premiumAccess: Bool {
        guard role != .teamManager else { return false }
        return role == .admin || role == .collaborator || subscriber
    }
    
    func validate() -> [ValidationError] {
        var result: [(String,String)] = []
        if !email.isValidEmail {
            result.append(("email", "Invalid email address"))
        }
        if name.isEmpty {
            result.append(("name", "Name cannot be empty"))
        }
        return result
    }
    
    var isAdmin: Bool {
        return role == .admin
    }
    
    var isCollaborator: Bool {
        return role == .collaborator
    }
}

struct PlayProgressData: Insertable {
    var userId: UUID
    var episodeNumber: Int
    var progress: Int
    var furthestWatched: Int
    
    static let tableName = "play_progress"
}

