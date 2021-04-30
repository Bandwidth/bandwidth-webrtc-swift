//
//  UserAgent.swift
//  
//
//  Created by Michael Hamer on 4/30/21.
//

import Foundation
#if os(iOS)
import UIKit
#endif

struct UserAgent {
    private init() {
        
    }
    
    static func build(packageName: String, packageVersion: String) -> String {
        var userAgentComponents = ["\(packageName)/\(packageVersion)"]
        
        #if os(iOS)
        let systemName = UIDevice.current.systemName
        let systemVersion = UIDevice.current.systemVersion
        let model = UIDevice.current.model
        userAgentComponents.append("(\(systemName) \(systemVersion)) \(model)")
        #endif
        
        return userAgentComponents.joined(separator: " ")
    }
}
