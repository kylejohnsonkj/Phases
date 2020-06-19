import Foundation

// MARK: - JSONParent
public struct JSONParent: Codable {
    public let data: JSONData
}

// MARK: - JSONData
public struct JSONData: Codable {
    public let children: [JSONChild]
    public let after: String
}

// MARK: - JSONChild
public struct JSONChild: Codable {
    public let data: Comment
}

// MARK: - Comment
public struct Comment: Codable {
    public let subreddit: String
    public let createdUTC: Int
    
    public enum CodingKeys: String, CodingKey {
        case subreddit
        case createdUTC = "created_utc"
    }
}
