//
//  Signaling.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation
import JSONRPCWebSockets
import WebRTC

enum SignalingMethod: String {
    case addICECandidate = "addIceCandidate"
    case endpointRemoved
    case offerSDP = "offerSdp"
    case requestToPublish
    case sdpNeeded
    case setMediaPreferences
    case unpublish
}

protocol SignalingDelegate {
    func signaling(_ signaling: Signaling, didReceiveSDPNeeded parameters: SDPNeededParameters)
    func signaling(_ signaling: Signaling, didReceiveAddICECandidate parameters: AddICECandidateParameters)
    func signaling(_ signaling: Signaling, didReceiveEndpointRemoved parameters: EndpointRemovedParameters)
}

class Signaling {
    private let client = Client()
    
    var delegate: SignalingDelegate?
    
    func connect(using token: String, completion: @escaping () -> Void) throws {
        var urlComponents = URLComponents()
        urlComponents.scheme = "wss"
        urlComponents.host = "device.webrtc.bandwidth.com"
        urlComponents.path = "/v2"
        urlComponents.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "uniqueId", value: UUID().uuidString)
        ]
        
        guard let url = urlComponents.url else {
            throw SignalingError.invalidWebSocketURL
        }
        
        try client.subscribe(to: SignalingMethod.endpointRemoved.rawValue, type: EndpointRemovedParameters.self)
        client.on(method: SignalingMethod.endpointRemoved.rawValue, type: EndpointRemovedParameters.self) { parameters in
            self.delegate?.signaling(self, didReceiveEndpointRemoved: parameters)
        }
        
        try client.subscribe(to: SignalingMethod.sdpNeeded.rawValue, type: SDPNeededParameters.self)
        client.on(method: SignalingMethod.sdpNeeded.rawValue, type: SDPNeededParameters.self) { parameters in
            self.delegate?.signaling(self, didReceiveSDPNeeded: parameters)
        }
        
        try client.subscribe(to: SignalingMethod.addICECandidate.rawValue, type: AddICECandidateParameters.self)
        client.on(method: SignalingMethod.addICECandidate.rawValue, type: AddICECandidateParameters.self) { parameters in
            self.delegate?.signaling(self, didReceiveAddICECandidate: parameters)
        }

        client.connect(url: url) {
            completion()
        }
    }
    
    func setMediaPreferences(protocol: String, aggregationType: String, sendReceive: Bool, completion: @escaping (SetMediaPreferencesResult?) -> Void) {
        let parameters = SetMediaPreferencesParameters(protocol: `protocol`, aggregationType: aggregationType, sendReceive: sendReceive)
        do {
            try client.call(method: SignalingMethod.setMediaPreferences.rawValue, parameters: parameters, type: SetMediaPreferencesResult.self) { result in
                completion(result)
            }
        } catch let error {
            debugPrint(error.localizedDescription)
        }
    }
    
    func requestToPublish(mediaTypes: [String], alias: String?, completion: @escaping (RequestToPublishResult?) -> Void) {
        let parameters = RequestToPublishParameters(mediaTypes: mediaTypes, alias: alias)
        do {
            try client.call(method: SignalingMethod.requestToPublish.rawValue, parameters: parameters, type: RequestToPublishResult.self) { result in
                completion(result)
            }
        } catch let error {
            debugPrint(error.localizedDescription)
        }
    }
    
    func offer(endpointId: String, sdp: String, completion: @escaping (OfferSDPResult?) -> Void) {
        let parameters = OfferSDPParameters(endpointId: endpointId, sdpOffer: sdp)
        
        try? client.call(method: "offerSdp", parameters: parameters, type: OfferSDPResult.self) { result in
            completion(result)
        }
    }
    
    func sendIceCandidate(endpointId: String, candidate: RTCIceCandidate) {
        let parameters = AddICECandidateSendParameters(
            endpointId: endpointId,
            candidate: candidate.sdp,
            sdpMLineIndex: Int(candidate.sdpMLineIndex),
            sdpMid: candidate.sdpMid ?? "")
        
        try? client.notify(method: "addIceCandidate", parameters: parameters) { error in
            if let error = error {
                debugPrint(error.localizedDescription)
            }
        }
    }
}
