import Foundation

struct ServerLaunchPlan {
    let executableURL: URL
    let arguments: [String]

    static func make(for serverURL: URL) -> ServerLaunchPlan {
        ServerLaunchPlan(executableURL: serverURL, arguments: [])
    }
}
