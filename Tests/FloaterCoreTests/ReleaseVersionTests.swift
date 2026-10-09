import XCTest
@testable import FloaterCore

final class ReleaseVersionTests: XCTestCase {
    func testReleaseTagsAndBundleVersionsMatch() throws {
        XCTAssertEqual(try XCTUnwrap(ReleaseVersion("v1.2.0")), ReleaseVersion("1.2.0"))
        XCTAssertEqual(try XCTUnwrap(ReleaseVersion("v1.2.0")).description, "1.2.0")
    }

    func testVersionsCompareNumericallyAcrossMinorAndMajorReleases() throws {
        let versions = try ["0.0.0", "1.1.9", "1.2.0", "1.10.0", "2.0.0"].map {
            try XCTUnwrap(ReleaseVersion($0))
        }
        XCTAssertEqual(versions.reversed().sorted(), versions)
        XCTAssertFalse(versions[2] < versions[2])
    }

    func testMalformedAndPrereleaseTagsAreRejected() {
        for value in ["", "v", "1.2", "1.2.0.1", "1..0", "1.2.-1", "01.2.0", "1.+2.0", "1.2.0-beta.1"] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }
}
