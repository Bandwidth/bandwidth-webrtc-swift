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
    case endpointRemoved
    case offerSDP = "offerSdp"
    case requestToPublish
    case sdpNeeded
    case setMediaPreferences
    case unpublish
    case leave
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
        
        try connect(to: url) {
            completion()
        }
    }
    
    func connect(to url: URL, completion: @escaping () -> Void) throws {
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
    
    func disconnect() {
        let leaveParameters = LeaveParameters()
        client.notify(method: SignalingMethod.leave.rawValue, parameters: leaveParameters) { _ in
            
        }
        
        client.disconnect {
            
        }
    }
    
    func unpublish(endpointId: String, completion: @escaping (Result<(), Error>) -> Void) {
        let unpublishParameters = UnpublishParameters(endpointId: endpointId)
        client.notify(method: SignalingMethod.unpublish.rawValue, parameters: unpublishParameters) { result in
            completion(result)
        }
    }
    
    func setMediaPreferences(protocol: String, aggregationType: String, sendReceive: Bool, completion: @escaping (SetMediaPreferencesResult?) -> Void) {
        let parameters = SetMediaPreferencesParameters(protocol: `protocol`, aggregationType: aggregationType, sendReceive: sendReceive)
        client.call(method: SignalingMethod.setMediaPreferences.rawValue, parameters: parameters, type: SetMediaPreferencesResult.self) { result in
            switch result {
            case .success(let result):
                completion(result)
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func requestToPublish(mediaTypes: [MediaType], alias: String?, completion: @escaping (RequestToPublishResult?) -> Void) {
        let parameters = RequestToPublishParameters(mediaTypes: mediaTypes, alias: alias)
        client.call(method: SignalingMethod.requestToPublish.rawValue, parameters: parameters, type: RequestToPublishResult.self) { result in
            switch result {
            case .success(let result):
                completion(result)
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func offer(endpointId: String, sdp: String, completion: @escaping (OfferSDPResult?) -> Void) {
        let parameters = OfferSDPParameters(endpointId: endpointId, sdpOffer: sdp)
        client.call(method: SignalingMethod.offerSDP.rawValue, parameters: parameters, type: OfferSDPResult.self) { result in
            switch result {
            case .success(let result):
                completion(result)
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func sendIceCandidate(endpointId: String, sdp: String, sdpMLineIndex: Int, sdpMid: String, completion: @escaping (Result<(), Error>) -> Void) {
        let parameters = AddICECandidateSendParameters(
            endpointId: endpointId,
            candidate: sdp,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )
        
        client.notify(method: SignalingMethod.addICECandidate.rawValue, parameters: parameters) { result in
            completion(result)
        }
    }
}
