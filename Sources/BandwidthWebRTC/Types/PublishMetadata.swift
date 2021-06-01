//
//  PublishMetadata.swift
//  
//
//  Created by Michael Hamer on 5/10/21.
//

struct PublishMetadata: Codable {
    let mediaStreams: [String: StreamPublishMetadata]
    let dataChannels: [String: DataChannelPublishMetadata]
}
