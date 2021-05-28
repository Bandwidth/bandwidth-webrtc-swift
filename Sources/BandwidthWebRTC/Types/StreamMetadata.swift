//
//  StreamMetadata.swift
//  
//
//  Created by Michael Hamer on 5/10/21.
//

import Foundation

struct StreamMetadata: Codable {
    let endpointId: String
    let mediaTypes: [MediaType]
    let alias: String?
    let participantId: String
}
