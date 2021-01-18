//
//  PeerConnectionState.swift
//  
//
//  Created by Michael Hamer on 1/11/21.
//

import Foundation

public enum PeerConnectionState {
    case new
    case connecting
    case connected
    case disconnected
    case failed
    case closed
}
