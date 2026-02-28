import Foundation
import Testing
@testable import axorc

@Suite("OXA Activation")
@MainActor
struct OXAActivationTests {
    @Test("Re-activates even when target is already frontmost")
    func reactivatesWhenAlreadyFrontmost() {
        let state = ActivationState(frontmostPid: 42, focusedPid: nil)

        let success = OXAExecutor.ensureApplicationFrontmost(
            pid: 42,
            timeout: 0.2,
            pollInterval: 0.01,
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            activatePid: { _ in
                state.activationCount += 1
                return true
            },
            frontmostPidProvider: { state.frontmostPid },
            focusedPidProvider: { state.focusedPid },
            axFrontmostProvider: { _ in false })

        #expect(success == true)
        #expect(state.activationCount >= 1)
    }

    @Test("Activates until target becomes focused")
    func activatesUntilTargetBecomesFocused() {
        let state = ActivationState(frontmostPid: nil, focusedPid: nil)

        let success = OXAExecutor.ensureApplicationFrontmost(
            pid: 55,
            timeout: 0.3,
            pollInterval: 0.01,
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            activatePid: { pid in
                state.activationCount += 1
                state.focusedPid = pid
                return true
            },
            frontmostPidProvider: { state.frontmostPid },
            focusedPidProvider: { state.focusedPid },
            axFrontmostProvider: { _ in false })

        #expect(success == true)
        #expect(state.activationCount >= 1)
    }

    @Test("Accepts AX frontmost signal")
    func acceptsAXFrontmostSignal() {
        let state = ActivationState(frontmostPid: nil, focusedPid: nil)

        let success = OXAExecutor.ensureApplicationFrontmost(
            pid: 99,
            timeout: 0.2,
            pollInterval: 0.01,
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            activatePid: { _ in
                state.activationCount += 1
                return true
            },
            frontmostPidProvider: { state.frontmostPid },
            focusedPidProvider: { state.focusedPid },
            axFrontmostProvider: { pid in pid == 99 })

        #expect(success == true)
        #expect(state.activationCount >= 1)
    }

    @Test("Ignores AX frontmost when workspace frontmost conflicts")
    func ignoresAXFrontmostWhenWorkspaceFrontmostConflicts() {
        let state = ActivationState(frontmostPid: 123, focusedPid: nil)

        let success = OXAExecutor.ensureApplicationFrontmost(
            pid: 99,
            timeout: 0.08,
            pollInterval: 0.02,
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            activatePid: { _ in
                state.activationCount += 1
                return false
            },
            frontmostPidProvider: { state.frontmostPid },
            focusedPidProvider: { state.focusedPid },
            axFrontmostProvider: { pid in pid == 99 })

        #expect(success == false)
        #expect(state.activationCount >= 1)
    }

    @Test("Returns false when app never becomes frontmost")
    func returnsFalseWhenNeverFrontmost() {
        let state = ActivationState(frontmostPid: nil, focusedPid: nil)

        let success = OXAExecutor.ensureApplicationFrontmost(
            pid: 77,
            timeout: 0.08,
            pollInterval: 0.02,
            now: { state.now },
            sleep: { seconds in state.now.addTimeInterval(seconds) },
            activatePid: { _ in
                state.activationCount += 1
                return false
            },
            frontmostPidProvider: { state.frontmostPid },
            focusedPidProvider: { state.focusedPid },
            axFrontmostProvider: { _ in false })

        #expect(success == false)
        #expect(state.activationCount >= 1)
    }
}

private final class ActivationState {
    init(frontmostPid: pid_t?, focusedPid: pid_t?) {
        self.frontmostPid = frontmostPid
        self.focusedPid = focusedPid
    }

    var now: Date = .init(timeIntervalSince1970: 1_700_000_000)
    var activationCount = 0
    var frontmostPid: pid_t?
    var focusedPid: pid_t?
}
