//
//  RequestToPublishParameters.swift
//  
//
//  Created by Michael Hamer on 12/15/20.
//

import Foundation

struct RequestToPublishParameters: Codable {
    let mediaTypes: [MediaType]
    let alias: String?
}
