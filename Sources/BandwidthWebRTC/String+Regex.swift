//
//  String+Regex.swift
//  
//
//  Created by Michael Hamer on 5/26/21.
//

import Foundation

extension String {
    func matches(pattern: String, options: NSRegularExpression.Options) -> [NSTextCheckingResult] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let matches = regex?.matches(in: self, options: [], range: NSRange(location: 0, length: self.count))
        return matches ?? []
    }
    
    func isMatch(pattern: String) -> Bool {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: self.count))
            return !matches.isEmpty
        }
        return false
    }
}
