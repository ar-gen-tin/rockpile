import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "SetupManager")

@MainActor
@Observable
final class SetupManager {
    var isRockpileDetected = false
    var localIPAddress: String = ""
    var pairingCode: String = ""
    var pluginInstalled = false
    var connectionTestResult: ConnectionTestResult = .untested
    var isTestingConnection = false

    enum ConnectionTestResult: Equatable {
        case untested
        case testing
        case success
        case failed(String)
    }

    init() {
        localIPAddress = Self.getLocalIP() ?? "unknown"
        pairingCode = Self.ipToCode(localIPAddress)
    }

    // MARK: - Detection

    func detectRockpile() {
        let rockpileDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rockpile")
        isRockpileDetected = FileManager.default.fileExists(atPath: rockpileDir.path)
    }

    // MARK: - Pairing Code (IP <-> Code)

    /// Encode an IPv4 address into a short alphanumeric pairing code
    /// e.g. "192.168.1.100" → "1hge15w" (lowercase, no separator)
    static func ipToCode(_ ip: String) -> String {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return "-------" }
        let num = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
        let raw = String(num, radix: 36, uppercase: false)
        // Pad to 7 characters, lowercase, no separator
        return String(repeating: "0", count: max(0, 7 - raw.count)) + raw
    }

    /// Decode a pairing code back to an IPv4 address
    /// e.g. "1HG-E15W" → "192.168.1.100"
    static func codeToIP(_ code: String) -> String? {
        let cleaned = code.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard let num = UInt32(cleaned, radix: 36) else { return nil }
        let a = (num >> 24) & 0xFF
        let b = (num >> 16) & 0xFF
        let c = (num >> 8) & 0xFF
        let d = num & 0xFF
        // Basic validation
        guard a > 0, a < 255 else { return nil }
        return "\(a).\(b).\(c).\(d)"
    }

    // MARK: - Plugin Installation (Plan A: Rockpile plugin + TCP)

    /// Install the Rockpile plugin on this machine and set ROCKPILE_HOST
    func installPlugin(targetHost: String, targetPort: UInt16 = 18790) -> Bool {
        let fm = FileManager.default
        let pluginDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".rockpile/plugins/rockpile")

        do {
            try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create plugin dir: \(error.localizedDescription)")
            return false
        }

        let indexJS = generatePluginJS(host: targetHost, port: targetPort)
        let packageJSON = """
        {
          "name": "rockpile-plugin",
          "version": "1.0.0",
          "main": "index.js",
          "description": "Rockpile notch companion plugin for Rockpile"
        }
        """

        do {
            try indexJS.write(to: pluginDir.appendingPathComponent("index.js"),
                            atomically: true, encoding: .utf8)
            try packageJSON.write(to: pluginDir.appendingPathComponent("package.json"),
                                atomically: true, encoding: .utf8)
            pluginInstalled = true
            logger.info("Plugin installed to \(pluginDir.path)")
        } catch {
            logger.error("Failed to write plugin files: \(error.localizedDescription)")
            return false
        }

        // Rockpile auto-discovers plugins in ~/.rockpile/plugins/ — no config registration needed

        // Write ROCKPILE_HOST to .zshrc
        setEnvironmentVariable(host: targetHost, port: targetPort)

        return true
    }

    /// Install plugin for local mode (Unix socket, no TCP needed)
    func installPluginLocal() -> Bool {
        let fm = FileManager.default
        let pluginDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".rockpile/plugins/rockpile")

        do {
            try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create plugin dir: \(error.localizedDescription)")
            return false
        }

        let indexJS = generatePluginJSLocal()
        let packageJSON = """
        {
          "name": "rockpile-plugin",
          "version": "1.0.0",
          "main": "index.js",
          "description": "Rockpile notch companion plugin for Rockpile"
        }
        """

        do {
            try indexJS.write(to: pluginDir.appendingPathComponent("index.js"),
                            atomically: true, encoding: .utf8)
            try packageJSON.write(to: pluginDir.appendingPathComponent("package.json"),
                                atomically: true, encoding: .utf8)
            pluginInstalled = true
            logger.info("Plugin installed (local mode) to \(pluginDir.path)")
        } catch {
            logger.error("Failed to write plugin files: \(error.localizedDescription)")
            return false
        }

        // Rockpile auto-discovers plugins in ~/.rockpile/plugins/ — no config registration needed
        return true
    }

    // MARK: - Connection Test

    func testConnection(host: String, port: UInt16 = 18790) async {
        isTestingConnection = true
        connectionTestResult = .testing

        let payload = """
        {"session_id":"setup-test","event":"SessionStart","status":"idle","ts":\(Int(Date().timeIntervalSince1970 * 1000))}
        """

        let urlString = "http://\(host):\(port)/hook"
        guard let url = URL(string: urlString) else {
            connectionTestResult = .failed("Invalid URL")
            isTestingConnection = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload.data(using: .utf8)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                connectionTestResult = .success
            } else {
                connectionTestResult = .failed("Server returned error")
            }
        } catch {
            connectionTestResult = .failed(error.localizedDescription)
        }

        isTestingConnection = false
    }

    // MARK: - Registration (控制端 → 服务端)

    /// 控制端向服务端注册自己的 IP，服务端收到后自动生成 Rockpile 插件
    func registerWithServer(serverIP: String, port: UInt16 = 18790) async -> Bool {
        let myIP = localIPAddress
        let payload = "{\"monitorIP\":\"\(myIP)\",\"monitorPort\":\(SocketServer.tcpPort)}"

        let urlString = "http://\(serverIP):\(port)/register"
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload.data(using: .utf8)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                logger.info("Registered with server \(serverIP, privacy: .public)")
                // Parse host's commandToken and commandPort for reverse commands
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let token = json["commandToken"] as? String, !token.isEmpty {
                        AppSettings.commandToken = token
                        logger.info("Saved host commandToken for reverse commands")
                    }
                    if let port = json["commandPort"] as? Int {
                        AppSettings.commandPort = UInt16(port)
                    }
                }
                return true
            }
        } catch {
            logger.error("Failed to register: \(error.localizedDescription)")
        }
        return false
    }

    // MARK: - Helpers

    static func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST
                    )
                    address = String(decoding: hostname.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        .trimmingCharacters(in: .init(charactersIn: "\0"))
                    if address != nil { break }
                }
            }
        }
        return address
    }

    // MARK: - Private

    private func setEnvironmentVariable(host: String, port: UInt16) {
        // Sanitize host: only allow IP-safe characters (digits, dots, letters, hyphens)
        let sanitized = host.filter { $0.isNumber || $0.isLetter || $0 == "." || $0 == "-" }
        guard !sanitized.isEmpty, sanitized == host else {
            logger.warning("Rejected unsafe host value for .zshrc: \(host, privacy: .public)")
            return
        }

        let profile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zshrc")

        guard var content = try? String(contentsOf: profile, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n").filter {
            !$0.contains("ROCKPILE_HOST") && !$0.contains("ROCKPILE_PORT") &&
            !$0.contains("# Rockpile")
        }
        content = lines.joined(separator: "\n")
        content += "\n\n# Rockpile monitor target\n"
        content += "export ROCKPILE_HOST=\"\(sanitized)\"\n"
        content += "export ROCKPILE_PORT=\(port)\n"

        try? content.write(to: profile, atomically: true, encoding: .utf8)
        logger.info("Set ROCKPILE_HOST=\(sanitized) in ~/.zshrc")
    }

    // MARK: - Plugin JS Generators

    /// Shared hook body JS with token usage reading from ~/.claude/stats-cache.json
    private static let pluginHookBody = PluginInstaller.sharedPluginHookBody

    /// Generate plugin JS for TCP mode (remote monitoring)
    private func generatePluginJS(host: String, port: UInt16) -> String {
        return """
        const { Socket } = require("net");

        const ROCKPILE_HOST = process.env.ROCKPILE_HOST || "\(host)";
        const ROCKPILE_PORT = parseInt(process.env.ROCKPILE_PORT || "\(port)", 10);

        function sendEvent(payload) {
          const client = new Socket();
          const data = JSON.stringify(payload);
          client.connect(ROCKPILE_PORT, ROCKPILE_HOST, () => {
            client.write(data);
            client.end();
          });
          client.on("error", () => {});
        }

        module.exports = function rockpilePlugin(api) {
          console.log("[rockpile] TCP mode -> " + ROCKPILE_HOST + ":" + ROCKPILE_PORT);
        \(Self.pluginHookBody)
        """
    }

    /// Generate plugin JS for local mode (Unix socket)
    private func generatePluginJSLocal() -> String {
        return """
        const { Socket } = require("net");
        const SOCKET_PATH = "/tmp/rockpile.sock";

        function sendEvent(payload) {
          const client = new Socket();
          client.connect(SOCKET_PATH, () => {
            client.write(JSON.stringify(payload));
            client.end();
          });
          client.on("error", () => {});
        }

        module.exports = function rockpilePlugin(api) {
          console.log("[rockpile] Unix socket mode -> " + SOCKET_PATH);
        \(Self.pluginHookBody)
        """
    }
}
