# SwiftSocket

SwiftSocket is simple abstraction for sockets on iOS.

#### Usage

```swift
let socket = SocketManager<Payload>(host: "127.0.0.1", port: 1234)

socket.tapInput { [weak self] in
  self?.readResponse($0)
}

socket.open()

...

socket.write(Payload(data: data))
```

#### PayloadType

SwiftSocket uses a generic `PayloadType` to describe the application specific communication protocol of the socket.
This `PayloadType` is specified when the `SocketManager` instance is created.

This `PayloadType` is used when writing to and reading from the socket.

```swift
protocol PayloadType {
    static var headerSize: Int { get }
    init(data: NSData)
    func networkBytes() -> [UInt8]
}
```

An example `Payload : PayloadType` :

```swift
class Payload: PayloadType {
  let data: NSData
  func networkBytes() -> [UInt8] {
    return Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>(data.bytes), count: data.length))
  }
  init(data: NSData) {
    self.data = data
  }
  static var headerSize: Int { return strideof(UInt32) }
}
```

#### Discussion

This implemention is performant, but simple.  A single UInt32 is used as a header for each payload to be transmitted or recieved
and indicates the byte-length of the `PayloadType` to be written or read.  This head is transmitted on every write and expected 
to be present for every read.

