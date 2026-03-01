import AppKit
import AXorcist
import ApplicationServices
import Darwin
import Foundation

enum SelectorQueryCLIError: LocalizedError, Equatable {
    case missingApplication
    case missingSelector
    case conflictingInputModes
    case invalidMaxDepth(Int)
    case invalidLimit(Int)
    case applicationNotFound(String)
    case cachedSnapshotUnavailable(String)
    case referenceCollision(String)

    var errorDescription: String? {
        switch self {
        case .missingApplication:
            "Selector mode requires --app."
        case .missingSelector:
            "Selector mode requires --selector."
        case .conflictingInputModes:
            "Selector mode (--app/--selector) cannot be combined with JSON input flags or payloads."
        case let .invalidMaxDepth(value):
            "--max-depth must be greater than 0. Received: \(value)."
        case let .invalidLimit(value):
            "--limit must be 0 or greater. Use 0 for no cap. Received: \(value)."
        case let .applicationNotFound(identifier):
            "Could not find a running app for '\(identifier)'. Use a bundle id (e.g. com.apple.TextEdit), running app name, PID, or 'focused'."
        case let .cachedSnapshotUnavailable(message):
            message
        case let .referenceCollision(reference):
            "Selector query produced a duplicate element reference '\(reference)'. Re-run query."
        }
    }
}

struct SelectorQueryRequest: Equatable {
    let appIdentifier: String
    let selector: String
    let maxDepth: Int
    let limit: Int
    let colorEnabled: Bool
    let showPath: Bool
    let showNameSource: Bool
    let cacheSessionEnabled: Bool
    let useCachedSnapshot: Bool

    init(
        appIdentifier: String,
        selector: String,
        maxDepth: Int,
        limit: Int,
        colorEnabled: Bool,
        showPath: Bool,
        showNameSource: Bool = false,
        cacheSessionEnabled: Bool = false,
        useCachedSnapshot: Bool = false)
    {
        self.appIdentifier = appIdentifier
        self.selector = selector
        self.maxDepth = maxDepth
        self.limit = limit
        self.colorEnabled = colorEnabled
        self.showPath = showPath
        self.showNameSource = showNameSource
        self.cacheSessionEnabled = cacheSessionEnabled
        self.useCachedSnapshot = useCachedSnapshot
    }
}

enum SelectorQueryRequestBuilder {
    private static let unlimitedMaxDepth = Int.max
    private static let defaultLimit = 50
    private static let unlimitedLimit = Int.max

    static func build(
        app: String?,
        selector: String?,
        maxDepth: Int?,
        limit: Int?,
        noColor: Bool,
        showPath: Bool,
        showNameSource: Bool = false,
        cacheSession: Bool = false,
        useCached: Bool = false,
        hasStructuredInput: Bool,
        stdoutSupportsANSI: Bool) throws -> SelectorQueryRequest?
    {
        let trimmedApp = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasApp = !(trimmedApp?.isEmpty ?? true)
        let hasSelector = !(trimmedSelector?.isEmpty ?? true)

        if !hasApp, !hasSelector {
            return nil
        }

        if hasStructuredInput {
            throw SelectorQueryCLIError.conflictingInputModes
        }

        guard hasApp else { throw SelectorQueryCLIError.missingApplication }
        guard hasSelector else { throw SelectorQueryCLIError.missingSelector }

        if let maxDepth, maxDepth <= 0 {
            throw SelectorQueryCLIError.invalidMaxDepth(maxDepth)
        }

        if let limit, limit < 0 {
            throw SelectorQueryCLIError.invalidLimit(limit)
        }

        let resolvedLimit: Int
        if let limit {
            resolvedLimit = (limit == 0) ? unlimitedLimit : limit
        } else {
            resolvedLimit = defaultLimit
        }

        return SelectorQueryRequest(
            appIdentifier: trimmedApp!,
            selector: trimmedSelector!,
            maxDepth: maxDepth ?? unlimitedMaxDepth,
            limit: resolvedLimit,
            colorEnabled: stdoutSupportsANSI && !noColor,
            showPath: showPath,
            showNameSource: showNameSource,
            cacheSessionEnabled: cacheSession || useCached,
            useCachedSnapshot: useCached)
    }
}

struct SelectorQueryExecutionReport: Equatable {
    let request: SelectorQueryRequest
    let elapsedMilliseconds: Double
    let traversedCount: Int
    let matchedCount: Int
    let shownCount: Int
    let results: [SelectorMatchSummary]

    init(
        request: SelectorQueryRequest,
        elapsedMilliseconds: Double,
        traversedCount: Int,
        matchedCount: Int,
        shownCount: Int,
        results: [SelectorMatchSummary])
    {
        self.request = request
        self.elapsedMilliseconds = elapsedMilliseconds
        self.traversedCount = traversedCount
        self.matchedCount = matchedCount
        self.shownCount = shownCount
        self.results = results
    }
}

struct SelectorQueryResult: Equatable {
    let traversedCount: Int
    let matchedCount: Int
    let shown: [SelectorMatchSummary]

    init(
        traversedCount: Int,
        matchedCount: Int,
        shown: [SelectorMatchSummary])
    {
        self.traversedCount = traversedCount
        self.matchedCount = matchedCount
        self.shown = shown
    }
}

struct SelectorMatchSummary: Equatable {
    let role: String
    let computedName: String?
    let computedNameSource: String?
    let isEnabled: Bool?
    let isFocused: Bool?
    let childCount: Int?
    let title: String?
    let value: String?
    let identifier: String?
    let descriptionText: String?
    let path: String?
    let reference: String?

    var resultDisplayName: String? {
        if self.role == AXRoleNames.kAXStaticTextRole, let value = self.value {
            return value
        }
        return self.computedName
    }

    var resultDisplayNameSource: String? {
        if self.role == AXRoleNames.kAXStaticTextRole, let value = self.value {
            if value != self.computedName {
                return AXAttributeNames.kAXValueAttribute
            }
        }
        return self.computedNameSource
    }

    var resultDisplayValue: String? {
        guard let value = self.value else { return nil }
        guard value != self.resultDisplayName else { return nil }
        return value
    }

    init(
        role: String,
        computedName: String?,
        computedNameSource: String? = nil,
        isEnabled: Bool? = nil,
        isFocused: Bool? = nil,
        childCount: Int? = nil,
        title: String?,
        value: String?,
        identifier: String?,
        descriptionText: String?,
        path: String?,
        reference: String? = nil)
    {
        self.role = role
        self.computedName = computedName
        self.computedNameSource = computedNameSource
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.childCount = childCount
        self.title = title
        self.value = value
        self.identifier = identifier
        self.descriptionText = descriptionText
        self.path = path
        self.reference = reference
    }

    @MainActor
    init(
        element: Element,
        includePath: Bool,
        isEnabled: Bool?,
        isFocused: Bool?,
        childCount: Int?)
    {
        let computedNameDetails = element.computedNameDetails()
        self.role = element.role() ?? "AXUnknown"
        self.computedName = SelectorMatchSummary.normalize(computedNameDetails?.value)
        self.computedNameSource = SelectorMatchSummary.normalize(computedNameDetails?.source)
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.childCount = childCount
        self.title = SelectorMatchSummary.normalize(element.title())
        self.value = SelectorMatchSummary.normalize(SelectorMatchSummary.preferredValueString(for: element))
        self.identifier = SelectorMatchSummary.normalize(element.identifier())
        self.descriptionText = SelectorMatchSummary.normalize(element.descriptionText())
        self.path = includePath ? SelectorMatchSummary.normalize(element.generatePathString()) : nil
        self.reference = nil
    }

    static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if self.isNullLikeString(trimmed) {
            return nil
        }
        return trimmed
    }

    static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        guard let unwrappedValue = self.unwrapOptional(value) else { return nil }

        if unwrappedValue is NSNull {
            return nil
        }
        if let string = unwrappedValue as? String {
            if self.isNullLikeString(string) {
                return nil
            }
            return string
        }
        if let attributed = unwrappedValue as? NSAttributedString {
            return attributed.string
        }
        if let number = unwrappedValue as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let bool = unwrappedValue as? Bool {
            return bool ? "true" : "false"
        }
        if let strings = unwrappedValue as? [String] {
            return strings.joined(separator: ",")
        }
        if let array = unwrappedValue as? [Any] {
            let parts = array.compactMap { stringify($0) }
            return parts.isEmpty ? nil : parts.joined(separator: ",")
        }

        let described = String(describing: unwrappedValue)
        if self.isNullLikeString(described) {
            return nil
        }
        return described
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }
        guard let wrapped = mirror.children.first?.value else {
            return nil
        }
        return self.unwrapOptional(wrapped)
    }

    private static func isNullLikeString(_ value: String) -> Bool {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token == "nil" ||
            token == "null" ||
            token == "(null)" ||
            token == "<null>" ||
            token == "optional(nil)"
    }

    @MainActor
    private static func preferredValueString(for element: Element) -> String? {
        if let directValue: String = element.attribute(Attribute<String>(AXAttributeNames.kAXValueAttribute)) {
            return directValue
        }

        if let normalizedValue = self.stringify(element.value()) {
            return normalizedValue
        }

        if let selectedText = element.selectedText() {
            return selectedText
        }

        return nil
    }
}

@MainActor
struct SelectorQueryRunner {
    typealias QueryExecutor = @MainActor (SelectorQueryRequest) throws -> SelectorQueryResult
    typealias NanosecondClock = @MainActor () -> UInt64

    init(
        queryExecutor: @escaping QueryExecutor = LiveSelectorQueryExecutor.execute,
        nowNanoseconds: @escaping NanosecondClock = defaultNowNanoseconds)
    {
        self.queryExecutor = queryExecutor
        self.nowNanoseconds = nowNanoseconds
    }

    func execute(_ request: SelectorQueryRequest) throws -> SelectorQueryExecutionReport {
        let startedAt = self.nowNanoseconds()
        let result = try self.queryExecutor(request)
        let endedAt = self.nowNanoseconds()

        let elapsedMilliseconds = Double(endedAt &- startedAt) / 1_000_000

        return SelectorQueryExecutionReport(
            request: request,
            elapsedMilliseconds: elapsedMilliseconds,
            traversedCount: result.traversedCount,
            matchedCount: result.matchedCount,
            shownCount: result.shown.count,
            results: result.shown)
    }

    private let queryExecutor: QueryExecutor
    private let nowNanoseconds: NanosecondClock

    private static func defaultNowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

@MainActor
private enum LiveSelectorQueryExecutor {
    private struct SelectorPrefetchSnapshot {
        let childrenByElement: [Element: [Element]]
        let parentByElement: [Element: Element]
        let roleByElement: [Element: String]
        let attributeValuesByElement: [Element: [String: String]]
        let prefetchedAttributeNames: Set<String>
        let elementsByReference: [String: Element]
    }

    private struct SelectorPrefetchCacheEntry {
        let appPID: pid_t
        let maxDepth: Int
        let prefetchedAttributeNames: Set<String>
        let snapshot: SelectorPrefetchSnapshot
    }

    private static let cacheReferenceAttributeName = "__axorc_ref"
    private static var prefetchCache: SelectorPrefetchCacheEntry?

    static func execute(_ request: SelectorQueryRequest) throws -> SelectorQueryResult
    {
        guard let root = self.resolveRootElement(appIdentifier: request.appIdentifier) else {
            throw SelectorQueryCLIError.applicationNotFound(request.appIdentifier)
        }

        let syntaxTree = try OXQParser().parse(request.selector)
        let prefetchedAttributeNames = self.prefetchAttributeNames(for: syntaxTree)
        let rootPID = self.axPid(for: root) ?? 0
        let prefetchedSnapshot = try self.resolvePrefetchedSnapshot(
            root: root,
            rootPID: rootPID,
            maxDepth: request.maxDepth,
            requiredAttributeNames: prefetchedAttributeNames,
            cacheSessionEnabled: request.cacheSessionEnabled,
            useCachedSnapshot: request.useCachedSnapshot)

        let childrenProvider: (Element) -> [Element] = { element in
            prefetchedSnapshot.childrenByElement[element] ?? []
        }
        let roleProvider: (Element) -> String? = { element in
            prefetchedSnapshot.roleByElement[element] ??
                self.stringValue(for: element, attributeName: AXAttributeNames.kAXRoleAttribute)
        }
        let attributeValueProvider: (Element, String) -> String? = { element, attributeName in
            let canonicalName = self.canonicalAttributeName(attributeName)
            if let prefetched = prefetchedSnapshot.attributeValuesByElement[element]?[canonicalName] {
                return prefetched
            }
            if prefetchedSnapshot.prefetchedAttributeNames.contains(canonicalName) {
                return nil
            }
            return self.stringValue(for: element, attributeName: canonicalName)
        }

        let selectorEngine = OXQSelectorEngine<Element>(
            children: childrenProvider,
            role: roleProvider,
            attributeValue: attributeValueProvider)

        let memoizationContext = OXQQueryMemoizationContext<Element>(
            childrenProvider: childrenProvider,
            roleProvider: roleProvider,
            attributeValueProvider: attributeValueProvider,
            preferDerivedComputedName: true)

        let evaluation = selectorEngine.findAllWithMetrics(
            matching: syntaxTree,
            from: root,
            maxDepth: request.maxDepth,
            memoizationContext: memoizationContext)
        let matchedElements = evaluation.matches

        let actionElementsByReference = prefetchedSnapshot.elementsByReference
        let shownElements = Array(matchedElements.prefix(request.limit))
        let shownSummaries = try shownElements.map { element in
            guard let reference = self.referenceForElement(element, snapshot: prefetchedSnapshot) else {
                throw SelectorQueryCLIError.cachedSnapshotUnavailable(
                    "Cached snapshot reference map is missing an element. Refresh with --cache-session.")
            }

            let isEnabled = self.parseBool(memoizationContext.attributeValue(
                of: element,
                attributeName: AXAttributeNames.kAXEnabledAttribute))
            let isFocused = self.parseBool(memoizationContext.attributeValue(
                of: element,
                attributeName: AXAttributeNames.kAXFocusedAttribute))
            let childCount = memoizationContext.children(of: element).count
            let computedNameDetails = memoizationContext.computedNameDetails(of: element)
            let roleName = memoizationContext.role(of: element) ?? "AXUnknown"
            let value = memoizationContext.attributeValue(of: element, attributeName: AXAttributeNames.kAXValueAttribute) ??
                memoizationContext.attributeValue(of: element, attributeName: AXAttributeNames.kAXSelectedTextAttribute)

            return SelectorMatchSummary(
                role: roleName,
                computedName: SelectorMatchSummary.normalize(computedNameDetails?.value),
                computedNameSource: SelectorMatchSummary.normalize(computedNameDetails?.source),
                isEnabled: isEnabled,
                isFocused: isFocused,
                childCount: childCount,
                title: SelectorMatchSummary.normalize(
                    memoizationContext.attributeValue(of: element, attributeName: AXAttributeNames.kAXTitleAttribute)),
                value: SelectorMatchSummary.normalize(value),
                identifier: SelectorMatchSummary.normalize(
                    memoizationContext.attributeValue(of: element, attributeName: AXAttributeNames.kAXIdentifierAttribute)),
                descriptionText: SelectorMatchSummary.normalize(
                    memoizationContext.attributeValue(of: element, attributeName: AXAttributeNames.kAXDescriptionAttribute)),
                path: request.showPath
                    ? SelectorMatchSummary.normalize(self.cachedPathString(for: element, snapshot: prefetchedSnapshot))
                    : nil,
                reference: reference)
        }
        SelectorActionRefStore.replace(
            with: actionElementsByReference,
            appPID: rootPID > 0 ? rootPID : nil)

        return SelectorQueryResult(
            traversedCount: evaluation.traversedNodeCount,
            matchedCount: matchedElements.count,
            shown: shownSummaries)
    }

    private static func resolvePrefetchedSnapshot(
        root: Element,
        rootPID: pid_t,
        maxDepth: Int,
        requiredAttributeNames: Set<String>,
        cacheSessionEnabled: Bool,
        useCachedSnapshot: Bool) throws -> SelectorPrefetchSnapshot
    {
        guard cacheSessionEnabled else {
            self.prefetchCache = nil
            return self.prefetchSnapshot(
                root: root,
                maxDepth: maxDepth,
                attributeNames: requiredAttributeNames)
        }

        if useCachedSnapshot {
            guard let cached = self.prefetchCache else {
                throw SelectorQueryCLIError.cachedSnapshotUnavailable(
                    "No warm cached snapshot available. Run the query once with --cache-session first.")
            }
            guard cached.appPID == rootPID else {
                throw SelectorQueryCLIError.cachedSnapshotUnavailable(
                    "Cached snapshot belongs to another app process. Refresh with --cache-session.")
            }
            guard cached.maxDepth >= maxDepth else {
                throw SelectorQueryCLIError.cachedSnapshotUnavailable(
                    "Cached snapshot depth (\(cached.maxDepth)) is shallower than requested depth (\(maxDepth)). Refresh with --cache-session.")
            }
            guard cached.prefetchedAttributeNames.isSuperset(of: requiredAttributeNames) else {
                throw SelectorQueryCLIError.cachedSnapshotUnavailable(
                    "Cached snapshot is missing attributes required by this selector. Refresh with --cache-session.")
            }
            return cached.snapshot
        }

        let snapshot = self.prefetchSnapshot(
            root: root,
            maxDepth: maxDepth,
            attributeNames: requiredAttributeNames)

        self.prefetchCache = SelectorPrefetchCacheEntry(
            appPID: rootPID,
            maxDepth: maxDepth,
            prefetchedAttributeNames: requiredAttributeNames,
            snapshot: snapshot)

        return snapshot
    }

    private static func resolveRootElement(appIdentifier: String) -> Element? {
        let normalizedIdentifier = appIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedIdentifier.caseInsensitiveCompare("focused") == .orderedSame,
           let frontmost = RunningApplicationHelper.frontmostApplication
        {
            return getApplicationElement(for: frontmost.processIdentifier)
        }

        if let pid = pid_t(normalizedIdentifier) {
            return getApplicationElement(for: pid)
        }

        if let directBundleMatch = getApplicationElement(for: normalizedIdentifier) {
            return directBundleMatch
        }

        guard let app = self.findRunningApplication(matching: normalizedIdentifier) else {
            return nil
        }

        return getApplicationElement(for: app.processIdentifier)
    }

    private static func axPid(for element: Element) -> pid_t? {
        if let pid = element.pid(), pid > 0 {
            return pid
        }

        var pid: pid_t = 0
        let status = AXUIElementGetPid(element.underlyingElement, &pid)
        guard status == .success, pid > 0 else {
            return nil
        }
        return pid
    }

    private static func findRunningApplication(matching identifier: String) -> NSRunningApplication? {
        let normalized = identifier.lowercased()

        return RunningApplicationHelper.allApplications().first { app in
            let bundleMatch = app.bundleIdentifier?.lowercased() == normalized
            let nameMatch = app.localizedName?.lowercased() == normalized
            return bundleMatch || nameMatch
        }
    }

    private static func stringValue(for element: Element, attributeName: String) -> String? {
        let canonicalName = self.canonicalAttributeName(attributeName)

        switch canonicalName {
        case AXAttributeNames.kAXRoleAttribute:
            return element.role()
        case AXAttributeNames.kAXSubroleAttribute:
            return element.subrole()
        case AXAttributeNames.kAXPIDAttribute:
            return element.pid().map(String.init)
        case AXAttributeNames.kAXTitleAttribute:
            return element.title()
        case AXAttributeNames.kAXDescriptionAttribute:
            return element.descriptionText()
        case AXAttributeNames.kAXHelpAttribute:
            return element.help()
        case AXAttributeNames.kAXIdentifierAttribute:
            return element.identifier()
        case AXAttributeNames.kAXRoleDescriptionAttribute:
            return element.roleDescription()
        case AXAttributeNames.kAXPlaceholderValueAttribute:
            return element.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute))
        case AXAttributeNames.kAXEnabledAttribute:
            return element.isEnabled().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXFocusedAttribute:
            return element.isFocused().map { $0 ? "true" : "false" }
        case AXAttributeNames.kAXValueAttribute:
            return SelectorMatchSummary.stringify(element.value())
        case AXMiscConstants.computedNameAttributeKey:
            return element.computedName()
        case AXMiscConstants.isIgnoredAttributeKey:
            return element.isIgnored() ? "true" : "false"
        default:
            break
        }

        guard let rawValue: Any = element.attribute(Attribute<Any>(canonicalName)) else {
            return nil
        }
        return SelectorMatchSummary.stringify(rawValue)
    }

    private static func canonicalAttributeName(_ name: String) -> String {
        PathUtils.attributeKeyMappings[name.lowercased()] ?? name
    }

    private static func prefetchAttributeNames(for syntaxTree: OXQSyntaxTree) -> Set<String> {
        var names: Set<String> = [
            AXAttributeNames.kAXRoleAttribute,
            AXAttributeNames.kAXTitleAttribute,
            AXAttributeNames.kAXValueAttribute,
            AXAttributeNames.kAXIdentifierAttribute,
            AXAttributeNames.kAXDescriptionAttribute,
            AXAttributeNames.kAXHelpAttribute,
            AXAttributeNames.kAXPlaceholderValueAttribute,
            AXAttributeNames.kAXSelectedTextAttribute,
            AXAttributeNames.kAXEnabledAttribute,
            AXAttributeNames.kAXFocusedAttribute,
            AXAttributeNames.kAXSubroleAttribute,
            AXAttributeNames.kAXPIDAttribute,
            AXAttributeNames.kAXRoleDescriptionAttribute,
        ]

        for selector in syntaxTree.selectors {
            self.collectAttributeNames(in: selector, into: &names)
        }

        return names
    }

    private static func collectAttributeNames(in selector: OXQSelector, into names: inout Set<String>) {
        self.collectAttributeNames(in: selector.leading, into: &names)
        for link in selector.links {
            self.collectAttributeNames(in: link.compound, into: &names)
        }
    }

    private static func collectAttributeNames(in compound: OXQCompound, into names: inout Set<String>) {
        for attribute in compound.attributes {
            self.collectAttributeName(attribute.name, into: &names)
        }

        for pseudo in compound.pseudos {
            switch pseudo {
            case let .not(selectors):
                for selector in selectors {
                    self.collectAttributeNames(in: selector, into: &names)
                }
            case let .has(argument):
                switch argument {
                case let .selectors(selectors):
                    for selector in selectors {
                        self.collectAttributeNames(in: selector, into: &names)
                    }
                case let .relativeSelectors(relativeSelectors):
                    for relativeSelector in relativeSelectors {
                        self.collectAttributeNames(in: relativeSelector.selector, into: &names)
                    }
                }
            }
        }
    }

    private static func collectAttributeName(_ rawName: String, into names: inout Set<String>) {
        let canonicalName = self.canonicalAttributeName(rawName)
        if canonicalName == AXMiscConstants.computedNameAttributeKey {
            names.formUnion([
                AXAttributeNames.kAXRoleAttribute,
                AXAttributeNames.kAXTitleAttribute,
                AXAttributeNames.kAXValueAttribute,
                AXAttributeNames.kAXIdentifierAttribute,
                AXAttributeNames.kAXDescriptionAttribute,
                AXAttributeNames.kAXHelpAttribute,
                AXAttributeNames.kAXPlaceholderValueAttribute,
                AXAttributeNames.kAXSelectedTextAttribute,
            ])
            return
        }

        if canonicalName == AXMiscConstants.isIgnoredAttributeKey {
            return
        }

        names.insert(canonicalName)
    }

    private static func prefetchSnapshot(
        root: Element,
        maxDepth: Int,
        attributeNames: Set<String>) -> SelectorPrefetchSnapshot
    {
        let safeMaxDepth = max(0, maxDepth)
        let orderedAttributeNames = Array(attributeNames).sorted()

        var childrenByElement: [Element: [Element]] = [:]
        var parentByElement: [Element: Element] = [:]
        var roleByElement: [Element: String] = [:]
        var attributeValuesByElement: [Element: [String: String]] = [:]
        var bestDepthByElement: [Element: Int] = [:]
        var elementsByReference: [String: Element] = [:]
        var generatedReferences: Set<String> = []
        var stack: [(element: Element, depth: Int, parent: Element?)] = [(root, 0, nil)]

        while let entry = stack.popLast() {
            let element = entry.element
            let depth = entry.depth
            let reference = self.ensureSnapshotReference(
                for: element,
                attributeValuesByElement: &attributeValuesByElement,
                elementsByReference: &elementsByReference,
                generatedReferences: &generatedReferences)

            if let parent = entry.parent {
                parentByElement[element] = parent
            }

            if let bestDepth = bestDepthByElement[element], depth >= bestDepth {
                continue
            }

            bestDepthByElement[element] = depth

            let prefetchedAttributes = self.batchFetchAttributeValues(
                for: element,
                attributeNames: orderedAttributeNames)
            var attributes = attributeValuesByElement[element] ?? [:]
            if !prefetchedAttributes.isEmpty {
                attributes.merge(prefetchedAttributes) { _, new in new }
            }
            attributes[self.cacheReferenceAttributeName] = reference
            attributeValuesByElement[element] = attributes

            if let role = prefetchedAttributes[AXAttributeNames.kAXRoleAttribute] ??
                self.stringValue(for: element, attributeName: AXAttributeNames.kAXRoleAttribute)
            {
                roleByElement[element] = role
                var attributes = attributeValuesByElement[element] ?? [:]
                attributes[AXAttributeNames.kAXRoleAttribute] = role
                attributeValuesByElement[element] = attributes
            }

            let children: [Element]
            if depth < safeMaxDepth {
                children = element.children(strict: false, includeApplicationExtras: element == root) ?? []
            } else {
                children = []
            }
            childrenByElement[element] = children

            for child in children.reversed() {
                stack.append((child, depth + 1, element))
            }
        }

        return SelectorPrefetchSnapshot(
            childrenByElement: childrenByElement,
            parentByElement: parentByElement,
            roleByElement: roleByElement,
            attributeValuesByElement: attributeValuesByElement,
            prefetchedAttributeNames: attributeNames,
            elementsByReference: elementsByReference)
    }

    private static func batchFetchAttributeValues(
        for element: Element,
        attributeNames: [String]) -> [String: String]
    {
        guard !attributeNames.isEmpty else { return [:] }

        let cfAttributeNames = attributeNames.map { $0 as CFString } as CFArray
        var values: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            element.underlyingElement,
            cfAttributeNames,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values)

        guard status == .success, let rawValues = values as? [Any] else {
            var fallbackValues: [String: String] = [:]
            for name in attributeNames {
                if let value = self.stringValue(for: element, attributeName: name) {
                    fallbackValues[name] = value
                }
            }
            return fallbackValues
        }

        var result: [String: String] = [:]
        let pairCount = min(attributeNames.count, rawValues.count)

        for index in 0..<pairCount {
            let name = attributeNames[index]
            if let value = self.stringifyBatchAttributeValue(rawValues[index]) {
                result[name] = value
            }
        }

        if rawValues.count < attributeNames.count {
            for name in attributeNames[rawValues.count...] {
                if let value = self.stringValue(for: element, attributeName: name) {
                    result[name] = value
                }
            }
        }

        return result
    }

    private static func stringifyBatchAttributeValue(_ value: Any) -> String? {
        if value is NSNull {
            return nil
        }

        let object = value as AnyObject
        let typeRef = object as CFTypeRef
        if CFGetTypeID(typeRef) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(object, to: AXValue.self)
            if AXValueGetType(axValue) == .axError {
                return nil
            }
        }

        return SelectorMatchSummary.stringify(value)
    }

    private static func cachedPathString(for element: Element, snapshot: SelectorPrefetchSnapshot) -> String {
        var chain: [Element] = []
        var visited = Set<Element>()
        var current: Element? = element

        while let node = current, visited.insert(node).inserted {
            chain.append(node)
            current = snapshot.parentByElement[node]
        }

        return chain.reversed().map { node in
            var parts: [String] = []
            let role = snapshot.roleByElement[node] ??
                snapshot.attributeValuesByElement[node]?[AXAttributeNames.kAXRoleAttribute] ??
                "AXUnknown"
            parts.append("Role: \(role)")

            if let title = snapshot.attributeValuesByElement[node]?[AXAttributeNames.kAXTitleAttribute], !title.isEmpty {
                parts.append("Title: '\(title)'")
            }
            if let identifier = snapshot.attributeValuesByElement[node]?[AXAttributeNames.kAXIdentifierAttribute],
               !identifier.isEmpty
            {
                parts.append("ID: '\(identifier)'")
            }

            return parts.joined(separator: ", ")
        }.joined(separator: " -> ")
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }

    static func invalidateCacheSessionState() {
        self.prefetchCache = nil
    }

    private static func referenceForElement(_ element: Element, snapshot: SelectorPrefetchSnapshot) -> String? {
        snapshot.attributeValuesByElement[element]?[self.cacheReferenceAttributeName]
    }

    private static func generateUniqueReference(existing: inout Set<String>) -> String {
        while true {
            let raw = UInt64.random(in: 0..<(1 << 36))
            let candidate = String(format: "%09llx", raw)
            if existing.insert(candidate).inserted {
                return candidate
            }
        }
    }

    private static func ensureSnapshotReference(
        for element: Element,
        attributeValuesByElement: inout [Element: [String: String]],
        elementsByReference: inout [String: Element],
        generatedReferences: inout Set<String>) -> String
    {
        var attributes = attributeValuesByElement[element] ?? [:]
        if let existing = attributes[self.cacheReferenceAttributeName] {
            elementsByReference[existing] = element
            return existing
        }

        let reference = self.generateUniqueReference(existing: &generatedReferences)
        attributes[self.cacheReferenceAttributeName] = reference
        attributeValuesByElement[element] = attributes
        elementsByReference[reference] = element
        return reference
    }
}

@MainActor
func selectorQueryInvalidateCaches() {
    LiveSelectorQueryExecutor.invalidateCacheSessionState()
    SelectorActionRefStore.clear()
}

enum OutputCapabilities {
    static var stdoutSupportsANSI: Bool {
        guard isatty(STDOUT_FILENO) == 1 else { return false }
        let term = ProcessInfo.processInfo.environment["TERM"]?.lowercased()
        return term != "dumb"
    }
}
