//
//  SocketManager.swift
//  LPAC
//
//  Created by Andrew Cavanagh on 4/5/16.
//  Copyright © 2016 Andrew Cavanagh. All rights reserved.
//

import Foundation

// MARK: - Data Consumer

private final class DataConsumer {
    let buffer: NSMutableData

    let length: Int
    var bytesRead: Int = 0
    var bytesToRead: Int {
        return length - bytesRead
    }
    
    func nextBuffer() -> UnsafeMutablePointer<UInt8> {
        return UnsafeMutablePointer<UInt8>(buffer.mutableBytes.advancedBy(bytesRead))
    }
    
    init(length: UInt32) {
        self.length = Int(length);
        self.buffer = NSMutableData(length: Int(length))!
    }
}

// MARK: - SocketManager Delegate

private final class SocketManagerDelegate: NSObject, NSStreamDelegate {
    var inputStream: NSInputStream!
    var outputStream: NSOutputStream!
    var readBlock: (() -> Void)?
    var errorBlock: (() -> Void)?
    
    @objc func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        switch eventCode {
        case NSStreamEvent.HasBytesAvailable:
            if aStream == inputStream {
                readBlock?()
            }
        case NSStreamEvent.ErrorOccurred:
            self.errorBlock?()
        default: break
        }
    }
}

// MARK: - SocketConfig

private struct SocketConfig {
    let host: String
    let port: Int
    let secure: Bool
}

// MARK: - SocketError

public enum SocketError: ErrorType {
    case error
}

// MARK: - SocketResponse

public enum Response<T> {
    case payload(T)
    case error(ErrorType)
}

// MARK: - SocketManager

public final class SocketManager<T: PayloadType> {
    
    private let delegate = SocketManagerDelegate()
    private var socketConfig: SocketConfig
    private var currentConsumer: DataConsumer?
    private var tapBlock: ((response: Response<T>) -> Void)?
    
    public init(host: String, port: Int, secure: Bool = false) {
        socketConfig = SocketConfig(host: host, port: port, secure: secure)
    }
    
    private func connect() {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, socketConfig.host, UInt32(socketConfig.port), &readStream, &writeStream)
        
        delegate.readBlock = { [weak self] in self?.readData() }
        delegate.errorBlock = { [weak self] in self?.tapBlock?(response: Response.error(SocketError.error)) }
        delegate.inputStream = readStream!.takeRetainedValue()
        delegate.outputStream = writeStream!.takeRetainedValue()
        
        if socketConfig.secure {
            delegate.inputStream.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            delegate.outputStream.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            
            var settings = [NSObject : AnyObject]()
            settings[kCFStreamSSLValidatesCertificateChain] = NSNumber(bool: false)
            settings[kCFStreamSSLPeerName] = kCFNull
            
            CFReadStreamSetProperty(delegate.inputStream, kCFStreamPropertySSLSettings, settings)
            CFWriteStreamSetProperty(delegate.outputStream, kCFStreamPropertySSLSettings, settings)
        }
        
        delegate.inputStream.delegate = delegate
        delegate.outputStream.delegate = delegate
    }
    
    deinit {
        close()
    }
    
    private func handlePayload(consumer: DataConsumer) {
        guard let block = tapBlock else { return }
        let payload = T(data: consumer.buffer)
        dispatch_async(dispatch_get_main_queue()) {
            block(response: Response.payload(payload))
        }
    }
    
    private func payloadSize() -> UInt32 {
        let length = strideof(T.HeaderType.self)
        var buffer = [UInt8](count: length, repeatedValue: 0)
        delegate.inputStream.read(&buffer, maxLength: strideof(UInt8) * length)
        return CFSwapInt32BigToHost(fromByteArray(buffer, UInt32.self))
    }
    
    private func readData() {
        while delegate.inputStream.hasBytesAvailable {
            if currentConsumer == nil {
                currentConsumer = DataConsumer(length: payloadSize())
            }
            guard let consumer = currentConsumer else { return }
            
            let readByteCount = delegate.inputStream.read(consumer.nextBuffer(), maxLength: consumer.bytesToRead)
            if readByteCount < 0 {
                close()
                currentConsumer = nil
                tapBlock?(response: Response.error(SocketError.error))
                return
            }
            
            consumer.bytesRead += readByteCount
            if consumer.bytesToRead == 0 {
                handlePayload(consumer)
                currentConsumer = nil
            }
        }
    }

}

// MARK: - Public Interface

public extension SocketManager {
    public func write(payload: [UInt8]) {
        var header = UInt32(payload.count).bigEndian
        var headerBytes = toByteArray(&header)
        headerBytes.appendContentsOf(payload)
        delegate.outputStream.write(headerBytes, maxLength: strideof(UInt8) * headerBytes.count)
    }

    public func tapInput(block: (response: Response<T>) -> Void) {
        tapBlock = block
    }
    
    public func open() {
        connect()
        delegate.inputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        delegate.outputStream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        delegate.inputStream.open()
        delegate.outputStream.open()
    }
    
    public func close() {
        delegate.inputStream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        delegate.outputStream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        delegate.inputStream.close()
        delegate.outputStream.close()
    }
}

// MARK: - PayloadType

private func toByteArray<T>(inout value: T) -> [UInt8] {
    return withUnsafePointer(&value) {
        Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: strideof(T)))
    }
}

private func fromByteArray<T>(value: [UInt8], _: T.Type) -> T {
    return value.withUnsafeBufferPointer {
        return UnsafePointer<T>($0.baseAddress).memory
    }
}

public protocol PayloadType {
    associatedtype HeaderType
    static var headerType: HeaderType { get }
    
    var data: NSData { get }
    init(data: NSData)
    func networkBytes() -> [UInt8]
}
