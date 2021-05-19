//
//  DataChannelAdapter.swift
//  
//
//  Created by Michael Hamer on 5/19/21.
//

import Foundation
import WebRTC

class DataChannelAdapter: NSObject, RTCDataChannelDelegate {
    var didChangeState: DidChangeState?
    var didReceiveMessageWithBuffer: DidReceiveMessageWithBuffer?
    
    init(didChangeState: DidChangeState? = nil, didReceiveMessageWithBuffer: DidReceiveMessageWithBuffer? = nil) {
        self.didChangeState = didChangeState
        self.didReceiveMessageWithBuffer = didReceiveMessageWithBuffer
    }
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        didChangeState?(dataChannel)
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        didReceiveMessageWithBuffer?(dataChannel, buffer)
    }
}

extension DataChannelAdapter {
    typealias DidChangeState = ((RTCDataChannel) -> ())
    typealias DidReceiveMessageWithBuffer = (RTCDataChannel, RTCDataBuffer) -> ()
}
