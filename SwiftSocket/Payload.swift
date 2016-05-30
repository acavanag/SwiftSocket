//
//  FrameBuffer.swift
//  CarBrain
//
//  Created by Andrew Cavanagh on 5/29/16.
//  Copyright © 2016 Andrew Cavanagh. All rights reserved.
//

import Foundation

public final class Payload: PayloadType {
    public let data: NSData
    
    public func networkBytes() -> [UInt8] {
        return Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>(data.bytes), count: data.length))
    }
    
    public init(data: NSData) {
        self.data = data
    }
    
    public static var headerType: UInt32.Type { return UInt32.self }
}