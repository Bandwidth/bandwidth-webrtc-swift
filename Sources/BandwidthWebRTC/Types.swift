//
//  Types.swift
//  
//
//  Created by Michael Hamer on 12/29/20.
//

import Foundation
import WebRTC

struct Candidate: Codable {
    let candidate: String
    let sdpMLineIndex: Int
    let sdpMid: String
}

enum MediaType: String {
    case audio = "AUDIO"
    case video = "VIDEO"
}

struct SDPRequest {
    let endpointId: String
    let mediaTypes: [MediaType]
    let direction: RTCRtpTransceiverDirection
    let alis: String
}
