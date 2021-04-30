//
//  RTCBandwidth.swift
//
//
//  Created by Michael Hamer on 12/17/20.
//

import Foundation
import WebRTC

public protocol RTCBandwidthDelegate {
    func bandwidth(_ bandwidth: RTCBandwidth, streamAvailableAt endpointId: String, participantId: String, alias: String?, mediaTypes: [MediaType], rtpReceiver: RTCRtpReceiver)
    func bandwidth(_ bandwidth: RTCBandwidth, streamUnavailableAt endpointId: String)
}

public class RTCBandwidth: NSObject {
    private var signaling: Signaling?
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    private let configuration: RTCConfiguration = {
        var configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        return configuration
    }()
    
    private let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue])
    
    private var localConnections = [Connection]()
    private var remoteConnections = [Connection]()
    
    #if os(iOS)
    private let audioSession =  RTCAudioSession.sharedInstance()
    #endif
    
    private let audioQueue = DispatchQueue(label: "audio")
    
    public var delegate: RTCBandwidthDelegate?
    
    public override init() {
        super.init()
        
        configureAudioSession()
    }
    
    
    /// Connect to the signaling server to start publishing media.
    /// - Parameters:
    ///   - token: Token returned from Bandwidth's servers giving permission to access WebRTC.
    ///   - completion: The completion handler to call when the connect request is complete.
    /// - Throws: Throw when a connection to the signaling server experiences an error.
    public func connect(using token: String, completion: @escaping () -> Void) throws {
        signaling = Signaling()
        signaling?.delegate = self
        
        let sdkVersion = UserAgent.build(packageName: "BandwidthWebRTCSwift", packageVersion: "0.4.0")
        
        try signaling?.connect(using: token, sdkVersion: sdkVersion) {
            completion()
        }
    }
    
    /// Connect to the signaling server to start publishing media.
    /// - Parameters:
    ///   - url: Complete URL containing everything required to access WebRTC.
    ///   - completion: The completion handler to call when the connect request is complete.
    /// - Throws: Throw when a connection to the signaling server experiences an error.
    public func connect(to url: URL, completion: @escaping () -> Void) throws {
        signaling = Signaling()
        signaling?.delegate = self
        
        try signaling?.connect(to: url) {
            completion()
        }
    }
    
    /// Disconnect from Bandwidth's WebRTC signaling server and remove all local connections.
    public func disconnect() {
        signaling?.disconnect()
        localConnections.forEach { $0.peerConnection.senders.forEach { $0.track?.isEnabled = false } }
        localConnections.removeAll()
    }

    /// Starts the signaling server publishing and calls a handler upon completion.
    /// - Parameters:
    ///   - audio: Request to publish audio.
    ///   - video: Request to publish video.
    ///   - alias: Optionally include an alias to assign to the request.
    ///   - completion: The completion handler to call when the publish request is complete.
    public func publish(audio: Bool, video: Bool, alias: String?, completion: @escaping (String, [MediaType], RTCRtpSender?, RTCRtpSender?) -> Void) {
        var mediaTypes = [MediaType]()
        
        if audio {
            mediaTypes.append(.audio)
        }
        
        if video {
            mediaTypes.append(.video)
        }
        
        signaling?.setMediaPreferences(protocol: "WEB_RTC", aggregationType: "NONE", sendReceive: false) { result in
            self.signaling?.requestToPublish(mediaTypes: mediaTypes, alias: alias) { result in
                guard let result = result else {
                    return
                }
                
                let peerConnection = RTCBandwidth.factory.peerConnection(with: self.configuration, constraints: self.mediaConstraints, delegate: self)
                
                var audioSender: RTCRtpSender?
                var videoSender: RTCRtpSender?
                
                let streamId = UUID().uuidString
                
                if mediaTypes.contains(.audio) {
                    let audioTrack = RTCBandwidth.factory.audioTrack(with: RTCBandwidth.factory.audioSource(with: nil), trackId: UUID().uuidString)
                    audioSender = peerConnection.add(audioTrack, streamIds: [streamId])
                }
                
                if mediaTypes.contains(.video) {
                    let videoTrack = RTCBandwidth.factory.videoTrack(with: RTCBandwidth.factory.videoSource(), trackId: UUID().uuidString)
                    videoSender = peerConnection.add(videoTrack, streamIds: [streamId])
                }

                let localConnection = Connection(peerConnection: peerConnection, endpointId: result.endpointId, participantId: result.participantId, mediaTypes: mediaTypes, alias: alias)
                self.localConnections.append(localConnection)
                
                self.negotiateSDP(endpointId: result.endpointId, direction: result.direction, mediaTypes: result.mediaTypes, for: peerConnection) {
                    completion(result.endpointId, result.mediaTypes, audioSender, videoSender)
                }
            }
        }
    }
    
    /// Stops the signaling server from publishing `endpointId` and close the associated `RTCPeerConnection`.
    ///
    /// - Parameter endpointId: The endpoint id for the local connection.
    public func unpublish(endpointId: String) {
        signaling?.unpublish(endpointId: endpointId) { result in

        }
        
        if let index = localConnections.firstIndex(where: { $0.endpointId == endpointId }) {
            localConnections[index].peerConnection.close()
            localConnections.remove(at: index)
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
    
    #if os(iOS)
    /// Determine whether the device's speaker should be in an enabled state.
    ///
    /// - Parameter isEnabled: A Boolean value indicating whether the device's speaker is in the enabled state.
    public func setSpeaker(_ isEnabled: Bool) {
        audioQueue.async {
            defer {
                RTCAudioSession.sharedInstance().unlockForConfiguration()
            }
            
            RTCAudioSession.sharedInstance().lockForConfiguration()
            do {
                try RTCAudioSession.sharedInstance().overrideOutputAudioPort(isEnabled ? .speaker : .none)
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }
    #endif
    
    private func negotiateSDP(endpointId: String, direction: String, mediaTypes: [MediaType], for peerConnection: RTCPeerConnection, completion: @escaping () -> Void) {
        debugPrint(direction)
        
        var mandatoryConstraints = [
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse,
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
        ]
        
        if direction.contains("recv") {
            mandatoryConstraints[kRTCMediaConstraintsOfferToReceiveAudio] = mediaTypes.contains(.audio) ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse
            mandatoryConstraints[kRTCMediaConstraintsOfferToReceiveVideo] = mediaTypes.contains(.video) ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse
        }
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
        
        peerConnection.offer(for: constraints) { offer, error in
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
                    if let error = error {
                        debugPrint(error.localizedDescription)
                    }
                    
                    let sdp = RTCSessionDescription(type: .answer, sdp: result.sdpAnswer)
                    
                    peerConnection.setRemoteDescription(sdp) { error in
                        if let error = error {
                            debugPrint(error.localizedDescription)
                        }
                        
                        completion()
                    }
                }
            }
        }
    }
    
    private func handleSDPNeededEvent(parameters: SDPNeededParameters) {
        let remotePeerConnection = RTCBandwidth.factory.peerConnection(with: configuration, constraints: mediaConstraints, delegate: self)
        
        let remoteConnection = Connection(
            peerConnection: remotePeerConnection,
            endpointId: parameters.endpointId,
            participantId: parameters.participantId,
            mediaTypes: parameters.mediaTypes,
            alias: parameters.alias
        )
        
        remoteConnections.append(remoteConnection)
        
        negotiateSDP(endpointId: parameters.endpointId, direction: parameters.direction, mediaTypes: parameters.mediaTypes, for: remotePeerConnection) {
            
        }
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
    }
}

extension RTCBandwidth: RTCPeerConnectionDelegate {
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        debugPrint("peerConnectionShouldNegotiate")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        debugPrint("peerConnection didAdd rtpReceiver: streams media Streams:")
        
        guard let remoteConnection = remoteConnections.first(where: { $0.peerConnection == peerConnection }) else { return }
        
        self.delegate?.bandwidth(
            self,
            streamAvailableAt: remoteConnection.endpointId,
            participantId: remoteConnection.participantId,
            alias: remoteConnection.alias,
            mediaTypes: remoteConnection.mediaTypes,
            rtpReceiver: rtpReceiver
        )
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        debugPrint("peerConnection didChange stateChanged: \(stateChanged)")
    }

    @available(*, deprecated)
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        
    }

    @available(*, deprecated)
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        debugPrint("peerConnection didChange newState: RTCIceConnectionState - \(newState)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        debugPrint("peerConnection didChange newState: RTCIceGatheringState - \(newState)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        debugPrint("peerConnection didGenerate candidate: RTCIceCandidate")
        
        guard let remoteConnection = remoteConnections.first(where: { $0.peerConnection == peerConnection }) else {
            return
        }
        
        signaling?.sendIceCandidate(
            endpointId: remoteConnection.endpointId,
            sdp: candidate.sdp,
            sdpMLineIndex: Int(candidate.sdpMLineIndex),
            sdpMid: candidate.sdpMid ?? ""
        ) { _ in
            
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        print("peerConnection didChange newState: \(newState)")
        
        if [.disconnected, .failed].contains(newState) {
            guard let index = remoteConnections.firstIndex(where: { $0.peerConnection == peerConnection }) else {
                return
            }
            
            delegate?.bandwidth(self, streamUnavailableAt: remoteConnections[index].endpointId)
            
            remoteConnections[index].peerConnection.close()
            remoteConnections.remove(at: index)
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        debugPrint("peerConnection didRemove candidates: [RTCIceCandidate]")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        debugPrint("peerConnection didOpen dataChannel: RTCDataChannel")
    }
}

extension RTCBandwidth: SignalingDelegate {
    func signaling(_ signaling: Signaling, didReceiveSDPNeeded parameters: SDPNeededParameters) {
        handleSDPNeededEvent(parameters: parameters)
    }
    
    func signaling(_ signaling: Signaling, didReceiveAddICECandidate parameters: AddICECandidateParameters) {
        handleIceCandidateEvent(parameters: parameters)
    }
    
    func signaling(_ signaling: Signaling, didReceiveEndpointRemoved parameters: EndpointRemovedParameters) {
        delegate?.bandwidth(self, streamUnavailableAt: parameters.endpointId)
    }
}
