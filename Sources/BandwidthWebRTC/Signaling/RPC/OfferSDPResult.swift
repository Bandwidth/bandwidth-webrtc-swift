//
//  OfferSDPResult.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct OfferSDPResult: Decodable {
    let sdpAnswer: String
    let candidates: [Candidate]?
}

struct Candidate: Codable {
    let candidate: String
    let sdpMLineIndex: Int
    let sdpMid: String
}
