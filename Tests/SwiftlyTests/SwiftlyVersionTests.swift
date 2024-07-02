import Foundation
import SwiftlyCore
import XCTest

final class SwiftlyVersionTests: SwiftlyTests {
    func testSanity() throws {
        // GIVEN: a simple valid swiftly version string with major, minor, and patch
        let vs = "0.3.0"
        // WHEN: that version is parsed
        let ver = try! SwiftlyVersion(parsing: vs)
        // THEN: it succeeds and the major, minor, and patch parts match
        XCTAssertEqual(0, ver.major)
        XCTAssertEqual(3, ver.minor)
        XCTAssertEqual(0, ver.patch)
        XCTAssertEqual(nil, ver.suffix)

        // GIVEN: two different swiftly versions
        let vs040 = "0.4.0"
        let ver040 = try! SwiftlyVersion(parsing: vs040)
        // WHEN: the versions are compared
        let cmp = ver040 > ver
        // THEN: the comparison highlights the larger version
        XCTAssertTrue(cmp)
    }

    func testPreRelease() throws {
        // GIVEN: a swiftly version string with major, minor, patch, and suffix (pre-release)
        let preRelease = "0.4.0-dev"
        // WHEN: that version is parsed
        let preVer = try! SwiftlyVersion(parsing: preRelease)
        // THEN: it succeeds and the major, minor, patch, and suffix parts match
        XCTAssertEqual(0, preVer.major)
        XCTAssertEqual(4, preVer.minor)
        XCTAssertEqual(0, preVer.patch)
        XCTAssertEqual("dev", preVer.suffix)

        // GIVEN: a swiftly pre release version and the final release version
        let releaseVer = try! SwiftlyVersion(parsing: "0.4.0")
        // WHEN: the versions are compared
        let cmp = releaseVer > preVer
        // THEN: the released version is consider larger
        XCTAssertTrue(cmp)

        // GIVEN: a swiftly pre release version and the previous release
        let oldReleaseVer = try! SwiftlyVersion(parsing: "0.3.0")
        // WHEN: the versions are compared
        let cmpOldRelease = oldReleaseVer < preVer
        // THEN: the older version is considered smaller than the pre release
        XCTAssertTrue(cmpOldRelease)

        // GIVEN: two pre release versions that are identical except for their suffix
        let preVer2 = try! SwiftlyVersion(parsing: "0.4.0-pre")
        // WHEN: the versions are compared
        let cmpPreVers = preVer2 > preVer
        // THEN: the lexicographically larger one is considered larger
        XCTAssertTrue(cmpPreVers)

        // GIVEN: a pre-release version with dots in it
        let preReleaseDot = "1.5.0-alpha.1"
        // WHEN: that version is parsed
        let preVerDot = try! SwiftlyVersion(parsing: preReleaseDot)
        // THEN: it succeeds and the major, minor, patch, and suffix parts match
        XCTAssertEqual(1, preVerDot.major)
        XCTAssertEqual(5, preVerDot.minor)
        XCTAssertEqual(0, preVerDot.patch)
        XCTAssertEqual("alpha.1", preVerDot.suffix)
    }
}
