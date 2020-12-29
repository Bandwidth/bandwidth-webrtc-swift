//
//  BandwidthRTC.swift
//  
//
//  Created by Michael Hamer on 12/17/20.
//

import Foundation
import WebRTC

public class BandwidthRTC: NSObject {
    private var signaling: Signaling?
    
    private var remotePeerConnections = Dictionary<String, RTCPeerConnection>()
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    func connect(token: String, completion: @escaping () -> Void) throws {
        signaling = Signaling()
        signaling?.delegate = self
        
        try signaling?.connect(token: token) {
            completion()
        }
    }
    
    func publish(mediaTypes: [String], alias: String?, completion: @escaping () -> Void) {
        signaling?.requestToPublish(mediaTypes: mediaTypes, alias: alias) { result in
            print("Request to publish...")
            completion()
        }
    }
    
    private func setupNewPeerConnection(peerConnection: RTCPeerConnection, endpointId: String, mediaTypes: String, alias: String?) {
        
    }
    
    private func negotiateSdp(endpointId: String, direction: String, peerConnection: RTCPeerConnection) {
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        peerConnection.offer(for: constraints) { offer, error in
            if let error = error {
                print(error.localizedDescription)
            }
            
            if let offer = offer {
                print("Send offer to signaling server...")
                
                self.signaling?.offerSDP(endpointId: endpointId, sdpOffer: offer.sdp) { result in
                    
                    peerConnection.setLocalDescription(offer) { error in
                        if let error = error {
                            print(error.localizedDescription)
                        }
                        
                        guard let result = result else {
                            return
                        }
                        
                        let description = RTCSessionDescription(type: .answer, sdp: result.sdpAnswer)
                            
                        peerConnection.setRemoteDescription(description) { error in
                                
                            for candidate in result.candidates ?? [] {
                                let iceCandidate = RTCIceCandidate(sdp: candidate.candidate, sdpMLineIndex: Int32(candidate.sdpMLineIndex), sdpMid: candidate.sdpMid)
                                peerConnection.add(iceCandidate)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension BandwidthRTC: SignalingDelegate {
    func signaling(_ signaling: Signaling, didReceiveSDPNeeded parameters: SDPNeededParameters) {
        let endpointId = parameters.endpointId
        let alias = parameters.alias
        
        let config = RTCConfiguration()
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        let peerConnection = BandwidthRTC.factory.peerConnection(with: config, constraints: constraints, delegate: self)
        remotePeerConnections[endpointId] = peerConnection
        
        print("SDP direction: \(parameters.direction)")
        
        negotiateSdp(endpointId: endpointId, direction: parameters.direction, peerConnection: peerConnection)
    }
    
    func signaling(_ signaling: Signaling, didReceiveAddICECandidate parameters: AddICECandidateParameters) {
        
    }
    
    func signaling(_ signaling: Signaling, didReceiveEndpointRemoved parameters: EndpointRemovedParameters) {
        
    }
}

extension BandwidthRTC: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("RTCPeerConnection didChange stateChanged")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("RTCPeerConnection didAdd stream")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("RTCPeerConnection didRemove stream")
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("RTCPeerConnection should negotiate.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("A peer connection has generated an ICE candiate.")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        
    }
}
