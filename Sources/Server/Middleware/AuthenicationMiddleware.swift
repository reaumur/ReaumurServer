//
//  AuthenicationMiddleware.swift
//  Server
//
//  Created by BluDesign, LLC on 8/9/17.
//

import Foundation
import Vapor
import MongoKitten

extension HTTPHeaders {
    public var bearerAuthorization: String? {
        get {
            guard let string = self[HTTP.HTTPHeaderName.authorization].first else { return nil }
            guard let range = string.range(of: "Bearer ") else { return nil }
            let token = string[range.upperBound...]
            return String(token)
        }
        set {
            if let bearer = newValue {
                replaceOrAdd(name: HTTP.HTTPHeaderName.authorization, value: "Bearer \(bearer)")
            } else {
                remove(name: HTTP.HTTPHeaderName.authorization)
            }
        }
    }
}

final class AuthenticationStorage: Service {
    var userId: ObjectId? = nil
    var permission: User.Permission? = nil
    
    init() { }
}

final class AdminAuthenticationMiddleware: Middleware, Service {
    
    static var shared = AdminAuthenticationMiddleware()
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        let authentication: Request.Authentication
        do {
            authentication = try request.authentication()
        } catch {
            if request.jsonResponse {
                return try request.statusResponse(status: .unauthorized).encode(for: request)
            }
            return try request.redirect(to: "/users/login?referrer=\(request.http.urlString)").encode(for: request)
        }
        guard authentication.permission.isAdmin else {
            if request.jsonResponse {
                return try request.statusResponse(status: .forbidden).encode(for: request)
            }
            return try request.redirect(to: "\(request.http.url.deletingLastPathComponent().absoluteString)").encode(for: request)
        }
        return try next.respond(to: request)
    }
}

final class AuthenticationMiddleware: Middleware, Service {
    
    static var shared = AuthenticationMiddleware()
    
    // MARK: - Methods
    
    func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        do {
            try request.authentication()
        } catch {
            if request.jsonResponse {
                return try request.statusResponse(status: .unauthorized).encode(for: request)
            }
            return try request.redirect(to: "/users/login?referrer=\(request.http.urlString)").encode(for: request)
        }
        return try next.respond(to: request)
    }
}

extension Request {
    struct Authentication {
        let userId: ObjectId
        let permission: User.Permission
        
        func canAccess(deviceId: ObjectId) throws -> Bool {
            if permission.isAdmin {
                return true
            }
            guard let device = try Device.collection.findOne("_id" == deviceId, projecting: [
                "_id",
                "hostDeviceId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Device not found")
            }
            let hostDeviceId = try device.extractObjectId("hostDeviceId")
            return try canAccess(hostDeviceId: hostDeviceId)
        }
        
        func canAccess(hostDeviceId: ObjectId) throws -> Bool {
            if permission.isAdmin {
                return true
            }
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                "_id",
                "userId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            let objectUserId = try hostDevice.extractObjectId("userId")
            return userId == objectUserId
        }
    }
    
    @discardableResult func authentication() throws -> Authentication {
        let authentication = try privateContainer.make(AuthenticationStorage.self)
        if let userId = authentication.userId, let permission = authentication.permission {
            return Authentication(userId: userId, permission: permission)
        }
        let token: String
        if let authorization = http.headers["Authorization"].first?.components(separatedBy: " ").last {
            token = authorization
        } else if let cookie = http.cookies["Server-Auth"]?.string {
            token = cookie
        } else {
            throw ServerAbort(.unauthorized, reason: "No authorization")
        }
        
        let tokenHash = try MainApplication.makeHash(token)
        guard var accessToken = try AccessToken.collection.findOne("token" == tokenHash) else {
            throw ServerAbort(.unauthorized, reason: "Authorization not found")
        }
        let tokenExpiration = try accessToken.extract("tokenExpires") as Date
        guard Date() < tokenExpiration else {
            throw ServerAbort(.unauthorized, reason: "Authorization is expired")
        }
        let userId = try accessToken.extract("userId") as ObjectId
        if tokenExpiration.timeIntervalSinceReferenceDate - 432000 < Date().timeIntervalSinceReferenceDate, let objectId = accessToken.objectId {
            let expirationDate = Date(timeIntervalSinceNow: AccessToken.cookieExpiresIn)
            accessToken["tokenExpires"] = expirationDate
            accessToken["endOfLife"] = expirationDate
            try AccessToken.collection.update("_id" == objectId, to: accessToken)
        }
        let permission = try accessToken.extractUserPermission("permission")
        authentication.userId = userId
        authentication.permission = permission
        return Authentication(userId: userId, permission: permission)
    }
}
