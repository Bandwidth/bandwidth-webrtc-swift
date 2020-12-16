//
//  AddICECandidateParameters.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct AddICECandidateParameters: Codable {
    let endpointId: String
    let candidate: Candidate
    
    struct Candidate: Codable {
        let candidate: String
        let sdpMLineIndex: Int
        let sdpMid: String
    }
}
