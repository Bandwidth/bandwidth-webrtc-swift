//
//  Connection.swift
//
//
//  Created by Michael Hamer on 1/8/20.
//

import Foundation
import WebRTC

class Connection {
    let endpointId: String
    let peerConnection: RTCPeerConnection
    
    init(endpointId: String, peerConnection: RTCPeerConnection) {
        self.endpointId = endpointId
        self.peerConnection = peerConnection
    }
}
