//
//  ConnectionState.swift
//  
//
//  Created by Michael Hamer on 1/11/21.
//

import Foundation

public enum ConnectionState {
    case new
    case checking
    case connected
    case completed
    case failed
    case disconnected
    case closed
}
