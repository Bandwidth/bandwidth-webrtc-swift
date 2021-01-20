//
//  RequestToPublishResult.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct RequestToPublishResult: Decodable {
    let endpointId: String
    let participantId: String
    let mediaTypes: [MediaType]
    let direction: String
}
