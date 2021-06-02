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
        let version = "7.7.7"
        
        let userAgent = UserAgent(from: Bundle.module.url(forResource: "Settings", withExtension: "plist"))
        
        XCTAssertEqual(userAgent.build(packageName: packageName), "\(packageName) \(version)")
    }
}
