//
//  AddICECandidateSendParameters.swift
//  
//
//  Created by Michael Hamer on 1/8/21.
//

import Foundation

struct AddICECandidateSendParameters: Codable {
    let endpointId: String
    let candidate: String
    let sdpMLineIndex: Int
    let sdpMid: String
}
