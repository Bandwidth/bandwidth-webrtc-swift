//
//  RTCStream.swift
//  
//
//  Created by Michael Hamer on 5/28/21.
//

import Foundation
import WebRTC

public struct RTCStream {
    let mediaTypes: [MediaType]
    let mediaStream: RTCMediaStream
    let alias: String?
    let participantId: String?
}
