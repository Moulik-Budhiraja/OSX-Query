import AppKit
import ApplicationServices
import Foundation

@MainActor
public func getApplicationElement(for bundleIdentifier: String) -> Element? {
    let normalizedIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

    let runningApp =
        NSRunningApplication.runningApplications(withBundleIdentifier: normalizedIdentifier)
            .first(where: { !$0.isTerminated }) ??
        NSWorkspace.shared.runningApplications.first(where: {
            guard let candidate = $0.bundleIdentifier else { return false }
            return candidate.caseInsensitiveCompare(normalizedIdentifier) == .orderedSame && !$0.isTerminated
        })

    guard let runningApp else {
        return nil
    }

    return Element(AXUIElementCreateApplication(runningApp.processIdentifier))
}

@MainActor
public func getApplicationElement(for processId: pid_t) -> Element? {
    Element(AXUIElementCreateApplication(processId))
}
