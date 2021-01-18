//
//  RTCBandwidth.swift
//
//
//  Created by Michael Hamer on 12/17/20.
//

import Foundation
import WebRTC

public protocol RTCBandwidthDelegate: class {
    func rtcBandwidth(_ rtcBandwidth: RTCBandwidth, didChangePeerConnectionState state: PeerConnectionState?, with error: WebRTCError?)
    func rtcBandwidth(_ rtcBandwidth: RTCBandwidth, streamUnavailableAt endpointId: String)
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
    
    private var videoCapturer: RTCVideoCapturer?

    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    
    public weak var delegate: RTCBandwidthDelegate?
    
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
    
    public func publish(audio: Bool, video: Bool, completion: @escaping () -> Void) {
        var mediaTypes = [MediaType]()
        
        if audio {
            mediaTypes.append(.audio)
        }
        
        if video {
            mediaTypes.append(.video)
        }
        
        signaling?.setMediaPreferences(protocol: "WEB_RTC", aggregationType: "NONE", sendReceive: false) { result in
            self.signaling?.requestToPublish(mediaTypes: mediaTypes, alias: nil) { result in
                guard let result = result else {
                    return
                }
                
                let peerConnection = RTCBandwidth.factory.peerConnection(with: self.configuration, constraints: self.mediaConstraints, delegate: nil)
                peerConnection.delegate = self
                
                self.createMediaSenders(peerConnection: peerConnection, audio: audio, video: video)
                
                let localConnection = Connection(endpointId: result.endpointId, peerConnection: peerConnection)
                self.localConnections.append(localConnection)
                
                self.negotiateSDP(endpointId: result.endpointId, direction: result.direction, mediaTypes: result.mediaTypes, for: peerConnection) {
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            }
        }
    }
    
    // MARK: Media
    
    public func captureLocalVideo(renderer: RTCVideoRenderer) {
        guard let capturer = videoCapturer as? RTCCameraVideoCapturer else {
            return
        }
        
        // Grab the front facing camera. TODO: Add support for additional cameras.
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }) else {
            return
        }
        
        // Grab the highest resolution available.
        guard let format = RTCCameraVideoCapturer.supportedFormats(for: device)
            .sorted(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width })
            .last else { return }
        
        // Grab the highest fps available.
        guard let fps = format.videoSupportedFrameRateRanges
            .compactMap({ $0.maxFrameRate })
            .sorted()
            .last else { return }
        
        capturer.startCapture(with: device, format: format, fps: Int(fps))
        
        localVideoTrack?.add(renderer)
    }
    
    public func renderRemoteVideo(renderer: RTCVideoRenderer) {
        remoteVideoTrack?.add(renderer)
    }
    
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
    
    private func createMediaSenders(peerConnection: RTCPeerConnection, audio: Bool, video: Bool) {
        let streamId = "stream"
        
        // Create an audio track for the peer connection.
        if audio {
            let audioTrack = createAudioTrack()
            peerConnection.add(audioTrack, streamIds: [streamId])
        }

        // Create a video track for the peer connection.
        if video {
            let videoTrack = createVideoTrack()
            localVideoTrack = videoTrack
            peerConnection.add(videoTrack, streamIds: [streamId])
        }
    }
    
    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = RTCBandwidth.factory.audioSource(with: audioConstraints)
        let audioTrack = RTCBandwidth.factory.audioTrack(with: audioSource, trackId: "audio0")

        return audioTrack
    }
    
    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = RTCBandwidth.factory.videoSource()
        
        #if targetEnvironment(simulator)
        videoCapturer = RTCFileVideoCapturer(delegate: videoSource)
        #else
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        #endif
        
        let videoTrack = RTCBandwidth.factory.videoTrack(with: videoSource, trackId: "video0")
        
        return videoTrack
    }
    
    private func negotiateSDP(endpointId: String, direction: String, mediaTypes: [String], for peerConnection: RTCPeerConnection, completion: @escaping () -> Void) {
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
                                
                                completion()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func handleSDPNeededEvent(parameters: SDPNeededParameters) {
        let peerConnection = RTCBandwidth.factory.peerConnection(with: configuration, constraints: mediaConstraints, delegate: self)
        let remoteConnection = Connection(endpointId: parameters.endpointId, peerConnection: peerConnection)
        
        remoteConnections.append(remoteConnection)
        
        negotiateSDP(endpointId: parameters.endpointId, direction: parameters.direction, mediaTypes: parameters.mediaTypes, for: peerConnection) {
            
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
    
    private func endpointRemoved(with endpointId: String) {
        delegate?.rtcBandwidth(self, streamUnavailableAt: endpointId)
    }
}

extension RTCBandwidth: RTCPeerConnectionDelegate {
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        debugPrint("peerConnectionShouldNegotiate")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        debugPrint("peerConnection didChange newState: \(newState)")
        
        var state: PeerConnectionState?
        var error: WebRTCError?
        
        switch newState {
        case .closed:
            state = .closed
        case .failed:
            state = .failed
        case .disconnected:
            state = .disconnected
        case .new:
            state = .new
        case .connecting:
            state = .connecting
        case .connected:
            state = .connected
        default:
            error = .unknownPeerConnectionState
        }

        DispatchQueue.main.async {
            self.delegate?.rtcBandwidth(self, didChangePeerConnectionState: state, with: error)
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        debugPrint("peerConnection didAdd rtpReceiver: streams media Streams:")
        remoteVideoTrack = rtpReceiver.track as? RTCVideoTrack
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        debugPrint("peerConnection didChange stateChanged: \(stateChanged)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        debugPrint("peerConnection didAdd stream: RTCMediaStream")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        debugPrint("peerConnection didRemove stream: RTCMediaStream")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        debugPrint("peerConnection didChange newState: RTCIceConnectionState - \(newState)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        debugPrint("peerConnection didChange newState: RTCIceGatheringState - \(newState)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        debugPrint("peerConnection didGenerate candidate: RTCIceCandidate")
        
        guard let endpointId = remoteConnections.first(where: { $0.peerConnection == peerConnection })?.endpointId else {
            return
        }
        
        signaling?.sendIceCandidate(endpointId: endpointId, candidate: candidate)
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
        endpointRemoved(with: parameters.endpointId)
    }
}
