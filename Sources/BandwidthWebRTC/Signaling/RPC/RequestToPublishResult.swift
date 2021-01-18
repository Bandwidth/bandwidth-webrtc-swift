//
//  RequestToPublishResult.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct RequestToPublishResult: Decodable {
    let endpointId: String
    let mediaTypes: [String]
    let direction: String
}
