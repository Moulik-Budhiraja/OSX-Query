import AXorcist
import Darwin
import Foundation

enum SelectorCacheDaemonError: LocalizedError {
    case socketPathTooLong(String)
    case socketCreateFailed(String)
    case socketBindFailed(String)
    case socketListenFailed(String)
    case socketAcceptFailed(String)
    case socketConnectFailed(String)
    case socketReadFailed(String)
    case socketWriteFailed(String)
    case daemonStartFailed(String)
    case daemonUnavailable(String)
    case invalidRequest(String)
    case invalidResponse(String)
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case let .socketPathTooLong(path):
            "Selector cache daemon socket path is too long: \(path)"
        case let .socketCreateFailed(details):
            "Failed to create selector cache daemon socket: \(details)"
        case let .socketBindFailed(details):
            "Failed to bind selector cache daemon socket: \(details)"
        case let .socketListenFailed(details):
            "Failed to listen on selector cache daemon socket: \(details)"
        case let .socketAcceptFailed(details):
            "Failed to accept selector cache daemon client: \(details)"
        case let .socketConnectFailed(details):
            "Failed to connect to selector cache daemon: \(details)"
        case let .socketReadFailed(details):
            "Failed to read selector cache daemon payload: \(details)"
        case let .socketWriteFailed(details):
            "Failed to write selector cache daemon payload: \(details)"
        case let .daemonStartFailed(details):
            "Failed to launch selector cache daemon: \(details)"
        case let .daemonUnavailable(details):
            "Selector cache daemon is unavailable: \(details)"
        case let .invalidRequest(details):
            "Selector cache daemon received invalid request: \(details)"
        case let .invalidResponse(details):
            "Selector cache daemon returned invalid response: \(details)"
        case let .remoteError(details):
            details
        }
    }
}

@MainActor
enum SelectorCacheDaemonServer {
    private static let idleTimeoutSeconds: Int = 600

    static func run(socketPath: String) throws {
        let serverFD = try SelectorCacheSocketTransport.makeServerSocket(path: socketPath)
        defer {
            Darwin.close(serverFD)
            Darwin.unlink(socketPath)
        }

        let runner = SelectorQueryRunner()

        while true {
            var pollDescriptor = pollfd(fd: serverFD, events: Int16(POLLIN), revents: 0)
            let timeoutMilliseconds = Int32(self.idleTimeoutSeconds * 1000)
            let ready = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
            if ready == 0 {
                return
            }
            if ready < 0 {
                if errno == EINTR {
                    continue
                }
                throw SelectorCacheDaemonError.socketAcceptFailed(String(cString: strerror(errno)))
            }

            let clientFD = Darwin.accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                throw SelectorCacheDaemonError.socketAcceptFailed(String(cString: strerror(errno)))
            }

            do {
                try self.handleClient(fd: clientFD, runner: runner)
            } catch {
                // Best-effort daemon loop: ignore per-request errors and keep serving.
            }
            Darwin.close(clientFD)
        }
    }

    private static func handleClient(fd: Int32, runner: SelectorQueryRunner) throws {
        let requestData = try SelectorCacheSocketTransport.readAll(from: fd)
        guard !requestData.isEmpty else {
            throw SelectorCacheDaemonError.invalidRequest("Empty payload.")
        }

        let decoder = JSONDecoder()
        let requestPayload: SelectorCacheDaemonPayload
        do {
            requestPayload = try decoder.decode(SelectorCacheDaemonPayload.self, from: requestData)
        } catch {
            throw SelectorCacheDaemonError.invalidRequest(error.localizedDescription)
        }

        let response: SelectorCacheDaemonResponse
        do {
            let report = try runner.execute(requestPayload.toSelectorQueryRequest())
            let output = SelectorQueryOutputFormatter.format(report: report)
            response = SelectorCacheDaemonResponse(success: true, output: output, error: nil)
        } catch let parseError as OXQParseError {
            response = SelectorCacheDaemonResponse(
                success: false,
                output: nil,
                error: "Invalid selector query: \(parseError.description)")
        } catch let selectorError as SelectorQueryCLIError {
            response = SelectorCacheDaemonResponse(
                success: false,
                output: nil,
                error: selectorError.localizedDescription)
        } catch {
            response = SelectorCacheDaemonResponse(
                success: false,
                output: nil,
                error: error.localizedDescription)
        }

        let encoded = try JSONEncoder().encode(response)
        try SelectorCacheSocketTransport.writeAll(data: encoded, to: fd)
    }
}

@MainActor
struct SelectorCacheDaemonClient {
    static func defaultSocketPath() -> String {
        "/tmp/axorc-selector-cache-\(getuid()).sock"
    }

    func execute(request: SelectorQueryRequest) throws -> String {
        let socketPath = Self.defaultSocketPath()
        try self.ensureDaemonRunning(socketPath: socketPath)

        let payload = SelectorCacheDaemonPayload(request: request)
        let data = try JSONEncoder().encode(payload)
        let responseData = try SelectorCacheSocketTransport.requestResponse(
            socketPath: socketPath,
            requestData: data)

        let response: SelectorCacheDaemonResponse
        do {
            response = try JSONDecoder().decode(SelectorCacheDaemonResponse.self, from: responseData)
        } catch {
            throw SelectorCacheDaemonError.invalidResponse(error.localizedDescription)
        }

        if response.success, let output = response.output {
            return output
        }

        throw SelectorCacheDaemonError.remoteError(response.error ?? "Unknown selector cache daemon error.")
    }

    private func ensureDaemonRunning(socketPath: String) throws {
        if SelectorCacheSocketTransport.canConnect(socketPath: socketPath) {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [
            "--selector-cache-daemon",
            "--selector-cache-daemon-socket",
            socketPath,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw SelectorCacheDaemonError.daemonStartFailed(error.localizedDescription)
        }

        for _ in 0..<40 {
            if SelectorCacheSocketTransport.canConnect(socketPath: socketPath) {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        throw SelectorCacheDaemonError.daemonUnavailable("Timed out waiting for daemon socket at \(socketPath).")
    }
}

private struct SelectorCacheDaemonPayload: Codable {
    let appIdentifier: String
    let selector: String
    let maxDepth: Int
    let limit: Int
    let colorEnabled: Bool
    let showPath: Bool
    let showNameSource: Bool
    let useCachedSnapshot: Bool
    let interaction: SelectorCacheDaemonInteractionPayload?

    init(request: SelectorQueryRequest) {
        self.appIdentifier = request.appIdentifier
        self.selector = request.selector
        self.maxDepth = request.maxDepth
        self.limit = request.limit
        self.colorEnabled = request.colorEnabled
        self.showPath = request.showPath
        self.showNameSource = request.showNameSource
        self.useCachedSnapshot = request.useCachedSnapshot
        self.interaction = SelectorCacheDaemonInteractionPayload(request.interaction)
    }

    func toSelectorQueryRequest() -> SelectorQueryRequest {
        SelectorQueryRequest(
            appIdentifier: self.appIdentifier,
            selector: self.selector,
            maxDepth: self.maxDepth,
            limit: self.limit,
            colorEnabled: self.colorEnabled,
            showPath: self.showPath,
            showNameSource: self.showNameSource,
            cacheSessionEnabled: true,
            useCachedSnapshot: self.useCachedSnapshot,
            interaction: self.interaction?.toInteractionRequest())
    }
}

private struct SelectorCacheDaemonResponse: Codable {
    let success: Bool
    let output: String?
    let error: String?
}

private enum SelectorCacheDaemonInteractionAction: String, Codable {
    case click
    case press
    case focus
    case setValue
    case setValueAndSubmit
    case sendKeystrokesAndSubmit
}

private struct SelectorCacheDaemonInteractionPayload: Codable {
    let resultIndex: Int
    let action: SelectorCacheDaemonInteractionAction
    let value: String?

    init?(_ interaction: SelectorInteractionRequest?) {
        guard let interaction else { return nil }
        self.resultIndex = interaction.resultIndex

        switch interaction.action {
        case .click:
            self.action = .click
            self.value = nil
        case .press:
            self.action = .press
            self.value = nil
        case .focus:
            self.action = .focus
            self.value = nil
        case let .setValue(value):
            self.action = .setValue
            self.value = value
        case let .setValueAndSubmit(value):
            self.action = .setValueAndSubmit
            self.value = value
        case let .sendKeystrokesAndSubmit(value):
            self.action = .sendKeystrokesAndSubmit
            self.value = value
        }
    }

    func toInteractionRequest() -> SelectorInteractionRequest {
        let selectorAction: SelectorInteractionAction
        switch self.action {
        case .click:
            selectorAction = .click
        case .press:
            selectorAction = .press
        case .focus:
            selectorAction = .focus
        case .setValue:
            selectorAction = .setValue(self.value ?? "")
        case .setValueAndSubmit:
            selectorAction = .setValueAndSubmit(self.value ?? "")
        case .sendKeystrokesAndSubmit:
            selectorAction = .sendKeystrokesAndSubmit(self.value ?? "")
        }
        return SelectorInteractionRequest(resultIndex: self.resultIndex, action: selectorAction)
    }
}

private enum SelectorCacheSocketTransport {
    static func requestResponse(socketPath: String, requestData: Data) throws -> Data {
        let fd = try self.connect(socketPath: socketPath)
        defer { Darwin.close(fd) }

        try self.writeAll(data: requestData, to: fd)
        Darwin.shutdown(fd, SHUT_WR)
        return try self.readAll(from: fd)
    }

    static func canConnect(socketPath: String) -> Bool {
        let fd = try? self.connect(socketPath: socketPath)
        guard let fd else { return false }
        Darwin.close(fd)
        return true
    }

    static func makeServerSocket(path: String) throws -> Int32 {
        try self.validateSocketPath(path)
        Darwin.unlink(path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SelectorCacheDaemonError.socketCreateFailed(String(cString: strerror(errno)))
        }

        do {
            try withSockAddr(path: path) { sockAddr, sockLen in
                if Darwin.bind(fd, sockAddr, sockLen) != 0 {
                    throw SelectorCacheDaemonError.socketBindFailed(String(cString: strerror(errno)))
                }
            }

            if Darwin.listen(fd, 16) != 0 {
                throw SelectorCacheDaemonError.socketListenFailed(String(cString: strerror(errno)))
            }

            _ = Darwin.chmod(path, mode_t(0o600))
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func connect(socketPath: String) throws -> Int32 {
        try self.validateSocketPath(socketPath)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SelectorCacheDaemonError.socketCreateFailed(String(cString: strerror(errno)))
        }

        do {
            try withSockAddr(path: socketPath) { sockAddr, sockLen in
                if Darwin.connect(fd, sockAddr, sockLen) != 0 {
                    throw SelectorCacheDaemonError.socketConnectFailed(String(cString: strerror(errno)))
                }
            }
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    static func readAll(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)

        while true {
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
                continue
            }
            if bytesRead == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            throw SelectorCacheDaemonError.socketReadFailed(String(cString: strerror(errno)))
        }

        return data
    }

    static func writeAll(data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var offset = 0
            while offset < rawBuffer.count {
                let remaining = rawBuffer.count - offset
                let written = Darwin.write(fd, baseAddress.advanced(by: offset), remaining)
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0, errno == EINTR {
                    continue
                }
                throw SelectorCacheDaemonError.socketWriteFailed(String(cString: strerror(errno)))
            }
        }
    }

    private static func validateSocketPath(_ path: String) throws {
        let maxLen = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard path.utf8.count < maxLen else {
            throw SelectorCacheDaemonError.socketPathTooLong(path)
        }
    }

    private static func withSockAddr<T>(
        path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T
    {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { cStringPtr in
                cStringPtr.initialize(repeating: 0, count: sunPathCapacity)
                _ = path.withCString { source in
                    strncpy(cStringPtr, source, sunPathCapacity - 1)
                }
            }
        }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                try body(sockaddrPtr, length)
            }
        }
    }
}
