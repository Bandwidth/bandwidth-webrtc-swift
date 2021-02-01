//
//  Connection.swift
//
//
//  Created by Michael Hamer on 1/8/20.
//

import Foundation
import WebRTC

class Connection {
    let peerConnection: RTCPeerConnection
    let endpointId: String
    let participantId: String
    let mediaTypes: [MediaType]
    let alias: String?
    
    init(peerConnection: RTCPeerConnection, endpointId: String, participantId: String, mediaTypes: [MediaType], alias: String?) {
        self.peerConnection = peerConnection
        self.endpointId = endpointId
        self.participantId = participantId
        self.mediaTypes = mediaTypes
        self.alias = alias
    }
}
