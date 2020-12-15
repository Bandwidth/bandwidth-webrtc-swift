//
//  Signaling.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation
import JSONRPCWebSockets

enum SignalingMethod: String {
    case sdpNeeded
    case addICECandidate = "addIceCandidate"
    case setMediaPreferences
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
        
        //client.subscriber(to: "endpointRemoved", type: )
        
        try? client.subscribe(to: SignalingMethod.sdpNeeded.rawValue, type: SDPNeededParameters.self)
        client.on(method: SignalingMethod.sdpNeeded.rawValue, type: SDPNeededParameters.self) { parameters in
            self.delegate?.signaling(self, didReceiveSDPNeeded: parameters)
        }
        
        try? client.subscribe(to: SignalingMethod.addICECandidate.rawValue, type: AddICECandidateParameters.self)
        client.on(method: SignalingMethod.addICECandidate.rawValue, type: AddICECandidateParameters.self) { parameters in
            self.delegate?.signaling(self, didReceiveAddICECandidate: parameters)
        }
        
        client.connect(url: url) {
            let parameters = SetMediaPreferencesParameters(protocol: "WEB_RTC", aggregationType: "NONE", sendReceive: false)
            
            self.client.call(method: SignalingMethod.setMediaPreferences.rawValue, parameters: parameters, type: SetMediaPreferencesResult.self) { result in
                completion()
            }
        }
    }
}
