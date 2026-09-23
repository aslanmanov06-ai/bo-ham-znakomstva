import Foundation

struct IceServer: Decodable {
    let urls: [String]
    let username: String?
    let credential: String?
}