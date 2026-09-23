import Foundation

struct PublicChannel: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let username: String?
    let subscriberCount: Int
}
