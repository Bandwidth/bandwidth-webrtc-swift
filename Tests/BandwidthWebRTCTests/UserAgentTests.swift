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
        let userAgent = UserAgent()
        let packageName = "TestPackageName"
        
        XCTAssertEqual(userAgent.build(packageName: packageName), packageName)
    }
}
