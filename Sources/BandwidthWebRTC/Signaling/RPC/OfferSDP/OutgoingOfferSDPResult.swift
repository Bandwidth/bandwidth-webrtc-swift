//
//  OutgoingOfferSDPResult.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct OutgoingOfferSDPResult: Decodable {
    let endpointId: String
    let sdpAnswer: String
    let streamMetadata: [String: StreamMetadata]
}
