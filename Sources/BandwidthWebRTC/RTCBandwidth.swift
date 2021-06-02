//
//  RTCBandwidth.swift
//
//
//  Created by Michael Hamer on 12/17/20.
//

import Foundation
import WebRTC

public protocol RTCBandwidthDelegate {
    func bandwidth(_ bandwidth: RTCBandwidth, streamAvailable stream: RTCStream)
    func bandwidth(_ bandwidth: RTCBandwidth, streamUnavailable stream: RTCStream)
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
        configuration.iceServers = []
        configuration.iceTransportPolicy = .all
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
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
    private var subscribedDataChannels: [String: RTCDataChannel] = [:]
    
    // Published (outgoing) streams keyed by media stream id (msid).
    private var publishedStreams: [String: PublishedStream] = [:]
    // Subscribed (incoming) streams keyed by media stream id (msid).
    private var subscribedStreams: [String: StreamMetadata] = [:]
    
    // Keep track of our available streams. Prevents duplicate stream available / unavailable events.
    private var availableMediaStreams: [String: RTCMediaStream] = [:]
    
    #if os(iOS)
    private let audioSession =  RTCAudioSession.sharedInstance()
    #endif
    
    private let audioQueue = DispatchQueue(label: "audio")
    
    private let userAgent = UserAgent()
    
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
        
        
        let sdkVersion = userAgent.build(packageName: "BandwidthWebRTCSwift")
        
        signaling?.connect(using: token, sdkVersion: sdkVersion) { result in
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
    
    /// Disconnect from Bandwidth's WebRTC signaling server and remove all connections.
    public func disconnect() {
        signaling?.disconnect()
        cleanupPublishedStreams(publishedStreams: publishedStreams)
        publishingPeerConnection?.close()
        subscribingPeerConnection?.close()
        publishingPeerConnection = nil
        subscribingPeerConnection = nil
    }

    public func publish(alias: String?, completion: @escaping (RTCStream) -> Void) {
        setupPublishingPeerConnection {
            let mediaStream = RTCBandwidth.factory.mediaStream(withStreamId: UUID().uuidString)
            
            let audioTrack = RTCBandwidth.factory.audioTrack(with: RTCBandwidth.factory.audioSource(with: nil), trackId: UUID().uuidString)
            mediaStream.addAudioTrack(audioTrack)
            
            let videoTrack = RTCBandwidth.factory.videoTrack(with: RTCBandwidth.factory.videoSource(), trackId: UUID().uuidString)
            mediaStream.addVideoTrack(videoTrack)
            
            self.addStreamToPublishingPeerConnection(mediaStream: mediaStream)
            
            let publishMetadata = StreamPublishMetadata(alias: alias)
            self.publishedStreams[mediaStream.streamId] = PublishedStream(mediaStream: mediaStream, metadata: publishMetadata)
            
            self.offerPublishSDP { result in
                let stream = RTCStream(mediaTypes: result.streamMetadata[mediaStream.streamId]?.mediaTypes ?? [.application],
                                       mediaStream: mediaStream,
                                       alias: alias,
                                       participantId: nil)
                
                completion(stream)
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
        dataChannel?.delegate = self
        
        return dataChannel
    }
    
    private func setupPublishingPeerConnection(completion: @escaping () -> Void) {
        guard publishingPeerConnection == nil else {
            completion()
            return
        }
        
        publishingPeerConnection = RTCBandwidth.factory.peerConnection(with: configuration, constraints: mediaConstraints, delegate: self)
        
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
            for publishedStream in self.publishedStreams {
                self.addStreamToPublishingPeerConnection(mediaStream: publishedStream.value.mediaStream)
                
                self.offerPublishSDP { _ in
                    completion()
                }
            }
            
            completion()
        }
    }
    
    private func setupSubscribingPeerConnection() {
        subscribingPeerConnection = RTCBandwidth.factory.peerConnection(with: configuration, constraints: mediaConstraints, delegate: self)
        
        if let subscribingPeerConnection = subscribingPeerConnection {
            if let heartbeatDataChannel = addHeartbeatDataChannel(peerConnection: subscribingPeerConnection) {
                subscribedDataChannels[heartbeatDataChannel.label] = heartbeatDataChannel
                subscribeHeartbeatDataChannel = heartbeatDataChannel
            }
            
            if let diagnosticsDataChannel = addDiagnosticsDataChannel(peerConnection: subscribingPeerConnection) {
                subscribedDataChannels[diagnosticsDataChannel.label] = diagnosticsDataChannel
                subscribeDiagnosticsDataChannel = diagnosticsDataChannel
            }
        }
    }
    
    private func offerPublishSDP(restartICE: Bool = false, completion: @escaping (OfferSDPResult) -> Void) {
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
    
    /// Stops the signaling server from publishing `streamId` and removes associated tracks.
    ///
    /// - Parameter streamId: The stream ids for the published streams.
    public func unpublish(streamIds: [String], completion: @escaping () -> Void) {
        let publishedStreams = self.publishedStreams.filter { streamIds.contains($0.key) }
        cleanupPublishedStreams(publishedStreams: publishedStreams)
        
        offerPublishSDP { _ in
            completion()
        }
    }
    
    private func addStreamToPublishingPeerConnection(mediaStream: RTCMediaStream) {
        for track in mediaStream.audioTracks + mediaStream.videoTracks {
            let transceiverInit = RTCRtpTransceiverInit()
            transceiverInit.direction = .sendOnly
            transceiverInit.streamIds = [mediaStream.streamId]

            publishingPeerConnection?.addTransceiver(with: track, init: transceiverInit)
        }
    }
    
    private func cleanupPublishedStreams(publishedStreams: [String: PublishedStream]) {
        for publishedStream in publishedStreams {
            let transceivers = publishingPeerConnection?.transceivers ?? []
            for transceiver in transceivers {
                let mediaStream = publishedStream.value.mediaStream
                
                for audioTrack in mediaStream.audioTracks {
                    if transceiver.sender.track == audioTrack {
                        publishingPeerConnection?.removeTrack(transceiver.sender)
                        transceiver.stopInternal()
                    }
                }
                
                for videoTrack in mediaStream.videoTracks {
                    if transceiver.sender.track == videoTrack {
                        publishingPeerConnection?.removeTrack(transceiver.sender)
                        transceiver.stopInternal()
                    }
                }
            }
            self.publishedStreams.removeValue(forKey: publishedStream.key)
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
    
    private func handleSubscribeOfferSDP(parameters: SDPOfferParams, completion: @escaping () -> Void) {
        subscribedStreams = parameters.streamMetadata
        
        if subscribingPeerConnection == nil {
            setupSubscribingPeerConnection()
        }
        
        let mungedSDP = setSDPMediaSetup(sdp: parameters.sdpOffer, considerDirection: true, withTemplate: "a=setup:actpass")
        let mungedSessionDescription = RTCSessionDescription(type: .offer, sdp: mungedSDP)
        
        subscribingPeerConnection?.setRemoteDescription(mungedSessionDescription) { error in
            if let error = error {
                debugPrint(error.localizedDescription)
            } else {
                self.subscribingPeerConnection?.answer(for: self.mediaConstraints) { sessionDescription, error in
                    if let error = error {
                        debugPrint(error.localizedDescription)
                    } else {
                        guard let sessionDescription = sessionDescription else {
                            return
                        }
                        
                        let mungedSDP = self.setSDPMediaSetup(sdp: sessionDescription.sdp, considerDirection: false, withTemplate: "a=setup:passive")
                        let mungedSessionDescription = RTCSessionDescription(type: sessionDescription.type, sdp: mungedSDP)
                        
                        self.subscribingPeerConnection?.setLocalDescription(mungedSessionDescription) { error in
                            if let error = error {
                                debugPrint(error.localizedDescription)
                            } else {
                                self.signaling?.answer(sdp: mungedSessionDescription.sdp) { _ in
                                    completion()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func setSDPMediaSetup(sdp: String, considerDirection: Bool, withTemplate template: String) -> String {
        var mungedSDP = sdp
        
        // Match all media descriptions within the sdp.
        let mediaMatches = sdp.matches(pattern: "m=.*?(?=m=|$)", options: .dotMatchesLineSeparators)
        
        // Iterate the media descriptions in reverse as we'll potentially be modifying them.
        for mediaMatch in mediaMatches.reversed() {
            guard let mediaRange = Range(mediaMatch.range, in: sdp) else {
                continue
            }
            
            let media = sdp[mediaRange]
            
            // Either do not consider the direction or only act on media descriptions without a direction.
            if !considerDirection || !String(media).isMatch(pattern: "a=(?:sendrecv|recvonly|sendonly|inactive)") {
                if let replaceRegex = try? NSRegularExpression(pattern: "a=setup:(?:active)", options: .caseInsensitive) {
                    mungedSDP = replaceRegex.stringByReplacingMatches(in: mungedSDP, options: [], range: mediaMatch.range, withTemplate: template)
                }
            }
        }
        
        return mungedSDP
    }
}

extension RTCBandwidth: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        
    }
    
    @available(*, deprecated)
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        
    }
    
    @available(*, deprecated)
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard subscribingPeerConnection == peerConnection else {
            return
        }
        
        for mediaStream in mediaStreams {
            if availableMediaStreams.updateValue(mediaStream, forKey: mediaStream.streamId) == nil {
                let subscribedStream = subscribedStreams[mediaStream.streamId]
                
                let stream = RTCStream(mediaTypes: subscribedStream?.mediaTypes ?? [],
                                    mediaStream: mediaStream,
                                    alias: subscribedStream?.alias,
                                    participantId: subscribedStream?.participantId)
                
                delegate?.bandwidth(self, streamAvailable: stream)
            }
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        guard subscribingPeerConnection == peerConnection else {
            return
        }
        
        guard let track = rtpReceiver.track else {
            return
        }
        
        let availableMediaStream = availableMediaStreams
            .first { $0.value.audioTracks.contains { $0.trackId == track.trackId } || $0.value.videoTracks.contains { $0.trackId == track.trackId } }
        
        if let availableMediaStream = availableMediaStream {
            let mediaStream = availableMediaStream.value
            
            let subscribedStream = subscribedStreams[mediaStream.streamId]
            
            let stream = RTCStream(mediaTypes: subscribedStream?.mediaTypes ?? [],
                                mediaStream: mediaStream,
                                alias: subscribedStream?.alias,
                                participantId: subscribedStream?.participantId)
            
            delegate?.bandwidth(self, streamUnavailable: stream)
            
            availableMediaStreams.removeValue(forKey: mediaStream.streamId)
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        guard publishingPeerConnection == peerConnection else {
            return
        }
        
        if newState == .failed {
            offerPublishSDP(restartICE: true) { _ in
                
            }
        }
    }
}

extension RTCBandwidth: RTCDataChannelDelegate {
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        
    }
    
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        debugPrint("Diagnostics Received: \(String(data: buffer.data, encoding: .utf8) ?? "")")
    }
}

extension RTCBandwidth: SignalingDelegate {
    func signaling(_ signaling: Signaling, didRecieveOfferSDP parameters: SDPOfferParams) {
        handleSubscribeOfferSDP(parameters: parameters) {
            
        }
    }
}
