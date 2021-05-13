//
//  PeerConnectionAdapter.swift
//  
//
//  Created by Michael Hamer on 5/10/21.
//

import WebRTC

class PeerConnectionAdapter: NSObject, RTCPeerConnectionDelegate {
    private var didChangePeerConnectionState: PeerConnectionState?
    private var didAddRTPReceiverAndMediaStreams: RTPReceiverAndMediaStreams?
    
    init(didChangePeerConnectionState: @escaping PeerConnectionState,
         didAddRTPReceiverAndMediaStreams: @escaping RTPReceiverAndMediaStreams) {
        self.didChangePeerConnectionState = didChangePeerConnectionState
        self.didAddRTPReceiverAndMediaStreams = didAddRTPReceiverAndMediaStreams
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        
    }
    
    @available(*, deprecated)
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        
    }
    
    @available(*, deprecated)
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        didChangePeerConnectionState?(peerConnection, newState)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        didAddRTPReceiverAndMediaStreams?(peerConnection, rtpReceiver, mediaStreams)
    }
}

extension PeerConnectionAdapter {
    typealias PeerConnectionState = ((RTCPeerConnection, RTCPeerConnectionState) -> ())
    typealias RTPReceiverAndMediaStreams = ((RTCPeerConnection, RTCRtpReceiver, [RTCMediaStream]) -> ())
}
