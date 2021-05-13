//
//  OutgoingOfferSDPParams.swift
//  
//
//  Created by Michael Hamer on 5/11/21.
//

import Foundation

struct OutgoingOfferSDPParams: Codable {
    let sdpOffer: String
    let mediaMetadata: PublishMetadata
}
