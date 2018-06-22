//
//  Log+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 10/13/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto

struct LogRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        protectedRouter.get(use: get)
        protectedRouter.get(ObjectId.parameter, use: getLog)
        protectedRouter.delete(ObjectId.parameter, use: deleteLog)
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let pageInfo = request.pageInfo
            let authentication = try request.authentication()
            let filteredType = try? request.query.get(at: "type") as Int
            let filteredDeviceId = try? request.query.get(at: "deviceId") as ObjectId
            let query: Query?
            var startQuery: Query?
            if let type = filteredType {
                if let currentQuery = startQuery {
                    startQuery = currentQuery && "type" == type
                } else {
                    startQuery = "type" == type
                }
            }
            if let deviceId = filteredDeviceId {
                if let currentQuery = startQuery {
                    startQuery = currentQuery && "deviceId" == deviceId
                } else {
                    startQuery = "deviceId" == deviceId
                }
            }
            
            if authentication.permission.isAdmin == false {
                let hostDevices = try HostDevice.collection.find("userId" == authentication.userId, projecting: [
                    "_id"
                ])
                var hostDeviceIds: Set<ObjectId> = []
                for hostDevice in hostDevices {
                    guard let hostDeviceId = hostDevice.objectId else { continue }
                    hostDeviceIds.insert(hostDeviceId)
                }
                if let startQuery = startQuery {
                    query = startQuery && Query(aqt: AQT.in(key: "hostDeviceId", in: Array(hostDeviceIds)))
                } else {
                    query = Query(aqt: AQT.in(key: "hostDeviceId", in: Array(hostDeviceIds)))
                }
            } else {
                query = startQuery
            }
            let logs = try Log.collection.find(query, sortedBy: ["createdAt": .descending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try logs.makeResponse(request))
            } else {
                var pageLink: String = ""
                if let type = filteredType {
                    pageLink += "&type=\(type)"
                }
                if let deviceId = filteredDeviceId {
                    pageLink += "&deviceId=\(deviceId.hexString)"
                }
                
                var typeData: String = "<option value=\"\"\(filteredType == nil ? "selected" : "")>All Logs</option>"
                for type in Log.LogType.allValues {
                    let string = "<option value=\"\(type.rawValue)\"\(type.rawValue == filteredType ? "selected" : "")>\(type.description)</option>"
                    typeData.append(string)
                }
                let link = "/logs?"
                
                let hostDeviceQuery: Query?
                if authentication.permission.isAdmin == false {
                    hostDeviceQuery = "userId" == authentication.userId
                } else {
                    hostDeviceQuery = nil
                }
                let hostDevices = try HostDevice.collection.find(hostDeviceQuery, projecting: [
                    "_id",
                    "name"
                ])
                var hostDeviceNames: [ObjectId: String] = [:]
                var hostDeviceIds: Set<ObjectId> = []
                for hostDevice in hostDevices {
                    guard let hostDeviceId = hostDevice.objectId, let name = hostDevice["name"] as? String else { continue }
                    hostDeviceNames[hostDeviceId] = name
                    hostDeviceIds.insert(hostDeviceId)
                }
                
                let deviceQuery: Query?
                if authentication.permission.isAdmin == false {
                    deviceQuery = Query(aqt: AQT.in(key: "hostDeviceId", in: Array(hostDeviceIds)))
                } else {
                    deviceQuery = nil
                }
                let devices = try Device.collection.find(deviceQuery, projecting: [
                    "_id",
                    "name"
                ])
                var deviceNames: [ObjectId: String] = [:]
                var deviceData: String = "<option value=\"\"\(filteredDeviceId == nil ? "selected" : "")>All Devices</option>"
                for device in devices {
                    guard let deviceId = device.objectId, let name = device["name"] as? String else { continue }
                    deviceNames[deviceId] = name
                    
                    let string = "<option value=\"\(deviceId.hexString)\"\(deviceId == filteredDeviceId ? "selected" : "")>\(name)</option>"
                    deviceData.append(string)
                }
                
                let pageSkip = max(pageInfo.skip - (pageInfo.limit * 5), 0)
                var pages = try ((pageSkip + logs.count(limitedTo: pageInfo.limit * 10, skipping: pageSkip)) / pageInfo.limit) + 1
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
                    pageData.append("<li class=\"page-item\(x == pageInfo.page - 1 ? " active" : "")\"><a class=\"page-link\" href=\"\(link)page=\(x + 1)\(pageLink)\">\(x + 1)</a></li>")
                }
                var tableData: String = ""
                for log in logs {
                    let logId = try log.extractObjectId()
                    let createdAt = try log.extractDate("createdAt")
                    let hostDeviceId = try log.extractObjectId("hostDeviceId")
                    let hostDeviceName = hostDeviceNames[hostDeviceId] ?? "Unknown"
                    let deviceName: String
                    if let deviceId = log["deviceId"] as? ObjectId {
                        deviceName = deviceNames[deviceId] ?? "None"
                    } else {
                        deviceName = "None"
                    }
                    let type = try log.extractLogType("type")
                    let string = "<tr onclick=\"location.href='/logs/\(logId.hexString)'\"><td>\(hostDeviceName)</td><td>\(createdAt.longString)</td><td>\(type.description)</td><td>\(deviceName)</td></tr>"
                    tableData.append(string)
                }
                let context = TemplateData.dictionary([
                    "tableData": .string(tableData),
                    "deviceData": .string(deviceData),
                    "typeData": .string(typeData),
                    "pageData": .string(pageData),
                    "page": .int(pageInfo.page),
                    "nextPage": .string((pageInfo.page + 1 > pages ? "#" : "\(link)page=\(pageInfo.page + 1)\(pageLink)")),
                    "prevPage": .string((pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)\(pageLink)")),
                    "admin": .bool(authentication.permission.isAdmin)
                ])
                return promise.submit(try request.renderEncoded("logs", context))
            }
        }
    }
    
    // MARK: GET :logId
    func getLog(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let logId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let log = try Log.collection.findOne("_id" == logId) else {
                throw ServerAbort(.notFound, reason: "Log not found")
            }
            if authentication.permission.isAdmin == false {
                let logUserId: ObjectId?
                if let hostDeviceId = log["hostDeviceId"] as? ObjectId {
                    guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                        "_id",
                        "userId"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Host device not found")
                    }
                    logUserId = try hostDevice.extractObjectId("userId")
                } else if let containerId = log["containerId"] as? ObjectId {
                    guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                        "_id",
                        "userId"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Container not found")
                    }
                    logUserId = try container.extractObjectId("userId")
                } else {
                    logUserId = nil
                }
                guard let userId = logUserId, authentication.userId == userId else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/logs"))
                }
            }
            if request.jsonResponse {
                return promise.submit(try log.makeResponse(request))
            } else {
                let type = try log.extractLogType("type")
                let createdAt = try log.extractDate("createdAt")
                
                var data: [String: TemplateData] = [
                    "type": .string(type.description),
                    "createdAt": .string(createdAt.longString),
                ]
                
                if let hostDeviceId = log["hostDeviceId"] as? ObjectId {
                    guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                        "_id",
                        "name"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Host device not found")
                    }
                    let hostDeviceName = try hostDevice.extractString("name")
                    data["hostDevice"] = .string(hostDeviceName)
                }
                if let containerId = log["containerId"] as? ObjectId {
                    guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                        "_id",
                        "name"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Container not found")
                    }
                    let containerName = try container.extractString("name")
                    data["container"] = .string(containerName)
                }
                if let deviceId = log["deviceId"] as? ObjectId {
                    guard let device = try Device.collection.findOne("_id" == deviceId, projecting: [
                        "_id",
                        "name"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Device not found")
                    }
                    let deviceName = try device.extractString("name")
                    data["device"] = .string(deviceName)
                }
                if let address = log["address"] as? String {
                    data["address"] = .string(address)
                }
                if let temperature = log["temperature"]?.doubleValue {
                    data["temperature"] = .double(temperature)
                }
                if let message = log["message"] as? String {
                    data["message"] = .string(message)
                }
                
                let context = TemplateData.dictionary(data)
                return promise.submit(try request.renderEncoded("log", context))
            }
        }
    }
    
    // MARK: DELETE :logId
    func deleteLog(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let logId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            if authentication.permission.isAdmin == false {
                guard let log = try Log.collection.findOne("_id" == logId, projecting: [
                    "_id",
                    "hostDeviceId"
                ]) else {
                    throw ServerAbort(.notFound, reason: "Log not found")
                }
                let hostDeviceId = try log.extractObjectId("hostDeviceId")
                guard try authentication.canAccess(hostDeviceId: hostDeviceId), authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/logs"))
                }
            }
            
            guard try Log.collection.remove("_id" == logId) == 1 else {
                throw ServerAbort(.notFound, reason: "Could not delete container")
            }
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/logs"))
        }
    }
}
