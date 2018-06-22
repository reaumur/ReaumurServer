//
//  SocketProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 9/19/17.
//

import Foundation
import Vapor
import WebSocket
import MongoKitten
import Jobs

final class SocketHolder {
    let webSocket: WebSocket
    let userId: ObjectId
    let permission: User.Permission
    var pingCount: Int = 0
    
    init(webSocket: WebSocket, userId: ObjectId, permission: User.Permission) {
        self.webSocket = webSocket
        self.userId = userId
        self.permission = permission
        
        webSocket.onBinary { [unowned self] (webSocket, data) in
            guard let socketFrameHolder = try? JSONDecoder().decode(SocketFrameHolder.self, from: data) else { return }
            self.handle(socketFrameHolder: socketFrameHolder)
        }
        
        webSocket.onText { [unowned self] (webSocket, string) in
            guard let socketFrameHolder = try? JSONDecoder().decode(SocketFrameHolder.self, from: string) else { return }
            self.handle(socketFrameHolder: socketFrameHolder)
        }
    }
    
    func handle(socketFrameHolder: SocketFrameHolder) {
        if socketFrameHolder.type == .pong {
            pingCount = 0
        }
    }
    
    func sendPing() {
        pingCount += 1
        send(socketFrameHolder: SocketFrameHolder(type: .ping, data: nil))
    }
    
    func send(socketFrameHolder: SocketFrameHolder) {
        guard let string = socketFrameHolder.stringValue else { return }
        webSocket.send(string)
    }
}

final class SocketProvider: Service, WebSocketServer {
    
    static var shared = SocketProvider()
    var webSockets: [SocketHolder] = []
    
    init() {
        Logger.debug("Starting Socket Server")
        Jobs.add(interval: .seconds(10)) {
            for (index, socketHolder) in self.webSockets.enumerated() {
                if socketHolder.pingCount > 2 || socketHolder.webSocket.isClosed {
                    socketHolder.webSocket.close()
                    self.webSockets.remove(at: index)
                } else {
                    socketHolder.sendPing()
                }
            }
        }
    }
    
    func webSocketShouldUpgrade(for request: Request) -> HTTPHeaders? {
        guard let authorization = request.http.headers["Authorization"].first?.components(separatedBy: " ").last else { return nil }
        do {
            let tokenHash = try MainApplication.makeHash(authorization)
            guard let accessToken = try AccessToken.collection.findOne("token" == tokenHash) else { return nil }
            let tokenExpiration = try accessToken.extract("tokenExpires") as Date
            guard Date() < tokenExpiration else { return nil }
            _ = try accessToken.extract("userId") as ObjectId
            return [:]
        } catch {
            return nil
        }
    }
    
    func webSocketOnUpgrade(_ webSocket: WebSocket, for request: Request) {
        guard let authorization = request.http.headers["Authorization"].first?.components(separatedBy: " ").last else { return }
        do {
            let tokenHash = try MainApplication.makeHash(authorization)
            guard let accessToken = try AccessToken.collection.findOne("token" == tokenHash) else { return }
            let tokenExpiration = try accessToken.extract("tokenExpires") as Date
            guard Date() < tokenExpiration else { return }
            let userId = try accessToken.extract("userId") as ObjectId
            let permission = try accessToken.extractUserPermission("permission")
            self.webSockets.append(SocketHolder(webSocket: webSocket, userId: userId, permission: permission))
        } catch {
            Logger.error("Socket Error")
        }
    }
    
    func send(socketFrameHolder: SocketFrameHolder, userId: ObjectId) {
        for socketHolder in webSockets {
            if socketHolder.permission == .admin || socketHolder.userId == userId {
                socketHolder.send(socketFrameHolder: socketFrameHolder)
            }
        }
    }
}
