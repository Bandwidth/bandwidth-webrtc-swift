//
//  BandwidthRTC.swift
//
//
//  Created by Michael Hamer on 12/17/20.
//

import Foundation
import WebRTC

protocol BandwidthRTCDelegate: class {
    func bandwidthRTC(_ bandwidthRTC: BandwidthRTC, didConnect signaling: Signaling)
    func bandwidthRTC(_ bandwidthRTC: BandwidthRTC, didDisconnect signaling: Signaling)
    func bandwidthRTC(_ bandwidthRTC: BandwidthRTC, didReceiveRemoteSDP sdp: RTCSessionDescription)
    func bandwidthRTC(_ bandwidthRTC: BandwidthRTC, didReceiveRemoteICECandidate candidate: RTCIceCandidate)
}

final class BandwidthRTC: NSObject {
    private var signaling: Signaling?
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    private let configuration = RTCConfiguration()
    private let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
    
    private var localConnections = [Connection]()
    private var remoteConnections = [Connection]()
    
    #if os(iOS)
    private let audioSession =  RTCAudioSession.sharedInstance()
    #endif
    
    private let audioQueue = DispatchQueue(label: "audio")
    
    weak var delegate: BandwidthRTCDelegate?
    
    public override init() {
        super.init()
        
        configureAudioSession()
    }
    
    public func connect(using token: String, completion: @escaping () -> Void) throws {
        signaling = Signaling()
        signaling?.delegate = self
        
        try signaling?.connect(using: token) {
            completion()
        }
    }
    
    public func publish(completion: @escaping () -> Void) {
        signaling?.setMediaPreferences(protocol: "WEB_RTC", aggregationType: "NONE", sendReceive: false) { result in
            self.signaling?.requestToPublish(mediaTypes: ["AUDIO"], alias: nil) { result in
                guard let result = result else {
                    return
                }
                
                let peerConnection = BandwidthRTC.factory.peerConnection(with: self.configuration, constraints: self.mediaConstraints, delegate: nil)
                peerConnection.delegate = self
                
                self.createMediaSenders(peerConnection: peerConnection)
                
                let localConnection = Connection(endpointId: result.endpointId, peerConnection: peerConnection)
                self.localConnections.append(localConnection)
                
                self.negotiateSDP(endpointId: result.endpointId, direction: result.direction, mediaTypes: result.mediaTypes, for: peerConnection)
            }
        }
    }
    
    // MARK: Media
    
    func configureAudioSession() {
        #if os(iOS)
        audioSession.lockForConfiguration()
        
        defer {
            audioSession.unlockForConfiguration()
        }
        
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
            try audioSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
        } catch let error {
            debugPrint("Error updating AVAudioSession category: \(error.localizedDescription)")
        }
        #endif
    }
    
    private func createMediaSenders(peerConnection: RTCPeerConnection) {
        let streamId = "stream"
        
        // Create an audio track for the peer connection.
        let audioTrack = self.createAudioTrack()
        peerConnection.add(audioTrack, streamIds: [streamId])
        
        // TODO: Video
        
        // TODO: Data?
    }
    
    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = BandwidthRTC.factory.audioSource(with: audioConstraints)
        let audioTrack = BandwidthRTC.factory.audioTrack(with: audioSource, trackId: "audio0")

        return audioTrack
    }
    
    private func negotiateSDP(endpointId: String, direction: String, mediaTypes: [String], for peerConnection: RTCPeerConnection) {
        debugPrint(direction)
        
        var mandatoryConstraints = [
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse,
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
        ]
        
        if direction.contains("recv") {
            mandatoryConstraints[kRTCMediaConstraintsOfferToReceiveAudio] = mediaTypes.contains("AUDIO") ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse
            mandatoryConstraints[kRTCMediaConstraintsOfferToReceiveVideo] = mediaTypes.contains("VIDEO") ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse
        }
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
        
        peerConnection.offer(for: constraints) { offer, error in
            DispatchQueue.main.async {
                if let error = error {
                    print(error.localizedDescription)
                }
            
                guard let offer = offer else {
                    return
                }
            
                self.signaling?.offer(endpointId: endpointId, sdp: offer.sdp) { result in
                    guard let result = result else {
                        return
                    }
                
                    peerConnection.setLocalDescription(offer) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                debugPrint(error.localizedDescription)
                            }
                            
                            let sdp = RTCSessionDescription(type: .answer, sdp: result.sdpAnswer)
                            
                            peerConnection.setRemoteDescription(sdp) { error in
                                if let error = error {
                                    debugPrint(error.localizedDescription)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func handleSDPNeededEvent(parameters: SDPNeededParameters) {
        let peerConnection = BandwidthRTC.factory.peerConnection(with: configuration, constraints: mediaConstraints, delegate: self)
        let remoteConnection = Connection(endpointId: parameters.endpointId, peerConnection: peerConnection)
        
        remoteConnections.append(remoteConnection)
        
        negotiateSDP(endpointId: parameters.endpointId, direction: parameters.direction, mediaTypes: parameters.mediaTypes, for: peerConnection)
    }
    
    private func handleIceCandidateEvent(parameters: AddICECandidateParameters) {
        guard let connection = remoteConnections.first(where: { $0.endpointId == parameters.endpointId }) ?? localConnections.first(where: { $0.endpointId == parameters.endpointId }) else {
            // TODO: Add ICE Candidate queues?
            return
        }
        
        let candidate = RTCIceCandidate(
            sdp: parameters.candidate.candidate,
            sdpMLineIndex: Int32(parameters.candidate.sdpMLineIndex),
            sdpMid: parameters.candidate.sdpMid
        )

        connection.peerConnection.add(candidate)

        delegate?.bandwidthRTC(self, didReceiveRemoteICECandidate: candidate)
    }
}

extension BandwidthRTC: RTCPeerConnectionDelegate {
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        debugPrint("peerConnectionShouldNegotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        debugPrint("peerConnection didChange stateChanged: \(stateChanged)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        debugPrint("peerConnection didAdd stream: RTCMediaStream")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        debugPrint("peerConnection didRemove stream: RTCMediaStream")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        debugPrint("peerConnection didChange newState: RTCIceConnectionState - \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        debugPrint("peerConnection didChange newState: RTCIceGatheringState - \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        debugPrint("peerConnection didGenerate candidate: RTCIceCandidate")
        
        guard let endpointId = remoteConnections.first(where: { $0.peerConnection == peerConnection })?.endpointId else {
            return
        }
        
        signaling?.sendIceCandidate(endpointId: endpointId, candidate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        debugPrint("peerConnection didRemove candidates: [RTCIceCandidate]")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        debugPrint("peerConnection didOpen dataChannel: RTCDataChannel")
    }
}

extension BandwidthRTC: SignalingDelegate {
    func signaling(_ signaling: Signaling, didConnect isConnected: Bool) {
        delegate?.bandwidthRTC(self, didConnect: signaling)
    }
    
    func signaling(_ signaling: Signaling, didDisconnect isConnected: Bool) {
        delegate?.bandwidthRTC(self, didDisconnect: signaling)
    }
    
    func signaling(_ signaling: Signaling, didReceiveSDPNeeded parameters: SDPNeededParameters) {
        handleSDPNeededEvent(parameters: parameters)
    }
    
    func signaling(_ signaling: Signaling, didReceiveAddICECandidate parameters: AddICECandidateParameters) {
        handleIceCandidateEvent(parameters: parameters)
    }
    
    func signaling(_ signaling: Signaling, didReceiveEndpointRemoved parameters: EndpointRemovedParameters) {
        
    }
}