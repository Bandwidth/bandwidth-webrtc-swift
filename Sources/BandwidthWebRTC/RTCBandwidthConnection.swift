//
//  RTCBandwidthConnection.swift
//
//
//  Created by Michael Hamer on 1/8/20.
//

import Foundation
import WebRTC

public class RTCBandwidthConnection {
    let endpointId: String
    let peerConnection: RTCPeerConnection
    let alias: String?
    let participantId: String?
    
    init(endpointId: String, peerConnection: RTCPeerConnection, alias: String?, participantId: String?) {
        self.endpointId = endpointId
        self.peerConnection = peerConnection
        self.alias = alias
        self.participantId = participantId
    }
}
