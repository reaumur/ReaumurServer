//
//  Notifications+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 12/6/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto

struct NotificationRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        protectedRouter.get(use: get)
        protectedRouter.get(ObjectId.parameter, use: getNotification)
        protectedRouter.delete(ObjectId.parameter, use: deleteNotification)
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let pageInfo = request.pageInfo
            let authentication = try request.authentication()
            let query: Query?
            if authentication.permission.isAdmin == false {
                query = "userId" == authentication.userId
            } else {
                query = nil
            }
            let notifications = try Notification.collection.find(query, sortedBy: ["createdAt": .descending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            
            if request.jsonResponse {
                return promise.submit(try notifications.makeResponse(request))
            } else {
                let hostDevices = try HostDevice.collection.find(projecting: [
                    "_id",
                    "name"
                ])
                var hostDeviceNames: [ObjectId: String] = [:]
                for hostDevice in hostDevices {
                    guard let hostDeviceId = hostDevice.objectId, let name = hostDevice["name"] as? String else { continue }
                    hostDeviceNames[hostDeviceId] = name
                }
                let containers = try BrewContainer.collection.find(projecting: [
                    "_id",
                    "name"
                ])
                var containerNames: [ObjectId: String] = [:]
                for container in containers {
                    guard let containerId = container.objectId, let name = container["name"] as? String else { continue }
                    containerNames[containerId] = name
                }
                let devices = try Device.collection.find(projecting: [
                    "_id",
                    "name"
                ])
                var deviceNames: [ObjectId: String] = [:]
                for device in devices {
                    guard let deviceId = device.objectId, let name = device["name"] as? String else { continue }
                    deviceNames[deviceId] = name
                }
                
                let link = "/notifications?"
                let pageSkip = max(pageInfo.skip - (pageInfo.limit * 5), 0)
                var pages = try ((pageSkip + notifications.count(limitedTo: pageInfo.limit * 10, skipping: pageSkip)) / pageInfo.limit) + 1
                let startPage: Int
                if pages > 7 {
                    let firstPage = pageInfo.page - 3
                    let lastPage = pageInfo.page + 2
                    startPage = max(pageInfo.page - 3 - (lastPage > pages ? lastPage - pages : 0), 0)
                    pages = min(pages, lastPage - (firstPage < 0 ? firstPage : 0))
                } else {
                    startPage = 0
                }
                var pageData: String = ""
                for x in startPage..<pages {
                    pageData.append("<li class=\"page-item\(x == pageInfo.page - 1 ? " active" : "")\"><a class=\"page-link\" href=\"\(link)page=\(x + 1)\">\(x + 1)</a></li>")
                }
                var tableData: String = ""
                for notification in notifications {
                    let notificationId = try notification.extractObjectId()
                    let createdAt = try notification.extractDate("createdAt")
                    let typeValue = try notification.extractInteger("type")
                    guard let type = Notification.Kind(rawValue: typeValue) else {
                        throw ServerAbort(.notFound, reason: "type is required")
                    }
                    let name: String
                    if let deviceId = notification["deviceId"] as? ObjectId {
                        name = deviceNames[deviceId] ?? "Unknown"
                    } else if let containerId = notification["containerId"] as? ObjectId {
                        name = containerNames[containerId] ?? "Unknown"
                    } else if let hostDeviceId = notification["hostDeviceId"] as? ObjectId {
                        name = hostDeviceNames[hostDeviceId] ?? "Unknown"
                    } else {
                        name = "Unknown"
                    }
                    let string = "<tr onclick=\"location.href='/notifications/\(notificationId.hexString)'\"><td>\(name)</td><td>\(createdAt.longString)</td><td>\(type.description)</td></tr>"
                    tableData.append(string)
                }
                let context = TemplateData.dictionary([
                    "tableData": .string(tableData),
                    "pageData": .string(pageData),
                    "page": .int(pageInfo.page),
                    "nextPage": .string((pageInfo.page + 1 > pages ? "#" : "\(link)page=\(pageInfo.page + 1)")),
                    "prevPage": .string((pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)")),
                    "admin": .bool(authentication.permission.isAdmin)
                ])
                return promise.submit(try request.renderEncoded("notifications", context))
            }
        }
    }
    
    // MARK: GET :notificationId
    func getNotification(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let notificationId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let notification = try Notification.collection.findOne("_id" == notificationId) else {
                throw ServerAbort(.notFound, reason: "Notification not found")
            }
            if authentication.permission.isAdmin == false {
                let notificationUserId: ObjectId?
                if let hostDeviceId = notification["hostDeviceId"] as? ObjectId {
                    guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                        "_id",
                        "userId"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Host device not found")
                    }
                    notificationUserId = try hostDevice.extractObjectId("userId")
                } else if let containerId = notification["containerId"] as? ObjectId {
                    guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                        "_id",
                        "userId"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Container not found")
                    }
                    notificationUserId = try container.extractObjectId("userId")
                } else {
                    notificationUserId = nil
                }
                guard let userId = notificationUserId, authentication.userId == userId else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/notifications"))
                }
            }
            if request.jsonResponse {
                return promise.submit(try notification.makeResponse(request))
            } else {
                let typeValue = try notification.extractInteger("type")
                guard let type = Notification.Kind(rawValue: typeValue) else {
                    throw ServerAbort(.notFound, reason: "type is required")
                }
                let createdAt = try notification.extractDate("createdAt")
                
                var data: [String: TemplateData] = [
                    "type": .string(type.description),
                    "createdAt": .string(createdAt.longString),
                ]
                
                if let hostDeviceId = notification["hostDeviceId"] as? ObjectId {
                    guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                        "_id",
                        "name"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Host device not found")
                    }
                    let hostDeviceName = try hostDevice.extractString("name")
                    data["hostDevice"] = .string(hostDeviceName)
                }
                if let containerId = notification["containerId"] as? ObjectId {
                    guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                        "_id",
                        "name"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Container not found")
                    }
                    let containerName = try container.extractString("name")
                    data["container"] = .string(containerName)
                }
                if let deviceId = notification["deviceId"] as? ObjectId {
                    guard let device = try Device.collection.findOne("_id" == deviceId, projecting: [
                        "_id",
                        "name"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Device not found")
                    }
                    let deviceName = try device.extractString("name")
                    data["device"] = .string(deviceName)
                }
                if let temperature = notification["temperature"]?.doubleValue {
                    data["temperature"] = .double(temperature)
                }
                if let humidity = notification["humidity"]?.doubleValue {
                    data["humidity"] = .double(humidity)
                }
                
                let context = TemplateData.dictionary(data)
                return promise.submit(try request.renderEncoded("notification", context))
            }
        }
    }
    
    // MARK: DELETE :notificationId
    func deleteNotification(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let notificationId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let notification = try Notification.collection.findOne("_id" == notificationId) else {
                throw ServerAbort(.notFound, reason: "Notification not found")
            }
            if authentication.permission.isAdmin == false {
                let notificationUserId: ObjectId?
                if let hostDeviceId = notification["hostDeviceId"] as? ObjectId {
                    guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                        "_id",
                        "userId"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Host device not found")
                    }
                    notificationUserId = try hostDevice.extractObjectId("userId")
                } else if let containerId = notification["containerId"] as? ObjectId {
                    guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                        "_id",
                        "userId"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Container not found")
                    }
                    notificationUserId = try container.extractObjectId("userId")
                } else {
                    notificationUserId = nil
                }
                guard let userId = notificationUserId, authentication.userId == userId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/notifications"))
                }
            }
            
            guard try Notification.collection.remove("_id" == notificationId) == 1 else {
                throw ServerAbort(.notFound, reason: "Could not delete notification")
            }
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/notifications"))
        }
    }
}
