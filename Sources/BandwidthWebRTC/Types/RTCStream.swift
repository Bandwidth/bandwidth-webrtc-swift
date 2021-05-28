//
//  RTCStream.swift
//  
//
//  Created by Michael Hamer on 5/28/21.
//

import Foundation
import WebRTC

public struct RTCStream {
    public let mediaTypes: [MediaType]
    public let mediaStream: RTCMediaStream
    public let alias: String?
    public let participantId: String?
}
