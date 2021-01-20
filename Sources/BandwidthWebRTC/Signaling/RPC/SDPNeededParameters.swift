//
//  SDPNeededParameters.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct SDPNeededParameters: Codable {
    let alias: String
    let direction: String
    let endpointId: String
    let mediaTypes: [MediaType]
    let participantId: String
//    let streamProperties: Any? // TODO: What should this do?
}
