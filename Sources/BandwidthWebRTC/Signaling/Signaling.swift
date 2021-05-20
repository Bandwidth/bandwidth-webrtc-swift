//
//  Signaling.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation
import JSONRPCWebSockets

enum SignalingMethod: String {
    case answerSDP = "answerSdp"
    case offerSDP = "offerSdp"
    case sdpOffer
    case setMediaPreferences
    case leave
}

protocol SignalingDelegate {
    func signaling(_ signaling: Signaling, didRecieveOfferSDP parameters: IncomingSDPOfferParams)
}

class Signaling {
    private let client = Client()
    private var hasSetMediaPreferences = false
    
    var delegate: SignalingDelegate?
    
    func connect(using token: String, completion: @escaping (Result<(), Error>) -> Void) {
        var urlComponents = URLComponents()
        urlComponents.scheme = "wss"
        urlComponents.host = "device.webrtc.bandwidth.com"
        urlComponents.path = "/v3"
        urlComponents.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "uniqueId", value: UUID().uuidString)
        ]
        
        guard let url = urlComponents.url else {
            completion(.failure(SignalingError.invalidWebSocketURL))
            return
        }
        
        connect(to: url) { result in
            completion(result)
        }
    }
    
    func connect(to url: URL, completion: @escaping (Result<(), Error>) -> Void) {
        do {
            try client.subscribe(to: SignalingMethod.sdpOffer.rawValue, type: IncomingSDPOfferParams.self)
            client.on(method: SignalingMethod.sdpOffer.rawValue, type: IncomingSDPOfferParams.self) { parameters in
                self.delegate?.signaling(self, didRecieveOfferSDP: parameters)
            }
        } catch {
            completion(.failure(error))
        }
        
        client.connect(url: url) {
            if !self.hasSetMediaPreferences {
                self.setMediaPreferences(protocol: "WEBRTC") { result in
                    self.hasSetMediaPreferences = true
                    
                    switch result {
                    case .success:
                        completion(.success(()))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } else {
                completion(.success(()))
            }
        }
    }
    
    func disconnect() {
        let leaveParameters = LeaveParameters()
        client.notify(method: SignalingMethod.leave.rawValue, parameters: leaveParameters) { _ in
            
        }
        
        client.disconnect {
            
        }
    }
    
    func offer(sdp: String, publishMetadata: PublishMetadata, completion: @escaping (Result<OutgoingOfferSDPResult?, Error>) -> Void) {
        let method = SignalingMethod.offerSDP.rawValue
        let parameters = OutgoingOfferSDPParams(sdpOffer: sdp, mediaMetadata: publishMetadata)
        
        client.call(method: method, parameters: parameters, type: OutgoingOfferSDPResult.self) { result in
            completion(result)
        }
    }
    
    func answer(sdp: String, completion: @escaping (Result<OutgoingAnswerSDPResult?, Error>) -> Void) {
        let method = SignalingMethod.answerSDP.rawValue
        let parameters = OutgoingAnswerSDPParams(sdpAnswer: sdp)
        
        client.call(method: method, parameters: parameters, type: OutgoingAnswerSDPResult.self) { result in
            completion(result)
        }
    }
    
    private func setMediaPreferences(protocol: String, completion: @escaping (Result<SetMediaPreferencesResult?, Error>) -> Void) {
        let parameters = SetMediaPreferencesParameters(protocol: `protocol`)
        client.call(method: SignalingMethod.setMediaPreferences.rawValue, parameters: parameters, type: SetMediaPreferencesResult.self) { result in
            completion(result)
        }
    }
}
