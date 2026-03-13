import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "SocketServer")

typealias HookEventHandler = @Sendable (HookEvent, EventSource) -> Void

final class SocketServer: @unchecked Sendable {
    static let shared = SocketServer()
    static let socketPath = "/tmp/rockpile.sock"
    static let tcpPort: UInt16 = 18790

    private var unixSocket: Int32 = -1
    private var tcpSocket: Int32 = -1
    private var unixAcceptSource: DispatchSourceRead?
    private var tcpAcceptSource: DispatchSourceRead?
    private var eventHandler: HookEventHandler?
    private let queue = DispatchQueue(label: "com.rockpile.socket", qos: .userInitiated)

    /// Last remote client IP that sent us an event (auto-discovery for reverse commands).
    /// Thread-safe: written from `queue`, read via `queue.sync`.
    private var _lastRemoteClientIP: String?
    var lastRemoteClientIP: String? {
        queue.sync { _lastRemoteClientIP }
    }

    /// Whether either socket (Unix or TCP) is actively listening
    var isListening: Bool {
        queue.sync { unixSocket >= 0 || tcpSocket >= 0 }
    }

    private init() {}

    func start(onEvent: @escaping HookEventHandler) {
        queue.async { [weak self] in
            self?.eventHandler = onEvent
            self?.startUnixSocket()
            self?.startTCPSocket()
        }
    }

    // MARK: - Unix Socket (local)

    private func startUnixSocket() {
        guard unixSocket < 0 else { return }

        unlink(Self.socketPath)

        unixSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard unixSocket >= 0 else {
            logger.error("Failed to create Unix socket: \(errno)")
            return
        }

        let flags = fcntl(unixSocket, F_GETFL)
        _ = fcntl(unixSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(unixSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind Unix socket: \(errno)")
            close(unixSocket)
            unixSocket = -1
            return
        }

        chmod(Self.socketPath, 0o700)

        guard listen(unixSocket, 128) == 0 else {
            logger.error("Failed to listen on Unix socket: \(errno)")
            close(unixSocket)
            unixSocket = -1
            return
        }

        logger.info("Unix socket listening: \(Self.socketPath, privacy: .public)")

        unixAcceptSource = DispatchSource.makeReadSource(fileDescriptor: unixSocket, queue: queue)
        unixAcceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection(on: self?.unixSocket ?? -1, source: .unixSocket)
        }
        unixAcceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.unixSocket, fd >= 0 {
                close(fd)
                self?.unixSocket = -1
            }
        }
        unixAcceptSource?.resume()
    }

    // MARK: - TCP Socket (remote / LAN)

    private func startTCPSocket() {
        guard tcpSocket < 0 else { return }

        tcpSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard tcpSocket >= 0 else {
            logger.error("Failed to create TCP socket: \(errno)")
            return
        }

        var reuse: Int32 = 1
        setsockopt(tcpSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(tcpSocket, F_GETFL)
        _ = fcntl(tcpSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.tcpPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY  // Listen on all interfaces

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(tcpSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind TCP port \(Self.tcpPort): errno=\(errno)")
            close(tcpSocket)
            tcpSocket = -1
            return
        }

        guard listen(tcpSocket, 128) == 0 else {
            logger.error("Failed to listen on TCP: \(errno)")
            close(tcpSocket)
            tcpSocket = -1
            return
        }

        logger.info("TCP socket listening on port \(Self.tcpPort)")

        tcpAcceptSource = DispatchSource.makeReadSource(fileDescriptor: tcpSocket, queue: queue)
        tcpAcceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection(on: self?.tcpSocket ?? -1, source: .tcpSocket)
        }
        tcpAcceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.tcpSocket, fd >= 0 {
                close(fd)
                self?.tcpSocket = -1
            }
        }
        tcpAcceptSource?.resume()
    }

    // MARK: - Shared

    func stop() {
        unixAcceptSource?.cancel()
        unixAcceptSource = nil
        tcpAcceptSource?.cancel()
        tcpAcceptSource = nil
        unlink(Self.socketPath)
    }

    private func acceptConnection(on serverFd: Int32, source: EventSource) {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(serverFd, sockaddrPtr, &addrLen)
            }
        }
        guard clientSocket >= 0 else { return }

        // Extract client IP for logging
        var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var addr = clientAddr.sin_addr
        inet_ntop(AF_INET, &addr, &ipStr, socklen_t(INET_ADDRSTRLEN))
        let clientIP = String(cString: ipStr)

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Set receive timeout as safety net for stuck connections.
        // HTTP: we use Content-Length for precise reading; this is just a fallback.
        // Raw JSON: plugin calls .end() after writing, so read completes on FIN.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Track remote client IP for reverse command auto-discovery
        if clientIP != "0.0.0.0" && clientIP != "127.0.0.1" && clientIP != "local" {
            _lastRemoteClientIP = clientIP
        }

        handleClient(clientSocket, clientIP: clientIP, source: source)
    }

    private func handleClient(_ clientSocket: Int32, clientIP: String = "local", source: EventSource = .tcpSocket) {
        defer { close(clientSocket) }

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)

        // Read initial data
        let firstRead = read(clientSocket, &buffer, buffer.count)
        guard firstRead > 0 else { return }
        allData.append(contentsOf: buffer[0..<firstRead])

        // Detect HTTP vs raw JSON by first bytes
        let isHTTP = allData.starts(with: Data("POST ".utf8)) ||
                     allData.starts(with: Data("GET ".utf8))

        if isHTTP {
            // HTTP: read until headers complete, then use Content-Length for body
            let headerSep = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
            let altSep = Data([0x0A, 0x0A])                  // \n\n

            while allData.range(of: headerSep) == nil && allData.range(of: altSep) == nil {
                let n = read(clientSocket, &buffer, buffer.count)
                guard n > 0 else { break }
                allData.append(contentsOf: buffer[0..<n])
            }

            // Parse Content-Length and read exact body
            if let sepRange = allData.range(of: headerSep) ?? allData.range(of: altSep) {
                let headerBytes = allData[allData.startIndex..<sepRange.lowerBound]
                let contentLength = parseContentLength(String(data: headerBytes, encoding: .utf8) ?? "")
                if contentLength > 0 {
                    let bodyStart = allData.distance(from: allData.startIndex, to: sepRange.upperBound)
                    var bodyReceived = allData.count - bodyStart
                    while bodyReceived < contentLength {
                        let n = read(clientSocket, &buffer, buffer.count)
                        guard n > 0 else {
                            logger.warning("Incomplete HTTP body: \(bodyReceived)/\(contentLength) bytes from \(clientIP)")
                            break
                        }
                        allData.append(contentsOf: buffer[0..<n])
                        bodyReceived += n
                    }
                }
            }
        } else {
            // Raw JSON: plugin calls .end() after writing, read until close
            while true {
                let n = read(clientSocket, &buffer, buffer.count)
                guard n > 0 else { break }
                allData.append(contentsOf: buffer[0..<n])
            }
        }

        guard !allData.isEmpty else { return }

        // Log raw data receipt with client IP
        let byteCount = allData.count
        Task { @MainActor in
            EventLogger.shared.logRawEvent(source: "TCP", byteCount: byteCount, clientIP: clientIP)
        }

        // Detect HTTP POST vs raw JSON
        let jsonData: Data
        if let rawString = String(data: allData, encoding: .utf8),
           rawString.hasPrefix("POST ") || rawString.hasPrefix("GET ") {
            jsonData = handleHTTPRequest(rawString: rawString, clientSocket: clientSocket, rawData: allData)
        } else {
            jsonData = allData
        }

        guard !jsonData.isEmpty else { return }

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: jsonData) else {
            let raw = String(data: jsonData, encoding: .utf8) ?? "binary"
            logger.warning("Failed to parse event: \(raw, privacy: .public)")
            Task { @MainActor in
                EventLogger.shared.logParseError(detail: String(raw.prefix(200)))
                StateMachine.shared.reportError("事件解析失败")
            }
            return
        }

        logEvent(event)
        Task { @MainActor in
            EventLogger.shared.logEvent(event)
        }
        eventHandler?(event, source)
    }

    /// Parse HTTP request, send 200 response, return JSON body
    private func handleHTTPRequest(rawString: String, clientSocket: Int32, rawData: Data) -> Data {
        // Find the blank line separating headers from body (\r\n\r\n)
        guard let headerEndRange = rawString.range(of: "\r\n\r\n") else {
            // Try \n\n as fallback
            guard let altRange = rawString.range(of: "\n\n") else {
                sendHTTPResponse(clientSocket, status: 400, body: "{\"error\":\"malformed request\"}")
                return Data()
            }
            let bodyStart = rawString[altRange.upperBound...]
            sendHTTPResponse(clientSocket, status: 200, body: "{\"ok\":true}")
            return Data(bodyStart.utf8)
        }

        let requestLine = rawString[rawString.startIndex..<(rawString.range(of: "\r\n")?.lowerBound ?? rawString.endIndex)]
        logger.info("HTTP: \(String(requestLine), privacy: .public)")

        let bodyString = rawString[headerEndRange.upperBound...]

        // Handle GET /health for connectivity checks
        if requestLine.hasPrefix("GET ") {
            sendHTTPResponse(clientSocket, status: 200, body: "{\"status\":\"ok\",\"app\":\"Rockpile\"}")
            return Data()
        }

        // Handle POST /register — 控制端注册自己的 IP，服务端自动生成插件
        if requestLine.contains("/register") {
            handleRegisterRequest(body: String(bodyString), clientSocket: clientSocket)
            return Data()
        }

        // Send HTTP 200 response
        sendHTTPResponse(clientSocket, status: 200, body: "{\"ok\":true}")

        guard !bodyString.isEmpty else { return Data() }
        return Data(bodyString.utf8)
    }

    private func sendHTTPResponse(_ clientSocket: Int32, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : "Bad Request"
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(body)
        """
        let responseData = Array(response.utf8)
        responseData.withUnsafeBufferPointer { buf in
            _ = write(clientSocket, buf.baseAddress!, buf.count)
        }
    }

    /// Handle POST /register: 控制端注册自己的 IP，服务端生成 Rockpile 插件
    private func handleRegisterRequest(body: String, clientSocket: Int32) {
        // Parse {"monitorIP": "x.x.x.x"}
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let monitorIP = json["monitorIP"] as? String, !monitorIP.isEmpty else {
            sendHTTPResponse(clientSocket, status: 400, body: "{\"error\":\"missing monitorIP\"}")
            return
        }

        // Validate IP format to prevent injection
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        guard monitorIP.range(of: ipPattern, options: .regularExpression) != nil else {
            sendHTTPResponse(clientSocket, status: 400, body: "{\"error\":\"invalid monitorIP format\"}")
            return
        }

        let port = (json["monitorPort"] as? NSNumber).flatMap { UInt16(exactly: $0) } ?? 18790

        logger.info("Register request: monitorIP=\(monitorIP, privacy: .public) port=\(port)")

        // Parse optional commandPort from registering client
        let remoteCommandPort = (json["commandPort"] as? NSNumber).flatMap { UInt16(exactly: $0) }

        // Save and install plugin on main thread, wait for completion before responding
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            AppSettings.monitorHost = monitorIP
            if let rcp = remoteCommandPort {
                AppSettings.commandPort = rcp
            }
            PluginInstaller.installTCPPlugin(targetHost: monitorIP, targetPort: port)
            logger.info("Plugin installed for monitor \(monitorIP, privacy: .public):\(port)")
            semaphore.signal()
        }

        // Wait up to 5s for main thread to finish
        _ = semaphore.wait(timeout: .now() + 5)

        // Read values directly from UserDefaults (thread-safe) after main thread completes
        let defaults = UserDefaults.standard
        let cmdPort = defaults.integer(forKey: "commandPort")
        let cmdPortVal = cmdPort > 0 ? UInt16(cmdPort) : UInt16(18793)
        let cmdToken = defaults.string(forKey: "commandToken") ?? ""
        let safeToken = cmdToken.replacingOccurrences(of: "\"", with: "")
        sendHTTPResponse(clientSocket, status: 200, body: "{\"ok\":true,\"needRestart\":true,\"commandPort\":\(cmdPortVal),\"commandToken\":\"\(safeToken)\"}")
    }

    /// Extract Content-Length value from HTTP headers string
    private func parseContentLength(_ headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func logEvent(_ event: HookEvent) {
        switch event.event {
        case "SessionStart":
            logger.info("Session started: \(event.sessionId, privacy: .public)")
        case "SessionEnd":
            logger.info("Session ended: \(event.sessionId, privacy: .public)")
        case "LLMInput":
            logger.info("Thinking...")
        case "LLMOutput":
            logger.info("Working...")
        case "ToolCall":
            let tool = event.tool ?? "unknown"
            logger.info("Tool: \(tool, privacy: .public)")
        case "ToolResult":
            let tool = event.tool ?? "unknown"
            let success = event.status != "error"
            logger.info("Result: \(success ? "ok" : "error", privacy: .public) \(tool, privacy: .public)")
        case "AgentEnd":
            logger.info("Done")
        default:
            break
        }
    }
}
