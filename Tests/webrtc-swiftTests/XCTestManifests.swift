import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(webrtc_swiftTests.allTests),
    ]
}
#endif
