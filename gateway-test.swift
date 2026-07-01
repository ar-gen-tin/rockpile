#!/usr/bin/env swift
// gateway-test.swift — 连接 OpenClaw Gateway WebSocket，读取 Dashboard 信息
// Usage: swift gateway-test.swift [host] [port] [token]

import Foundation

// MARK: - Config

let host = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "127.0.0.1"
let port = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "18789"
guard CommandLine.arguments.count > 3 else {
    print("Usage: swift gateway-test.swift <host> <port> <token>")
    print("  token: Gateway auth token (required, never hardcode)")
    exit(1)
}
let token = CommandLine.arguments[3]

let wsURL = URL(string: "ws://\(host):\(port)")!
print("🔌 Connecting to \(wsURL.absoluteString)...")
print("🔑 Token: \(token.prefix(8))...\(token.suffix(8))")
print()

// MARK: - State

let session = URLSession(configuration: .default)
let ws = session.webSocketTask(with: wsURL)

var connectRequestId: String?
var pendingMethodIds: [String: String] = [:]  // id → method name
let done = DispatchSemaphore(value: 0)
var methodsReceived = 0
let expectedMethods = 5  // health, status, sessions.list, channels.status, models.list

// MARK: - Helpers

func sendJSON(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        print("❌ Failed to encode JSON")
        return
    }
    ws.send(.string(text)) { error in
        if let error { print("❌ Send error: \(error.localizedDescription)") }
    }
}

func prettyJSON(_ obj: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        return "\(obj)"
    }
    return str
}

func sendMethod(_ method: String, params: [String: Any] = [:]) {
    let id = UUID().uuidString
    pendingMethodIds[id] = method
    let req: [String: Any] = [
        "type": "req",
        "id": id,
        "method": method,
        "params": params,
    ]
    print("📤 Requesting: \(method)")
    sendJSON(req)
}

// MARK: - Message Handler

func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else {
        print("⚠️  Malformed message: \(text.prefix(200))")
        return
    }

    switch type {
    case "event":
        guard let event = json["event"] as? String else { return }

        if event == "connect.challenge" {
            guard let payload = json["payload"] as? [String: Any],
                  let nonce = payload["nonce"] as? String else {
                print("❌ Malformed challenge")
                done.signal()
                return
            }
            print("📨 Challenge nonce: \(nonce.prefix(16))...")
            print("🔐 Authenticating...")
            print()

            let id = UUID().uuidString
            connectRequestId = id

            // Valid client.id must be from GATEWAY_CLIENT_ID_SET
            // Options: "cli", "gateway-client", "openclaw-macos", "test", etc.
            let connectReq: [String: Any] = [
                "type": "req",
                "id": id,
                "method": "connect",
                "params": [
                    "minProtocol": 3,
                    "maxProtocol": 3,
                    "client": [
                        "id": "gateway-client",
                        "version": "1.2.0",
                        "platform": "darwin",
                        "mode": "backend",
                    ] as [String: Any],
                    "role": "operator",
                    "scopes": ["operator.admin"],
                    "caps": ["tool-events"],
                    "auth": [
                        "token": token,
                    ] as [String: Any],
                    "locale": "zh-CN",
                ] as [String: Any],
            ]
            sendJSON(connectReq)
        } else {
            // Print other events (streaming, state changes, etc.)
            print("📨 Event: \(event)")
            if let payload = json["payload"] {
                print("   \(prettyJSON(payload).prefix(500))")
            }
        }

    case "res":
        guard let id = json["id"] as? String else { return }
        let ok = json["ok"] as? Bool ?? false

        // Connect response
        if id == connectRequestId {
            if ok {
                print("✅ Connected to Gateway!")
                print()

                if let payload = json["payload"] as? [String: Any] {
                    // Server info
                    if let server = payload["server"] as? [String: Any] {
                        print("═══════════════════════════════════════")
                        print("  🖥  Server Info")
                        print("═══════════════════════════════════════")
                        for (k, v) in server.sorted(by: { $0.key < $1.key }) {
                            if let dict = v as? [String: Any] {
                                print("  \(k): \(prettyJSON(dict))")
                            } else {
                                print("  \(k): \(v)")
                            }
                        }
                        print()
                    }

                    // Auth info
                    if let auth = payload["auth"] as? [String: Any] {
                        print("═══════════════════════════════════════")
                        print("  🔒 Auth Info")
                        print("═══════════════════════════════════════")
                        for (k, v) in auth.sorted(by: { $0.key < $1.key }) {
                            print("  \(k): \(v)")
                        }
                        print()
                    }

                    // Features
                    if let features = payload["features"] as? [String: Any] {
                        print("═══════════════════════════════════════")
                        print("  ⚡ Features")
                        print("═══════════════════════════════════════")
                        if let methods = features["methods"] as? [String] {
                            print("  Methods (\(methods.count)):")
                            for m in methods.sorted() { print("    • \(m)") }
                        } else {
                            print("  \(prettyJSON(features).prefix(2000))")
                        }
                        print()
                    }

                    // Snapshot (initial dashboard data)
                    if let snapshot = payload["snapshot"] as? [String: Any] {
                        print("═══════════════════════════════════════")
                        print("  📊 Initial Snapshot")
                        print("═══════════════════════════════════════")
                        printSnapshot(snapshot)
                        print()
                    }

                    // Policy
                    if let policy = payload["policy"] as? [String: Any] {
                        print("  ⏱  Policy: \(prettyJSON(policy))")
                        print()
                    }
                }

                // Now query dashboard methods
                print("═══════════════════════════════════════")
                print("  📡 Querying Dashboard APIs...")
                print("═══════════════════════════════════════")
                print()

                sendMethod("health")
                sendMethod("status")
                sendMethod("sessions.list")
                sendMethod("channels.status")
                sendMethod("models.list")

            } else {
                let errObj = json["error"] as? [String: Any]
                let errorMsg = errObj?["message"] as? String ?? "unknown"
                let errorCode = errObj?["code"] as? String ?? ""
                print("❌ Auth failed: [\(errorCode)] \(errorMsg)")
                print()
                print("Full response:")
                print(prettyJSON(json))
                done.signal()
            }
            return
        }

        // Method responses
        if let method = pendingMethodIds.removeValue(forKey: id) {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("  📬 \(method) → \(ok ? "✅" : "❌")")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            if ok, let payload = json["payload"] {
                switch method {
                case "sessions.list":
                    if let sessions = (payload as? [String: Any])?["sessions"] as? [[String: Any]] {
                        printSessions(sessions)
                    } else if let sessions = payload as? [[String: Any]] {
                        printSessions(sessions)
                    } else {
                        print(prettyJSON(payload))
                    }
                default:
                    print(prettyJSON(payload))
                }
            } else if !ok {
                let errObj = json["error"] as? [String: Any]
                print("  Error: \(errObj?["message"] ?? "unknown")")
            }
            print()

            methodsReceived += 1
            if methodsReceived >= expectedMethods {
                done.signal()
            }
        }

    default:
        print("❓ Unknown type: \(type)")
    }
}

func printSnapshot(_ snapshot: [String: Any]) {
    if let sessions = snapshot["sessions"] as? [[String: Any]] {
        print("  Sessions (\(sessions.count)):")
        printSessions(sessions)
    }
    for (key, value) in snapshot.sorted(by: { $0.key < $1.key }) {
        if key == "sessions" { continue }
        if let arr = value as? [Any] {
            print("  \(key): [\(arr.count) items]")
        } else if let dict = value as? [String: Any] {
            print("  \(key):")
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                print("    \(k): \(v)")
            }
        } else {
            print("  \(key): \(value)")
        }
    }
}

func printSessions(_ sessions: [[String: Any]]) {
    if sessions.isEmpty {
        print("  (no active sessions)")
        return
    }
    for (i, sess) in sessions.enumerated() {
        let key = sess["key"] as? String ?? sess["sessionKey"] as? String ?? "?"
        let status = sess["status"] as? String ?? sess["state"] as? String ?? "?"
        let model = sess["model"] as? String ?? "?"
        let cwd = sess["cwd"] as? String ?? "?"
        print()
        print("  [\(i + 1)] Key:    \(key)")
        print("      Status: \(status)")
        print("      Model:  \(model)")
        print("      CWD:    \(cwd)")
        for (k, v) in sess.sorted(by: { $0.key < $1.key }) {
            if ["key", "sessionKey", "status", "state", "model", "cwd"].contains(k) { continue }
            if let dict = v as? [String: Any] {
                print("      \(k): \(prettyJSON(dict).prefix(300))")
            } else if let arr = v as? [Any] {
                print("      \(k): [\(arr.count) items]")
            } else {
                print("      \(k): \(v)")
            }
        }
    }
}

// MARK: - Receive Loop

func receiveLoop() {
    ws.receive { result in
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                handleMessage(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }
            @unknown default:
                break
            }
            receiveLoop()
        case .failure(let error):
            print("❌ WebSocket error: \(error.localizedDescription)")
            done.signal()
        }
    }
}

// MARK: - Main

ws.resume()
receiveLoop()

// Wait for all responses (timeout 20s)
let result = done.wait(timeout: .now() + 20)
if result == .timedOut {
    print("⏰ Timeout — waited 20s")
}

ws.cancel(with: .goingAway, reason: nil)
session.invalidateAndCancel()
print()
print("🔌 Disconnected")
