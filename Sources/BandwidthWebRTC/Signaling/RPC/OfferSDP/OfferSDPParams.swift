//
//  OfferSDPParams.swift
//  
//
//  Created by Michael Hamer on 5/11/21.
//

import Foundation

struct OfferSDPParams: Codable {
    let sdpOffer: String
    let mediaMetadata: PublishMetadata
}
