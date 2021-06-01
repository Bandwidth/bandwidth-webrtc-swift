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
    private let settings: Settings?
    
    init(from url: URL? = Bundle.module.url(forResource: "Settings", withExtension: "plist")) {
        if let url = url, let data = try? Data(contentsOf: url) {
            settings = try? PropertyListDecoder().decode(Settings.self, from: data)
        } else {
            settings = nil
        }
    }
    
    func build(packageName: String) -> String {
        var userAgentComponents = [packageName]
        
        if let settings = settings {
            userAgentComponents.append(settings.version)
        }
        
        #if os(iOS)
        let systemName = UIDevice.current.systemName
        userAgentComponents.append(systemName)
        
        let systemVersion = UIDevice.current.systemVersion
        userAgentComponents.append(systemVersion)
        
        let model = UIDevice.current.model
        userAgentComponents.append(model)
        #endif
        
        return userAgentComponents.joined(separator: " ")
    }
}
