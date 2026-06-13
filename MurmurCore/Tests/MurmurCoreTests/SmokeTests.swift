import XCTest
@testable import MurmurCore

final class SmokeTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(MurmurCore.version, "0.1.0")
    }
}
