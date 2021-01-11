//
//  SetMediaPreferencesParameters.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct SetMediaPreferencesParameters: Codable {
    let `protocol`: String
    let aggregationType: String
    let sendReceive: Bool
    
    enum CodingKeys: String, CodingKey {
        case `protocol`
        case aggregationType
        case sendReceive = "sendRecv"
    }
}
