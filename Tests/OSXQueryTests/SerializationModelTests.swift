import CoreGraphics
import Foundation
import Testing
@testable import OSXQuery

@Suite("Serialization and Model Contracts")
struct SerializationModelTests {
    @Test("AnyCodable encodes and decodes primitive values")
    func anyCodablePrimitiveRoundTrips() throws {
        let values: [AnyCodable] = [
            AnyCodable(true),
            AnyCodable(42),
            AnyCodable(2.5),
            AnyCodable("hello"),
            AnyCodable(nil as String?),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test("AnyCodable round trips arrays and dictionaries")
    func anyCodableCollectionRoundTrips() throws {
        let original = AnyCodable([
            "list": [1, "two", true] as [Any],
            "nested": [
                "flag": false,
                "value": 3.14,
            ] as [String: Any],
        ] as [String: Any])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        #expect(decoded == original)
    }

    @Test("AnyCodable encodes custom Encodable payloads")
    func anyCodableEncodesCustomEncodable() throws {
        struct Payload: Codable, Equatable {
            let id: Int
            let name: String
        }

        let wrapped = AnyCodable(Payload(id: 7, name: "widget"))
        let data = try JSONEncoder().encode(wrapped)
        let decoded = try JSONDecoder().decode(Payload.self, from: data)

        #expect(decoded == Payload(id: 7, name: "widget"))
    }

    @Test("AttributeValue exposes typed accessors and anyValue")
    func attributeValueTypedAccessors() {
        let dictionary = AttributeValue.dictionary([
            "name": .string("Button"),
            "enabled": .bool(true),
            "children": .array([.int(1), .double(2.5)]),
        ])

        #expect(AttributeValue.string("hello").stringValue == "hello")
        #expect(AttributeValue.bool(true).boolValue == true)
        #expect(AttributeValue.int(8).intValue == 8)
        #expect(AttributeValue.double(4.5).doubleValue == 4.5)
        #expect(AttributeValue.null.isNull)
        #expect(dictionary.dictionaryValue?["name"]?.stringValue == "Button")

        let anyValue = dictionary.anyValue as? [String: Any]
        #expect(anyValue?["name"] as? String == "Button")
        #expect(anyValue?["enabled"] as? Bool == true)
    }

    @Test("AttributeValue converts Foundation values")
    func attributeValueFromAny() {
        let integralNumber = NSNumber(value: 9)
        let fractionalNumber = NSNumber(value: 1.25)
        let boolNumber = kCFBooleanTrue
        let nullValue = NSNull()

        #expect(AttributeValue(from: integralNumber) == .int(9))
        #expect(AttributeValue(from: fractionalNumber) == .double(1.25))
        #expect(AttributeValue(from: boolNumber) == .bool(true))
        #expect(AttributeValue(from: nullValue) == .null)
        #expect(AttributeValue(from: ["a": 1, "b": "two"]) == .dictionary([
            "a": .int(1),
            "b": .string("two"),
        ]))
    }

    @Test("Criterion and PathStep encode optional match metadata")
    func criterionAndPathStepCoding() throws {
        let step = PathStep(
            criteria: [Criterion(attribute: "AXRole", value: "AXButton", matchType: .contains)],
            matchType: .contains,
            matchAllCriteria: false,
            maxDepthForStep: 4)

        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(PathStep.self, from: data)

        #expect(decoded.criteria.count == 1)
        #expect(decoded.criteria[0].matchType == .contains)
        #expect(decoded.matchType == .contains)
        #expect(decoded.matchAllCriteria == false)
        #expect(decoded.maxDepthForStep == 4)
        #expect(decoded.descriptionForLog().contains("Depth: 4"))
    }

    @Test("Locator maps path_from_root when decoding")
    func locatorCodingUsesPathFromRoot() throws {
        let json = """
        {
          "matchAll": false,
          "criteria": [{"attribute":"AXTitle","value":"Save"}],
          "selector": "AXButton",
          "path_from_root": [{"attribute":"role","value":"AXWindow","depth":2,"matchType":"exact"}],
          "descendantCriteria": {"AXRole":"AXButton"},
          "requireAction": "AXPress",
          "computedNameContains": "Save",
          "debugPathSearch": true
        }
        """.data(using: .utf8)!

        let locator = try JSONDecoder().decode(Locator.self, from: json)

        #expect(locator.matchAll == false)
        #expect(locator.criteria.count == 1)
        #expect(locator.selector == "AXButton")
        #expect(locator.rootElementPathHint?.count == 1)
        #expect(locator.rootElementPathHint?.first?.depth == 2)
        #expect(locator.descendantCriteria?["AXRole"] == "AXButton")
        #expect(locator.requireAction == "AXPress")
        #expect(locator.computedNameContains == "Save")
        #expect(locator.debugPathSearch == true)
    }

    @Test("JSONPathHintComponent resolves attribute aliases")
    func jsonPathHintComponentMapsAttributeNames() {
        let role = JSONPathHintComponent(attribute: "role", value: "AXWindow")
        let dom = JSONPathHintComponent(attribute: "DOMCLASS", value: "primary")
        let unknown = JSONPathHintComponent(attribute: "unknown", value: "value")

        #expect(role.axAttributeName == AXAttributeNames.kAXRoleAttribute)
        #expect(role.simpleCriteria?[AXAttributeNames.kAXRoleAttribute] == "AXWindow")
        #expect(dom.axAttributeName == AXAttributeNames.kAXDOMClassListAttribute)
        #expect(dom.descriptionForLog() == "\(AXAttributeNames.kAXDOMClassListAttribute):primary")
        #expect(unknown.axAttributeName == nil)
        #expect(unknown.simpleCriteria == nil)
    }

}
