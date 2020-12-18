//
//  BandwidthRTC.swift
//  
//
//  Created by Michael Hamer on 12/17/20.
//

import Foundation

class BandwidthRTC {
    private var signaling: Signaling?
    
    func connect(token: String, completion: @escaping () -> Void) throws {
        signaling = Signaling()
        signaling?.delegate = self
        
        try signaling?.connect(token: token) {
            completion()
        }
    }
}

extension BandwidthRTC: SignalingDelegate {
    func signaling(_ signaling: Signaling, didReceiveSDPNeeded parameters: SDPNeededParameters) {
        
    }
    
    func signaling(_ signaling: Signaling, didReceiveAddICECandidate parameters: AddICECandidateParameters) {
        
    }
    
    func signaling(_ signaling: Signaling, didReceiveEndpointRemoved parameters: EndpointRemovedParameters) {
        
    }
}
