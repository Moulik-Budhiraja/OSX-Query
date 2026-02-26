import Foundation
import Testing
@testable import AXorcist

@Suite("AXorcist Legacy JSON CLI Disabled Tests", .tags(.safe))
struct PingIntegrationTests {
    @Test("Rejects legacy --stdin flag", .tags(.safe))
    func rejectsLegacyStdinFlag() throws {
        let result = try runAXORCCommand(arguments: ["--stdin"])
        #expect(result.exitCode != 0)

        let errorResponse = try self.decodeErrorResponse(from: result.output)
        #expect(errorResponse.commandId == "argument_error")
        #expect(errorResponse.error.message.contains("Unknown option --stdin"))
    }

    @Test("Rejects legacy --file flag", .tags(.safe))
    func rejectsLegacyFileFlag() throws {
        let result = try runAXORCCommand(arguments: ["--file", "/tmp/legacy.json"])
        #expect(result.exitCode != 0)

        let errorResponse = try self.decodeErrorResponse(from: result.output)
        #expect(errorResponse.commandId == "argument_error")
        #expect(errorResponse.error.message.contains("Unknown option --file"))
    }

    @Test("Rejects legacy --json flag", .tags(.safe))
    func rejectsLegacyJSONFlag() throws {
        let result = try runAXORCCommand(arguments: ["--json", "{}"])
        #expect(result.exitCode != 0)

        let errorResponse = try self.decodeErrorResponse(from: result.output)
        #expect(errorResponse.commandId == "argument_error")
        #expect(errorResponse.error.message.contains("Unknown option --json"))
    }

    @Test("Rejects legacy positional JSON payload", .tags(.safe))
    func rejectsLegacyPositionalPayload() throws {
        let payload = #"{"command":"ping"}"#
        let result = try runAXORCCommand(arguments: [payload])
        #expect(result.exitCode != 0)

        let errorResponse = try self.decodeErrorResponse(from: result.output)
        #expect(errorResponse.commandId == "argument_error")
    }

    @Test("Rejects empty invocation without selector or AX exposure mode", .tags(.safe))
    func rejectsNoModeInvocation() throws {
        let result = try runAXORCCommand(arguments: [])
        #expect(result.exitCode != 0)

        let errorResponse = try self.decodeErrorResponse(from: result.output)
        #expect(errorResponse.commandId == "argument_error")
        #expect(errorResponse.error.message.contains("No CLI mode selected"))
    }

    private func decodeErrorResponse(from output: String?) throws -> ErrorResponse {
        guard let output, let data = output.data(using: .utf8) else {
            Issue.record("Expected JSON error output from CLI, received nil/invalid output.")
            throw CancellationError()
        }
        return try JSONDecoder().decode(ErrorResponse.self, from: data)
    }
}
