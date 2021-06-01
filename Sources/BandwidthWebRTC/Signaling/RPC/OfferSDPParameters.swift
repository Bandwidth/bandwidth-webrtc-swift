//
//  OfferSDPParameters.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct OfferSDPParameters: Codable {
    let sdpOffer: String
    let mediaMetadata: PublishMetadata
}
