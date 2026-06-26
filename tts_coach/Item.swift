//
//  Item.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
