import Foundation

@Observable
class SettingsStore {
    private let defaults = UserDefaults.standard

    var serverHost: String {
        get { defaults.string(forKey: "serverHost") ?? "" }
        set { defaults.set(newValue, forKey: "serverHost") }
    }

    var serverPort: String {
        get { defaults.string(forKey: "serverPort") ?? "7777" }
        set { defaults.set(newValue, forKey: "serverPort") }
    }

    var baseURL: String {
        let host = serverHost.isEmpty ? "localhost" : serverHost
        let port = serverPort.isEmpty ? "7777" : serverPort
        return "http://\(host):\(port)"
    }

    var isConfigured: Bool {
        !serverHost.isEmpty
    }
}
