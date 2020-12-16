//
//  Signaling.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation
import JSONRPCWebSockets

enum SignalingMethod: String {
    case addICECandidate = "addIceCandidate"
    case offerSDP = "offerSdp"
    case requestToPublish
    case sdpNeeded
    case setMediaPreferences
    case unpublish
}

protocol SignalingDelegate {
    func signaling(_ signaling: Signaling, didReceiveSDPNeeded parameters: SDPNeededParameters)
    func signaling(_ signaling: Signaling, didReceiveAddICECandidate parameters: AddICECandidateParameters)
}

class Signaling {
    private let client = Client()
    private var hasSetMediaPreferences = false
    
    public var delegate: SignalingDelegate?
    
    public func connect(token: String, completion: @escaping () -> Void) throws {
        guard !token.isEmpty else {
            throw SignalingError.emptyToken
        }
        
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
        
        //TODO: client.subscriber(to: "endpointRemoved", type: )
        
        try? client.subscribe(to: SignalingMethod.sdpNeeded.rawValue, type: SDPNeededParameters.self)
        client.on(method: SignalingMethod.sdpNeeded.rawValue, type: SDPNeededParameters.self) { parameters in
            self.delegate?.signaling(self, didReceiveSDPNeeded: parameters)
        }
        
        try? client.subscribe(to: SignalingMethod.addICECandidate.rawValue, type: AddICECandidateParameters.self)
        client.on(method: SignalingMethod.addICECandidate.rawValue, type: AddICECandidateParameters.self) { parameters in
            self.delegate?.signaling(self, didReceiveAddICECandidate: parameters)
        }
        
        client.connect(url: url) {
            self.setMediaPreferences(protocol: "WEB_RTC", aggregationType: "NONE", sendReceive: false) { result in
                completion()
            }
        }
    }
    
    public func requestToPublish(mediaTypes: [String], alias: String?, completion: @escaping (RequestToPublishResult?) -> Void) {
        let parameters = RequestToPublishParameters(mediaTypes: mediaTypes, alias: alias)
        client.call(method: SignalingMethod.requestToPublish.rawValue, parameters: parameters, type: RequestToPublishResult.self) { result in
            completion(result)
        }
    }
    
    public func offerSDP(endpointId: String, sdpOffer: String, completion: @escaping (OfferSDPResult?) -> Void) {
        let parameters = OfferSDPParameters(endpointId: endpointId, sdpOffer: sdpOffer)
        client.call(method: SignalingMethod.offerSDP.rawValue, parameters: parameters, type: OfferSDPResult.self) { result in
            completion(result)
        }
    }
    
    public func addICECandidate(endpointId: String, candidate: String, sdpMLineIndex: Int, sdpMid: String, completion: @escaping (Error?) -> Void) throws {
        let candidate = AddICECandidateParameters.Candidate(candidate: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        let parameters = AddICECandidateParameters(endpointId: endpointId, candidate: candidate)
        try client.notify(method: SignalingMethod.addICECandidate.rawValue, parameters: parameters) { error in
            completion(error)
        }
    }
    
    public func unpublish(endpointId: String, completion: @escaping (Error?) -> Void) throws {
        let parameters = UnpublishParameters(endpointId: endpointId)
        try client.notify(method: SignalingMethod.unpublish.rawValue, parameters: parameters) { error in
            completion(error)
        }
    }
    
    private func setMediaPreferences(protocol: String, aggregationType: String, sendReceive: Bool, completion: @escaping (SetMediaPreferencesResult?) -> Void) {
        let parameters = SetMediaPreferencesParameters(protocol: `protocol`, aggregationType: aggregationType, sendReceive: sendReceive)
        self.client.call(method: SignalingMethod.setMediaPreferences.rawValue, parameters: parameters, type: SetMediaPreferencesResult.self) { result in
            completion(result)
        }
    }
}
