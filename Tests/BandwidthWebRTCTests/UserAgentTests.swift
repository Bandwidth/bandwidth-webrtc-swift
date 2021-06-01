//
//  UserAgentTests.swift
//  
//
//  Created by Michael Hamer on 6/1/21.
//

import XCTest
@testable import BandwidthWebRTC

final class UserAgentTests: XCTestCase {
    func testDefaultBuildResult() {
        let packageName = "TestPackageName"
        let version = "0.0.0"

        let userAgent = UserAgent()
        
        XCTAssertEqual(userAgent.build(packageName: packageName), "\(packageName) \(version)")
    }
}
