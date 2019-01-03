//
//  Container+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 9/19/17.
//

import Foundation
import Vapor
import MongoKitten

struct BrewContainerRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        protectedRouter.get(use: get)
        protectedRouter.post(use: post)
        protectedRouter.get(ObjectId.parameter, use: getContainer)
        protectedRouter.delete(ObjectId.parameter, use: deleteContainer)
        protectedRouter.post(ObjectId.parameter, "devices", ObjectId.parameter, use: postContainerDevice)
        protectedRouter.delete(ObjectId.parameter, "devices", ObjectId.parameter, use: deleteContainerDevice)
        protectedRouter.post("order", use: postOrder)
        protectedRouter.post(ObjectId.parameter, use: postContainer)
        protectedRouter.post(ObjectId.parameter, "devices", "order", use: postContainerDevicesOrder)
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let pageInfo = request.pageInfo
            let query: Query? = (authentication.permission.isAdmin ? nil : ("userId" == authentication.userId))
            let containers = try BrewContainer.collection.find(query, sortedBy: ["order": .ascending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try containers.makeResponse(request))
            } else {
                let link = "/containers?"
                var pages = try (containers.count() / pageInfo.limit) + 1
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
                for container in containers {
                    let containerId = try container.extractObjectId()
                    let name = try container.extractString("name")
                    let updatedAt = try container.extractDate("updatedAt")
                    let isHeating = try container.extractBoolean("isHeating")
                    let isCooling = try container.extractBoolean("isCooling")
                    let fanActive = try container.extractBoolean("fanActive")
                    let averageTemperature = container["averageTemperature"]?.doubleValue
                    let wantedHeatTemperature = container["wantedHeatTemperature"]?.doubleValue
                    let wantedCoolTemperature = container["wantedCoolTemperature"]?.doubleValue
                    let badge: String
                    let status: String
                    let statusCount = isHeating.integerValue + isCooling.integerValue + fanActive.integerValue
                    if statusCount >= 2 {
                        badge = "dark"
                        if statusCount == 3 {
                            status = "Heating/Cooling/Fan On"
                        } else if isHeating && isCooling {
                            status = "Heating/Cooling"
                        } else if isHeating {
                            status = "Heating/Fan On"
                        } else {
                            status = "Cooling/Fan On"
                        }
                    } else if isHeating {
                        badge = "danger"
                        status = "Heating"
                    } else if isCooling {
                        badge = "primary"
                        status = "Cooling"
                    } else if fanActive {
                        badge = "dark"
                        status = "Fan On"
                    } else {
                        badge = "light"
                        status = "None"
                    }
                    let string = "<tr onclick=\"location.href='/containers/\(containerId.hexString)'\"><td>\(name)</td><td>\(updatedAt.longString)</td><td><span class=\"badge badge-\(badge)\">\(status)</span></td><td>\(Double.temperatureFromDouble(averageTemperature))</td><td>\(Double.temperatureFromDouble(wantedHeatTemperature))</td><td>\(Double.temperatureFromDouble(wantedCoolTemperature))</td></tr>"
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
                return promise.submit(try request.renderEncoded("containers", context))
            }
        }
    }
    
    // MARK: GET :containerId
    func getContainer(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let containerId = try request.parameters.next(ObjectId.self)
            guard let container = try BrewContainer.collection.findOne("_id" == containerId) else {
                throw ServerAbort(.notFound, reason: "Container not found")
            }
            if authentication.permission.isAdmin == false  {
                let objectUserId = try container.extractObjectId("userId")
                guard authentication.userId == objectUserId else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/containers"))
                }
            }
            if request.jsonResponse {
                return promise.submit(try container.makeResponse(request))
            } else {
                let pageInfo = request.pageInfo
                let devices = try Device.collection.find("containerId" == containerId, sortedBy: ["order": .ascending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
                var data = try Device.tableData(pageInfo: pageInfo, authentication: authentication, devices: devices, showContainer: false)
                
                let containerUserId = try container.extractObjectId("userId")
                guard let user = try User.collection.findOne("_id" == containerUserId, projecting: [
                    "_id",
                    "email"
                ]) else {
                    throw ServerAbort(.notFound, reason: "user is required")
                }
                let containerUserEmail = try user.extractString("email")
                
                let isHeating = try container.extractBoolean("isHeating")
                let isCooling = try container.extractBoolean("isCooling")
                let fanActive = try container.extractBoolean("fanActive")
                
                var statusData = ""
                statusData.append("<span class=\"badge badge-\((isHeating ? "danger" : "light"))\">\((isHeating ? "Heating" : "Not Heating"))</span>&nbsp;")
                statusData.append("<span class=\"badge badge-\((isCooling ? "primary" : "light"))\">\((isCooling ? "Cooling" : "Not Cooling"))</span>&nbsp;")
                statusData.append("<span class=\"badge badge-\((fanActive ? "dark" : "light"))\">\((fanActive ? "Fan Active" : "Fan Off"))</span>&nbsp;")
                
                let updatedAt = (try? container.extractDate("updatedAt"))?.longString ?? "Never"
                let lastActionDate = (try? container.extractDate("lastActionDate"))?.longString ?? "Never"
                
                let homeKitHidden = container["homeKitHidden"] as? Bool ?? false
                data[(homeKitHidden ? "homeKitHiddenEnabled" : "homeKitHiddenDisabled")] = .string("checked")
                
                let conflictActionValue = try container.extractInteger("conflictAction")
                guard let conflictAction = BrewContainer.ConflictActionType(rawValue: conflictActionValue) else {
                    throw ServerAbort(.notFound, reason: "type is required")
                }
                switch conflictAction {
                case .nothing: data["conflictDoNothingEnabled"] = .string("checked")
                case .cool: data["conflictCoolEnabled"] = .string("checked")
                case .heat: data["conflictHeatEnabled"] = .string("checked")
                }
                
                data["containerId"] = .string(containerId.hexString)
                data["name"] = .string(try container.extract("name") as String)
                data["userEmail"] = .string(containerUserEmail)
                data["updatedAt"] = .string(updatedAt)
                data["lastActionDate"] = .string(lastActionDate)
                data["statusData"] = .string(statusData)
                if let averageTemperature = container["averageTemperature"]?.doubleValue, let stringValue = Double.numberFormatter.string(for: averageTemperature) {
                    data["averageTemperature"] = .string(stringValue)
                }
                if let minTemperature = container["minTemperature"]?.doubleValue {
                    data["minTemperature"] = .double(minTemperature)
                }
                if let maxTemperature = container["maxTemperature"]?.doubleValue {
                    data["maxTemperature"] = .double(maxTemperature)
                }
                if let wantedHeatTemperature = container["wantedHeatTemperature"]?.doubleValue {
                    data["wantedHeatTemperature"] = .double(wantedHeatTemperature)
                    if let turnOnBelowHeatTemperature = container["turnOnBelowHeatTemperature"]?.doubleValue {
                        data["turnOnBelowHeatTemperature"] = .double(wantedHeatTemperature - turnOnBelowHeatTemperature)
                    }
                    if let turnOffAboveHeatTemperature = container["turnOffAboveHeatTemperature"]?.doubleValue {
                        data["turnOffAboveHeatTemperature"] = .double(wantedHeatTemperature + turnOffAboveHeatTemperature)
                    }
                }
                if let wantedCoolTemperature = container["wantedCoolTemperature"]?.doubleValue {
                    data["wantedCoolTemperature"] = .double(wantedCoolTemperature)
                    if let turnOnAboveCoolTemperature = container["turnOnAboveCoolTemperature"]?.doubleValue {
                        data["turnOnAboveCoolTemperature"] = .double(wantedCoolTemperature + turnOnAboveCoolTemperature)
                    }
                    if let turnOffBelowCoolTemperature = container["turnOffBelowCoolTemperature"]?.doubleValue {
                        data["turnOffBelowCoolTemperature"] = .double(wantedCoolTemperature - turnOffBelowCoolTemperature)
                    }
                }
                
                let context = TemplateData.dictionary(data)
                return promise.submit(try request.renderEncoded("container", context))
            }
        }
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            guard authentication.permission != .readOnly else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/containers"))
            }
            struct FormData: Decodable {
                let name: String
                let conflictAction: Int?
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            let lastContainer = try BrewContainer.collection.findOne(sortedBy: ["order": .descending], projecting: [
                "_id",
                "order"
            ])
            let order = (lastContainer?["order"]?.intValue ?? -1) + 1
            
            var container: Document = [
                "name": formData.name,
                "updatedAt": Date(),
                "order": order,
                "userId": authentication.userId,
                "conflictAction": formData.conflictAction ?? 0,
                "containsDevices": false,
                "containsControllers": false,
                "containsSensors": false,
                "isHeating": false,
                "isCooling": false,
                "fanActive": false,
                "homeKitHidden": false
            ]
            
            guard let containerId = try BrewContainer.collection.insert(container) as? ObjectId else {
                throw ServerAbort(.internalServerError, reason: "Could not create container")
            }
            container["_id"] = containerId
            
            if request.jsonResponse {
                return promise.submit(try container.makeResponse(request))
            }
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/containers/\(containerId.hexString)"))
        }
    }
    
    // MARK: DELETE
    func deleteContainer(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let containerId = try request.parameters.next(ObjectId.self)
            guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                "_id",
                "userId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Container not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try container.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/containers/\(containerId.hexString)"))
                }
            }
            return promise.succeed(result: try BrewContainerRouter.delete(reqest: request, containerId: containerId))
        }
    }
    
    static func delete(reqest: Request, containerId: ObjectId) throws -> ServerResponse {
        // TODO: Test
        let devices = try Device.collection.find("containerId" == containerId, projecting: [
            "_id"
        ])
        var updates: [(filter: Query, to: Document, upserting: Bool, multiple: Bool)] = []
        for device in devices {
            guard let deviceId = device.objectId else { continue }
            updates.append((filter: "_id" == deviceId, to: ["$unset": ["containerId": 1, "containerOrder": 1]], upserting: false, multiple: false))
        }
        if updates.count > 0 {
            guard try BrewContainer.collection.update(bulk: updates, stoppingOnError: true) == updates.count else {
                throw ServerAbort(.notFound, reason: "Could not remove devices from container")
            }
        }
        
        HomeKitProvider.shared.removeContainer(forId: containerId)
        guard try BrewContainer.collection.remove("_id" == containerId) == 1 else {
            throw ServerAbort(.notFound, reason: "Could not delete container")
        }
        
        return reqest.serverStatusRedirect(status: .ok, to: "/containers")
    }
    
    // MARK: POST :containerId/:deviceId
    func postContainerDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let containerId = try request.parameters.next(ObjectId.self)
            let deviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            return promise.submit(try BrewContainer.addDevice(containerId: containerId, deviceId: deviceId, authentication: authentication).makeResponse(request))
        }
    }
    
    // MARK: DELETE :containerId/:deviceId
    func deleteContainerDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            _ = try request.parameters.next(ObjectId.self)
            let deviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            return promise.submit(try BrewContainer.removeDevice(deviceId: deviceId, authentication: authentication).makeResponse(request))
        }
    }
    
    // MARK: POST order
    func postOrder(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let containerIdStrings = try request.content.syncGet([String].self, at: "objectIds")
            var containerIds: [ObjectId] = []
            for containerIdString in containerIdStrings {
                containerIds.append(try ObjectId(containerIdString))
            }
            let authentication = try request.authentication()
            guard authentication.permission != .readOnly else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/containers"))
            }
            let query: Query? = (authentication.permission.isAdmin ? nil : ("userId" == authentication.userId))
            let containers = try BrewContainer.collection.find(query, sortedBy: ["order": .ascending], projecting: [
                "_id",
                "order"
            ])
            var last = containerIds.count
            var updates: [(filter: Query, to: Document, upserting: Bool, multiple: Bool)] = []
            for container in containers {
                guard let containerId = container.objectId else { continue }
                let order: Int
                if let index = containerIds.index(of: containerId) {
                    order = containerIds.distance(from: containerIds.startIndex, to: index)
                } else {
                    order = last
                    last += 1
                }
                updates.append((filter: "_id" == containerId, to: ["$set": ["order": order]], upserting: false, multiple: false))
            }
            guard updates.count > 0 else {
                throw ServerAbort(.notFound, reason: "No containers to update")
            }
            try BrewContainer.collection.update(bulk: updates, stoppingOnError: true)
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/containers"))
        }
    }
    
    struct TemperatureData: Codable {
        var action: String?
        var name: String?
        var homeKitHidden: Bool?
        var conflictAction: Int?
        var minTemperature: Double?
        var turnOnBelowHeatTemperature: Double?
        var turnOnBelowHeatTemperatureValue: Double?
        var wantedHeatTemperature: Double?
        var turnOffAboveHeatTemperature: Double?
        var turnOffAboveHeatTemperatureValue: Double?
        var turnOffBelowCoolTemperature: Double?
        var turnOffBelowCoolTemperatureValue: Double?
        var wantedCoolTemperature: Double?
        var turnOnAboveCoolTemperature: Double?
        var turnOnAboveCoolTemperatureValue: Double?
        var maxTemperature: Double?
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TemperatureData.CodingKeys.self)
            action = try? container.decode(String.self, forKey: .action)
            name = try? container.decode(String.self, forKey: .name)
            homeKitHidden = try? container.decode(Bool.self, forKey: .homeKitHidden)
            conflictAction = try? container.decode(Int.self, forKey: .conflictAction)
            minTemperature = (try? container.decode(Double.self, forKey: .minTemperature))?.roundedValue
            turnOnBelowHeatTemperature = (try? container.decode(Double.self, forKey: .turnOnBelowHeatTemperature))?.roundedValue
            wantedHeatTemperature = (try? container.decode(Double.self, forKey: .wantedHeatTemperature))?.roundedValue
            turnOffAboveHeatTemperature = (try? container.decode(Double.self, forKey: .turnOffAboveHeatTemperature))?.roundedValue
            if let wantedHeatTemperature = wantedHeatTemperature {
                if let turnOnBelowHeatTemperatureValue = (try? container.decode(Double.self, forKey: .turnOnBelowHeatTemperatureValue))?.roundedValue, turnOnBelowHeatTemperatureValue < wantedHeatTemperature {
                    turnOnBelowHeatTemperature = (wantedHeatTemperature - turnOnBelowHeatTemperatureValue).roundedValue
                }
                if let turnOffAboveHeatTemperatureValue = (try? container.decode(Double.self, forKey: .turnOffAboveHeatTemperatureValue))?.roundedValue, turnOffAboveHeatTemperatureValue > wantedHeatTemperature {
                    turnOffAboveHeatTemperature = (turnOffAboveHeatTemperatureValue - wantedHeatTemperature).roundedValue
                }
            }
            turnOffBelowCoolTemperature = (try? container.decode(Double.self, forKey: .turnOffBelowCoolTemperature))?.roundedValue
            wantedCoolTemperature = (try? container.decode(Double.self, forKey: .wantedCoolTemperature))?.roundedValue
            turnOnAboveCoolTemperature = (try? container.decode(Double.self, forKey: .turnOnAboveCoolTemperature))?.roundedValue
            if let wantedCoolTemperature = wantedCoolTemperature {
                if let turnOffBelowCoolTemperatureValue = (try? container.decode(Double.self, forKey: .turnOffBelowCoolTemperatureValue))?.roundedValue, turnOffBelowCoolTemperatureValue < wantedCoolTemperature {
                    turnOffBelowCoolTemperature = (wantedCoolTemperature - turnOffBelowCoolTemperatureValue).roundedValue
                }
                if let turnOnAboveCoolTemperatureValue = (try? container.decode(Double.self, forKey: .turnOnAboveCoolTemperatureValue))?.roundedValue, turnOnAboveCoolTemperatureValue > wantedCoolTemperature {
                    turnOnAboveCoolTemperature = (turnOnAboveCoolTemperatureValue - wantedCoolTemperature).roundedValue
                }
            }
            maxTemperature = (try? container.decode(Double.self, forKey: .maxTemperature))?.roundedValue
            
            checkValues()
        }
        
        var hasTemperatureSettings: Bool {
            return wantedHeatTemperature != nil || wantedCoolTemperature != nil || minTemperature != nil || maxTemperature != nil
        }
        
        mutating func checkValues() {
            if wantedHeatTemperature != nil {
                if turnOnBelowHeatTemperature == nil {
                    turnOnBelowHeatTemperature = 0
                }
                if turnOffAboveHeatTemperature == nil {
                    turnOffAboveHeatTemperature = 0
                }
            } else {
                turnOnBelowHeatTemperature = nil
                turnOffAboveHeatTemperature = nil
            }
            if wantedCoolTemperature != nil {
                if turnOffBelowCoolTemperature == nil {
                    turnOffBelowCoolTemperature = 0
                }
                if turnOnAboveCoolTemperature == nil {
                    turnOnAboveCoolTemperature = 0
                }
            } else {
                turnOffBelowCoolTemperature = nil
                turnOnAboveCoolTemperature = nil
            }
            
            if let wantedHeatTemperature = wantedHeatTemperature,
                let turnOffAboveHeatTemperature = turnOffAboveHeatTemperature,
                let wantedCoolTemperature = wantedCoolTemperature,
                let turnOffBelowCoolTemperature = turnOffBelowCoolTemperature {
                
                let heatMaxTemperature = wantedHeatTemperature + turnOffAboveHeatTemperature
                let coolMinTemperature = wantedCoolTemperature - turnOffBelowCoolTemperature
                if heatMaxTemperature > coolMinTemperature {
                    let difference = heatMaxTemperature - coolMinTemperature
                    let split = Int(difference / 2)
                    let remainder = Int(difference.truncatingRemainder(dividingBy: 2))
                    self.wantedHeatTemperature = (wantedHeatTemperature - Double(split) - Double(remainder)).roundedValue
                    self.wantedCoolTemperature = (wantedCoolTemperature + Double(split)).roundedValue
                }
            }
            
            if let wantedHeatTemperature = wantedHeatTemperature, let turnOnBelowHeatTemperature = turnOnBelowHeatTemperature, let minTemperature = minTemperature {
                if wantedHeatTemperature - turnOnBelowHeatTemperature < minTemperature {
                    self.minTemperature = wantedHeatTemperature - turnOnBelowHeatTemperature - 1
                }
            }
            
            if let wantedCoolTemperature = wantedCoolTemperature, let turnOnAboveCoolTemperature = turnOnAboveCoolTemperature, let maxTemperature = maxTemperature {
                if wantedCoolTemperature + turnOnAboveCoolTemperature > maxTemperature {
                    self.maxTemperature = wantedCoolTemperature + turnOnAboveCoolTemperature + 1
                }
            }
        }
    }
    
    // MARK: POST :containerId
    func postContainer(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let containerId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                "_id",
                "userId",
                "name",
                "averageTemperature"
            ]) else {
                throw ServerAbort(.notFound, reason: "Container not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try container.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/containers"))
                }
            }
            let temperatureData = try request.content.syncDecode(TemperatureData.self)
            if temperatureData.action == "delete" {
                return promise.succeed(result: try BrewContainerRouter.delete(reqest: request, containerId: containerId))
            }
            var update: Document = [:]
            var unset: [String: Int] = [:]
            var hostDeviceNeedsUpdate = false
            var didUpdateTemperatures = false
            if let name = temperatureData.name {
                update["name"] = name
            }
            if let homeKitHidden = temperatureData.homeKitHidden {
                update["homeKitHidden"] = homeKitHidden
                if homeKitHidden {
                    HomeKitProvider.shared.removeContainer(forId: containerId)
                } else {
                    try? HomeKitProvider.shared.upsert(container: container)
                }
            }
            if let conflictActionValue = temperatureData.conflictAction, let conflictAction = BrewContainer.ConflictActionType(rawValue: conflictActionValue) {
                update["conflictAction"] = conflictAction.rawValue
                hostDeviceNeedsUpdate = true
            }
            if temperatureData.hasTemperatureSettings {
                didUpdateTemperatures = true
                if let minTemperature = temperatureData.minTemperature {
                    update["minTemperature"] = minTemperature.roundedValue
                } else {
                    unset["minTemperature"] = 1
                }
                if let turnOnBelowHeatTemperature = temperatureData.turnOnBelowHeatTemperature {
                    update["turnOnBelowHeatTemperature"] = turnOnBelowHeatTemperature.roundedValue
                } else {
                    unset["turnOnBelowHeatTemperature"] = 1
                }
                if let wantedHeatTemperature = temperatureData.wantedHeatTemperature {
                    update["wantedHeatTemperature"] = wantedHeatTemperature.roundedValue
                } else {
                    unset["wantedHeatTemperature"] = 1
                }
                if let turnOffAboveHeatTemperature = temperatureData.turnOffAboveHeatTemperature {
                    update["turnOffAboveHeatTemperature"] = turnOffAboveHeatTemperature.roundedValue
                } else {
                    unset["turnOffAboveHeatTemperature"] = 1
                }
                if let turnOffBelowCoolTemperature = temperatureData.turnOffBelowCoolTemperature {
                    update["turnOffBelowCoolTemperature"] = turnOffBelowCoolTemperature.roundedValue
                } else {
                    unset["turnOffBelowCoolTemperature"] = 1
                }
                if let wantedCoolTemperature = temperatureData.wantedCoolTemperature {
                    update["wantedCoolTemperature"] = wantedCoolTemperature.roundedValue
                } else {
                    unset["wantedCoolTemperature"] = 1
                }
                if let turnOnAboveCoolTemperature = temperatureData.turnOnAboveCoolTemperature {
                    update["turnOnAboveCoolTemperature"] = turnOnAboveCoolTemperature.roundedValue
                } else {
                    unset["turnOnAboveCoolTemperature"] = 1
                }
                if let maxTemperature = temperatureData.maxTemperature {
                    update["maxTemperature"] = maxTemperature.roundedValue
                } else {
                    unset["maxTemperature"] = 1
                }
            }
            
            if hostDeviceNeedsUpdate || didUpdateTemperatures {
                let devices = try Device.collection.find("containerId" == containerId, projecting: [
                    "_id",
                    "hostDeviceId"
                ])
                var hostDeviceIds: Set<ObjectId> = []
                for device in devices {
                    guard let hostDeviceId = device["hostDeviceId"] as? ObjectId else { continue }
                    hostDeviceIds.insert(hostDeviceId)
                }
                if hostDeviceIds.count > 0 {
                    _ = try HostDevice.collection.findAndUpdate(Query(aqt: AQT.in(key: "_id", in: Array(hostDeviceIds))), with: ["$set": ["needsUpdate": true]], upserting: false, returnedDocument: .new)
                }
            }
            guard update.count > 0 || unset.count > 0 else {
                guard let document = try BrewContainer.collection.findOne("_id" == containerId) else {
                    throw ServerAbort(.notFound, reason: "Container not found")
                }
                if request.jsonResponse {
                    return promise.submit(try document.makeResponse(request))
                }
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/containers"))
            }
            var query: Document = [:]
            if update.count > 0 {
                query["$set"] = update
            }
            if unset.count > 0 && didUpdateTemperatures {
                query["$unset"] = unset
            }
            let document = try BrewContainer.collection.findAndUpdate("_id" == containerId, with: query, upserting: false, returnedDocument: .new)
            
            if request.jsonResponse {
                return promise.submit(try document.makeResponse(request))
            }
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/containers/\(containerId.hexString)"))
        }
    }
    
    // MARK: POST :containerId/deivces/order
    func postContainerDevicesOrder(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let containerId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
                "_id",
                "userId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Container not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try container.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/containers"))
                }
            }
            let deviceIdStrings = try request.content.syncGet([String].self, at: "objectIds")
            var deviceIds: [ObjectId] = []
            for deviceIdString in deviceIdStrings {
                deviceIds.append(try ObjectId(deviceIdString))
            }
            let devices = try Device.collection.find("containerId" == containerId, sortedBy: ["containerOrder": .ascending], projecting: [
                "_id",
                "containerOrder"
            ])
            var last = deviceIds.count
            var updates: [(filter: Query, to: Document, upserting: Bool, multiple: Bool)] = []
            for device in devices {
                guard let deviceId = device.objectId else { continue }
                let order: Int
                if let index = deviceIds.index(of: deviceId) {
                    order = deviceIds.distance(from: deviceIds.startIndex, to: index)
                } else {
                    order = last
                    last += 1
                }
                updates.append((filter: "_id" == deviceId, to: ["$set": ["containerOrder": order]], upserting: false, multiple: false))
            }
            guard updates.count > 0 else {
                throw ServerAbort(.notFound, reason: "No devices to update")
            }
            Logger.info("Order: \(try Device.collection.update(bulk: updates, stoppingOnError: true))")
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/containers"))
        }
    }
}
