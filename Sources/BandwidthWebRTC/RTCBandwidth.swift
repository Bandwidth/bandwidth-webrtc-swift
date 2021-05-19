//
//  RTCBandwidth.swift
//
//
//  Created by Michael Hamer on 12/17/20.
//

import Foundation
import WebRTC

public protocol RTCBandwidthDelegate {
    func bandwidth(_ bandwidth: RTCBandwidth, streamAvailable endpointId: String, mediaStream: RTCMediaStream)
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
    
    // One peer for all published (outgoing) streams, one for all subscribed (incoming) streams.
    private var publishingPeerConnection: RTCPeerConnection?
    private var subscribingPeerConnection: RTCPeerConnection?
    
    // Standard data channels used for platform diagnostics and health checks.
    private var publishHeartbeatDataChannel: RTCDataChannel?
    private var publishDiagnosticsDataChannel: RTCDataChannel?
    private var publishedDataChannels: [String: RTCDataChannel] = [:]
    private var subscribeHeartbeatDataChannel: RTCDataChannel?
    private var subscribeDiagnosticsDataChannel: RTCDataChannel?
    private var subscribeDataChannels: [String: RTCDataChannel] = [:]
    
    private var publishDataChannelAdapter: DataChannelAdapter?
    
    // Published (outgoing) streams keyed by media stream id (msid).
    private var publishedStreams: [String: PublishedStream] = [:]
    // Subscribed (incoming) streams keyed by media stream id (msid).
    private var subscribingStreams: [String: StreamMetadata] = [:]
    
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
    public func connect(using token: String, completion: @escaping (Result<(), Error>) -> Void) {
        signaling = Signaling()
        signaling?.delegate = self
        
        signaling?.connect(using: token) { result in
            completion(result)
        }
    }
    
    /// Connect to the signaling server to start publishing media.
    /// - Parameters:
    ///   - url: Complete URL containing everything required to access WebRTC.
    ///   - completion: The completion handler to call when the connect request is complete.
    public func connect(to url: URL, completion: @escaping (Result<(), Error>) -> Void) {
        signaling = Signaling()
        signaling?.delegate = self
        
        signaling?.connect(to: url) { result in
            completion(result)
        }
    }
    
    /// Disconnect from Bandwidth's WebRTC signaling server and remove all local connections.
    public func disconnect() {
        signaling?.disconnect()
    }

    public func publish(alias: String?, completion: @escaping (RTCRtpSender?, RTCRtpSender?) -> Void) {
        setupPublishingPeerConnection {
//            let streamId = UUID().uuidString
            
            let mediaStream = RTCBandwidth.factory.mediaStream(withStreamId: UUID().uuidString)
            
            let audioTrack = RTCBandwidth.factory.audioTrack(with: RTCBandwidth.factory.audioSource(with: nil), trackId: UUID().uuidString)
            mediaStream.addAudioTrack(audioTrack)
            
//            let audioSender = self.publishingPeerConnection?.add(audioTrack, streamIds: [streamId])
            
            let videoTrack = RTCBandwidth.factory.videoTrack(with: RTCBandwidth.factory.videoSource(), trackId: UUID().uuidString)
            mediaStream.addVideoTrack(videoTrack)
//            let videoSender = self.publishingPeerConnection?.add(videoTrack, streamIds: [streamId])
            
//            let transceiverInit = RTCRtpTransceiverInit()
            
            self.publishingPeerConnection?.addTransceiver(with: audioTrack)
            self.publishingPeerConnection?.addTransceiver(with: videoTrack)
            
            let publishMetadata = StreamPublishMetadata(alias: "usermedia")
            self.publishedStreams[mediaStream.streamId] = PublishedStream(mediaStream: mediaStream, metadata: publishMetadata)
            
            self.offerPublishSDP { result in
                completion(nil, nil) // TODO: temp return nil
            }
        }
    }
    
    private func addHeartbeatDataChannel(peerConnection: RTCPeerConnection) -> RTCDataChannel? {
        let configuration = RTCDataChannelConfiguration()
        configuration.channelId = 0
        configuration.isNegotiated = true
        configuration.protocol = "udp"
        
        return peerConnection.dataChannel(forLabel: "__heartbeat__", configuration: configuration)
    }
    
    private func addDiagnosticsDataChannel(peerConnection: RTCPeerConnection) -> RTCDataChannel? {
        let configuration = RTCDataChannelConfiguration()
        configuration.channelId = 1
        configuration.isNegotiated = true
        configuration.protocol = "udp"
        
        let dataChannel = peerConnection.dataChannel(forLabel: "__diagnostics__", configuration: configuration)
        publishDataChannelAdapter = DataChannelAdapter(
            didReceiveMessageWithBuffer: { _, buffer in
                debugPrint("Diagnostics Received: \(String(data: buffer.data, encoding: .utf8) ?? "")")
            }
        )
        dataChannel?.delegate = publishDataChannelAdapter
        
        return dataChannel
    }
    
    private func setupPublishingPeerConnection(completion: @escaping () -> Void) {
        guard publishingPeerConnection == nil else {
            completion()
            return
        }
        
        publishingPeerConnection = RTCBandwidth.factory.peerConnection(with: configuration, constraints: mediaConstraints, delegate: PeerConnectionAdapter(
            didChangePeerConnectionState: { peerConnection, state in
                if state == .failed {
                    self.offerPublishSDP(restartICE: true) { _ in
                        
                    }
                }
            },
            didAddRTPReceiverAndMediaStreams: { peerConnection, rtpReceiver, mediaStreams in
                for mediaStream in mediaStreams {
                    let publishMetadata = StreamPublishMetadata(alias: "usermedia")
                    self.publishedStreams[mediaStream.streamId] = PublishedStream(mediaStream: mediaStream, metadata: publishMetadata)
                }
            })
        )
        
        if let publishingPeerConnection = publishingPeerConnection {
            if let heartbeatDataChannel = addHeartbeatDataChannel(peerConnection: publishingPeerConnection) {
                publishedDataChannels[heartbeatDataChannel.label] = heartbeatDataChannel
                publishHeartbeatDataChannel = heartbeatDataChannel
            }
            
            if let diagnosticsDataChannel = addDiagnosticsDataChannel(peerConnection: publishingPeerConnection) {
                publishedDataChannels[diagnosticsDataChannel.label] = diagnosticsDataChannel
                publishDiagnosticsDataChannel = diagnosticsDataChannel
            }
        }
        
        offerPublishSDP { _ in
            
            // (Re)publish any existing media streams.
            if !self.publishedStreams.isEmpty {
                // TODO: self.publishedStreams.forEach...
                // TODO: addStreamToPublishingPeerConnection(self.publishedStream.mediaStream)
                
                self.offerPublishSDP { _ in
                    completion()
                }
            }
            
            completion()
        }
    }
    
    private func setupSubscribingPeerConnection() {
        subscribingPeerConnection = RTCBandwidth.factory.peerConnection(with: configuration, constraints: mediaConstraints, delegate: PeerConnectionAdapter(
                didChangePeerConnectionState: { _, _ in
                    
                },
                didAddRTPReceiverAndMediaStreams: { peerConnection, rtpReceiver, mediaStreams in
                    for mediaStream in mediaStreams {
                        self.delegate?.bandwidth(self, streamAvailable: mediaStream.streamId, mediaStream: mediaStream)
                    }
                }
            )
        )
    }
    
    private func offerPublishSDP(restartICE: Bool = false, completion: @escaping (OutgoingOfferSDPResult) -> Void) {
        let mandatoryConstraints = [
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse,
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse,
            kRTCMediaConstraintsVoiceActivityDetection: kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsIceRestart: restartICE ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse
        ]
        
        let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
        
        publishingPeerConnection?.offer(for: mediaConstraints, completionHandler: { localSDPOffer, error in
            guard let localSDPOffer = localSDPOffer else {
                return
            }
            
            let mediaStreams = self.publishedStreams.mapValues { $0.metadata }
            let dataChannels = self.publishedDataChannels.mapValues { DataChannelPublishMetadata(label: $0.label, streamId: $0.channelId) }
            let publishMetadata = PublishMetadata(mediaStreams: mediaStreams, dataChannels: dataChannels)
            
            self.signaling?.offer(sdp: localSDPOffer.sdp, publishMetadata: publishMetadata) { result in
                
                switch result {
                case .success(let result):
                    self.publishingPeerConnection?.setLocalDescription(localSDPOffer) { error in
                        guard let result = result else {
                            return
                        }
                        
                        let sdp = RTCSessionDescription(type: .answer, sdp: result.sdpAnswer)
                        
                        self.publishingPeerConnection?.setRemoteDescription(sdp) { error in
                            completion(result)
                        }
                    }
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
        })
    }
    
    /// Stops the signaling server from publishing `endpointId` and close the associated `RTCPeerConnection`.
    ///
    /// - Parameter endpointId: The endpoint id for the local connection.
    public func unpublish(endpointId: String) {
        
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
    
    private func handleSubscribeOfferSDP(parameters: IncomingOfferSDPParams, completion: @escaping () -> Void) {
        // TODO: Check sdp version
        
        subscribingStreams = parameters.streamMetadata
        
        if subscribingPeerConnection == nil {
            setupSubscribingPeerConnection()
        }
        
        // Munge, munge, munge
        
        let sessionDescription = RTCSessionDescription(type: .offer, sdp: parameters.sdpOffer)
        subscribingPeerConnection?.setRemoteDescription(sessionDescription) { error in
            self.subscribingPeerConnection?.answer(for: self.mediaConstraints) { sessionDescription, error in
                guard let sessionDescription = sessionDescription else {
                    // Improve error handling here.
                    return
                }
                
                // Munge, munge, munge
                
                self.subscribingPeerConnection?.setLocalDescription(sessionDescription) { error in
                    self.signaling?.answer(sdp: sessionDescription.sdp) { _ in
                        completion()
                    }
                }
            }
        }
    }
}

extension RTCBandwidth: SignalingDelegate {
    func signaling(_ signaling: Signaling, didRecieveOfferSDP parameters: IncomingOfferSDPParams) {
        handleSubscribeOfferSDP(parameters: parameters) {
            
        }
    }
}
