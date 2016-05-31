//
//  ViewController.swift
//  SwiftSocketExample
//
//  Created by Andrew Cavanagh on 5/30/16.
//  Copyright © 2016 Andrew Cavanagh. All rights reserved.
//

import UIKit
import SwiftSocket

final class ViewController: UIViewController {

    var timer: NSTimer?
    let socket = SocketManager<Payload>(host: "127.0.0.1", port: 6544)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        socket.tapInput { [weak self] in
            self?.readResponse($0)
        }
        socket.open()
        
        timer = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: #selector(send), userInfo: nil, repeats: true)
    }

    func send() {
        transmit("yolo swag")
    }
    
    func transmit(message: String) {
        guard let data = message.dataUsingEncoding(NSUTF8StringEncoding) else { return }
        socket.write(Payload(data: data))
    }
    
    func readResponse(response: Response<Payload>) {
        switch response {
        case .payload(let payload):
            print(payload.data)
            let message = NSString(data: payload.data, encoding: NSUTF8StringEncoding)
            print(message)
        case .error(_): break
        }
    }
    
}

