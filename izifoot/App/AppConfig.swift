import Foundation

enum AppConfig {
    static let apiBaseURL = URL(string: "https://api.izifoot.fr")!
    static let webBaseURL = URL(string: "https://www.izifoot.fr")!
    static let mobileAuthStartURL = URL(string: "https://www.izifoot.fr/auth/mobile/start?platform=ios")!
    static let mobileAuthCallbackScheme = "izifoot"
    static let appName = "izifoot"
}
