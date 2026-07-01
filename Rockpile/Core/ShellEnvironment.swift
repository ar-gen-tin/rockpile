import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "ShellEnvironment")

/// Shell 环境探测器 — 解析用户登录 shell 的完整 PATH 和环境变量
///
/// 灵感: lil-agents 的 ShellEnvironment 类
/// macOS GUI 应用的 PATH 通常只有 /usr/bin:/bin，缺少 Homebrew/mise/nvm 等路径。
/// 此类通过启动用户的登录 shell 获取完整环境，缓存后供 HookInstaller 等使用。
///
/// 用法:
/// ```swift
/// let path = await ShellEnvironment.shared.resolvedPATH
/// let binary = await ShellEnvironment.shared.findBinary("claude")
/// ```
@MainActor
final class ShellEnvironment {
    static let shared = ShellEnvironment()

    /// 缓存的完整 PATH（从登录 shell 获取）
    private(set) var resolvedPATH: String?

    /// 缓存的环境变量
    private(set) var resolvedEnvironment: [String: String]?

    /// 二进制路径缓存 (lil-agents 模式: 每个 binary 只查找一次)
    private var binaryCache: [String: String] = [:]

    /// 是否正在解析中
    private var isResolving = false

    /// 常见二进制安装位置（fallback 搜索路径）
    private static let fallbackPaths = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "\(NSHomeDirectory())/.local/bin",
        "\(NSHomeDirectory())/.cargo/bin",
        "\(NSHomeDirectory())/.nvm/versions/node",  // Node.js
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    private init() {}

    // MARK: - Public API

    /// 解析用户 shell 环境（首次调用时执行，结果缓存）
    func resolveIfNeeded() async {
        guard resolvedPATH == nil, !isResolving else { return }
        isResolving = true
        defer { isResolving = false }

        let shell = detectLoginShell()
        logger.info("Resolving shell environment via \(shell, privacy: .public)")

        do {
            let env = try await runShellForEnvironment(shell: shell)
            resolvedPATH = env["PATH"]
            resolvedEnvironment = env
            logger.info("Resolved PATH with \(env["PATH"]?.components(separatedBy: ":").count ?? 0) entries")
        } catch {
            logger.error("Failed to resolve shell environment: \(error.localizedDescription)")
            // Fallback: use known paths
            resolvedPATH = Self.fallbackPaths.joined(separator: ":")
        }
    }

    /// 查找二进制文件路径 (带缓存，lil-agents findBinary 模式)
    func findBinary(_ name: String) async -> String? {
        // 检查缓存
        if let cached = binaryCache[name] {
            return cached
        }

        // 确保 PATH 已解析
        await resolveIfNeeded()

        let fm = FileManager.default

        // 在 resolved PATH 中搜索
        if let path = resolvedPATH {
            for dir in path.components(separatedBy: ":") {
                let fullPath = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: fullPath) {
                    binaryCache[name] = fullPath
                    logger.info("Found \(name, privacy: .public) at \(fullPath, privacy: .public)")
                    return fullPath
                }
            }
        }

        // Fallback: 搜索常见位置
        for dir in Self.fallbackPaths {
            let fullPath = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: fullPath) {
                binaryCache[name] = fullPath
                logger.info("Found \(name, privacy: .public) at fallback \(fullPath, privacy: .public)")
                return fullPath
            }
        }

        logger.warning("Binary not found: \(name, privacy: .public)")
        return nil
    }

    /// 清除缓存（环境变化时调用）
    func invalidateCache() {
        resolvedPATH = nil
        resolvedEnvironment = nil
        binaryCache.removeAll()
    }

    // MARK: - Private

    /// 检测用户的登录 shell
    private func detectLoginShell() -> String {
        // 优先使用 SHELL 环境变量
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        // macOS 默认 zsh
        return "/bin/zsh"
    }

    /// 启动登录 shell 获取完整环境变量
    private func runShellForEnvironment(shell: String) async throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l: login shell (加载 .zprofile/.bash_profile)
        // -i: interactive (加载 .zshrc/.bashrc — 可能有 PATH 修改)
        // -c: 执行命令后退出
        process.arguments = ["-l", "-i", "-c", "env"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // 设置超时: 3 秒内必须完成
        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            // 在后台读取 + 超时控制
            Task.detached {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: ShellError.nonZeroExit(process.terminationStatus))
                    return
                }

                guard let output = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: ShellError.invalidOutput)
                    return
                }

                var env: [String: String] = [:]
                for line in output.components(separatedBy: "\n") {
                    guard let eqIdx = line.firstIndex(of: "=") else { continue }
                    let key = String(line[line.startIndex..<eqIdx])
                    let value = String(line[line.index(after: eqIdx)...])
                    env[key] = value
                }
                continuation.resume(returning: env)
            }
        }
    }

    private enum ShellError: LocalizedError {
        case nonZeroExit(Int32)
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code): return "Shell exited with code \(code)"
            case .invalidOutput: return "Invalid shell output encoding"
            }
        }
    }
}
