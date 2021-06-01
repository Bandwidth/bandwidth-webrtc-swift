//
//  Settings.swift
//  
//
//  Created by Michael Hamer on 6/1/21.
//

import Foundation

struct Settings: Codable {
    let version: String
}

extension Settings {
    enum CodingKeys: String, CodingKey {
        case version = "Version"
    }
}
