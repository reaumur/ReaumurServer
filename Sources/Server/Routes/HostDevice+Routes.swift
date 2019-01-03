//
//  HostDevice+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 9/9/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto

struct HostDeviceRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        let adminRouter = router.grouped(AdminAuthenticationMiddleware.self)
        
        protectedRouter.post(use: post)
        protectedRouter.delete(ObjectId.parameter, use: deleteHostDevice)
        protectedRouter.get(ObjectId.parameter, use: getHostDevice)
        protectedRouter.post(ObjectId.parameter, use: postHostDevice)
        protectedRouter.get(ObjectId.parameter, "sourceCode", use: getHostDeviceSourceCode)
        router.post(ObjectId.parameter, "ping", use: postHostDevicePing)
        protectedRouter.post(ObjectId.parameter, "flash", use: postHostDeviceFlash)
        protectedRouter.post("order", use: postOrder)
        protectedRouter.post(ObjectId.parameter, "devices", "order", use: postHostDeviceDevicesOrder)
        protectedRouter.post(ObjectId.parameter, "devices", use: postHostDeviceDevices)
        router.post(ObjectId.parameter, "devices", "register", use: postHostDeviceDevicesRegister)
        router.post(ObjectId.parameter, "logs", use: postHostDeviceLogs)
        protectedRouter.get(ObjectId.parameter, "logs", use: getHostDeviceLogs)
        protectedRouter.get(use: get)
        adminRouter.post(ObjectId.parameter, "publishEvent", use: postHostDevicePublishEvent)
        protectedRouter.post(ObjectId.parameter, "forceUpdate", use: postHostDeviceForceUpdate)
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            guard authentication.permission != .readOnly else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
            }
            struct FormData: Decodable {
                let name: String
                let deviceId: String
                let type: HostDevice.ParticleDeviceType
                let updateInterval: Int?
                let updateLedPin: Device.HostDevicePin?
            }
            let formData = try request.content.syncDecode(FormData.self)
            let hostDevice = try HostDevice.create(name: formData.name, deviceId: formData.deviceId, type: formData.type, updateLedPin: formData.updateLedPin ?? .d7, updateInterval: formData.updateInterval ?? 1, userId: authentication.userId)
            let hostDeviceId = try hostDevice.extractObjectId()
            
            if request.jsonResponse {
                return promise.submit(try hostDevice.makeResponse(request))
            }
            return promise.succeed(result: request.serverRedirect(to: "/hostDevices/\(hostDeviceId.hexString)"))
        }
    }
    
    // MARK: DELETE :hostDeviceId
    func deleteHostDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                "_id",
                "userId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try hostDevice.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
                }
            }
            try HostDeviceRouter.delete(hostDeviceId: hostDeviceId)
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/hostDevices"))
        }
    }
    
    static func delete(hostDeviceId: ObjectId) throws {
        let devices = try Device.collection.find("hostDeviceId" == hostDeviceId, projecting: [
            "_id"
        ])
        var containerIds: Set<ObjectId> = []
        for device in devices {
            if let containerId = device["containerId"] as? ObjectId {
                containerIds.insert(containerId)
            }
        }
        
        try Device.collection.remove("hostDeviceId" == hostDeviceId)
        try Log.collection.remove("hostDeviceId" == hostDeviceId)
        
        guard try HostDevice.collection.remove("_id" == hostDeviceId) == 1 else {
            throw ServerAbort(.notFound, reason: "Could not delete host device")
        }
        for containerId in containerIds {
            BrewContainer.updateDevices(containerId)
        }
    }
    
    // MARK: GET :hostDeviceId
    func getHostDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try hostDevice.extractObjectId("userId")
                guard authentication.userId == objectUserId else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
                }
            }
            
            if request.jsonResponse {
                return promise.submit(try hostDevice.makeResponse(request))
            } else {
                let pageInfo = request.pageInfo
                let devices = try Device.collection.find("hostDeviceId" == hostDeviceId, sortedBy: ["order": .ascending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
                var data = try Device.tableData(pageInfo: pageInfo, authentication: authentication, devices: devices)
                
                let hostDeviceUserId = try hostDevice.extractObjectId("userId")
                guard let user = try User.collection.findOne("_id" == hostDeviceUserId, projecting: [
                    "_id",
                    "email"
                ]) else {
                    throw ServerAbort(.notFound, reason: "user is required")
                }
                let hostDeviceUserEmail = try user.extractString("email")
                
                let typeValue = try hostDevice.extractInteger("type")
                guard let type = HostDevice.ParticleDeviceType(rawValue: typeValue) else {
                    throw ServerAbort(.notFound, reason: "type is required")
                }
                let needsUpdate = try hostDevice.extractBoolean("needsUpdate")
                let offline = hostDevice["offline"] as? Bool ?? false
                let updatedAt = try hostDevice.extractDate("updatedAt").longString
                let lastFlashed = (hostDevice["lastFlashedDate"] as? Date)?.longString ?? "Never"
                let lastPinged = (hostDevice["pingedAt"] as? Date)?.longString ?? "Never"
                
                var typeData = ""
                for type in Device.DeviceType.userCreatableDeviceTypes {
                    let string = "<option value=\(type.rawValue)>\(type.description)</option>"
                    typeData.append(string)
                }
                let hostPinDevices = try Device.collection.find("hostDeviceId" == hostDeviceId, projecting: [
                    "hostPin"
                ])
                var availablePins = Device.HostDevicePin.availablePins(particleDeviceType: type)
                for device in hostPinDevices {
                    guard let hostPinValue = device["hostPin"]?.intValue, let hostPin = Device.HostDevicePin(rawValue: hostPinValue) else { continue }
                    availablePins.remove(hostPin)
                }
                if let updateLedPinValue = hostDevice["updateLedPin"]?.intValue, let updateLedPin = Device.HostDevicePin(rawValue: updateLedPinValue) {
                    data["updateLedPin"] = .string(updateLedPin.description)
                    availablePins.remove(updateLedPin)
                }
                var pinData = ""
                if availablePins.isEmpty {
                    pinData = "<option value=\"\">No Available Pins</option>"
                } else {
                    let sortedPins = Array(availablePins).sorted(by: {$0.rawValue < $1.rawValue})
                    for hostDevicePin in sortedPins {
                        let string = "<option value=\(hostDevicePin.rawValue)>\(hostDevicePin.description)</option>"
                        pinData.append(string)
                    }
                }
                
                data["userEmail"] = .string(hostDeviceUserEmail)
                data["pinData"] = .string(pinData)
                data["typeData"] = .string(typeData)
                data["hostDeviceId"] = .string(hostDeviceId.hexString)
                data["name"] = .string(try hostDevice.extract("name") as String)
                data["deviceId"] = .string(try hostDevice.extract("deviceId") as String)
                data["deviceType"] = .string(type.description)
                data["needsUpdate"] = .string("<span class=\"badge badge-\((needsUpdate ? "danger" : "success"))\">\((needsUpdate ? "Yes" : "No"))</span>")
                data["offline"] = .string("<span class=\"badge badge-\((offline ? "danger" : "success"))\">\((offline ? "Yes" : "No"))</span>")
                data["updatedAt"] = .string(updatedAt)
                data["lastFlashed"] = .string(lastFlashed)
                data["lastPinged"] = .string(lastPinged)
                data["updateInterval"] = .int(try hostDevice.extractInteger("updateInterval"))
                
                let context = TemplateData.dictionary(data)
                return promise.submit(try request.renderEncoded("hostDevice", context))
            }
        }
    }
    
    // MARK: POST :hostDeviceId
    func postHostDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                "_id",
                "userId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try hostDevice.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
                }
            }
            struct FormData: Decodable {
                let action: String?
                let name: String?
                let updateInterval: Int?
                let updateLedPin: Device.HostDevicePin?
            }
            let formData = try request.content.syncDecode(FormData.self)
            if formData.action == "delete" {
                try HostDeviceRouter.delete(hostDeviceId: hostDeviceId)
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/hostDevices"))
            } else if formData.action == "flash" {
                guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId) else {
                    throw ServerAbort(.notFound, reason: "Host device not found")
                }
                return try HostDevice.flash(request: request, hostDeviceId: hostDeviceId, hostDevice: hostDevice, promise: promise)
            } else if formData.action == "update" {
                return try HostDevice.publishEvent(request: request, eventName: "forceUpdate", redirect: "/hostDevices/\(hostDeviceId.hexString)", promise: promise)
            } else if formData.action == "firmware" {
                return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/hostDevices/\(hostDeviceId.hexString)/sourceCode"))
            }
            var update: Document = [:]
            if let name = formData.name {
                update["name"] = name
            }
            if let updateInterval = formData.updateInterval {
                update["updateInterval"] = updateInterval
                update["needsUpdate"] = true
            }
            if let updateLedPin = formData.updateLedPin {
                update["updateLedPin"] = updateLedPin.rawValue
                update["needsUpdate"] = true
            }
            guard update.count > 0 else {
                guard let document = try HostDevice.collection.findOne("_id" == hostDeviceId) else {
                    throw ServerAbort(.notFound, reason: "Host device not found")
                }
                if request.jsonResponse {
                    return promise.submit(try document.makeResponse(request))
                }
                return promise.succeed(result: request.serverRedirect(to: "/hostDevices"))
            }
            let document = try HostDevice.collection.findAndUpdate("_id" == hostDeviceId, with: ["$set": update], upserting: false, returnedDocument: .new)
            if request.jsonResponse {
                return promise.submit(try document.makeResponse(request))
            }
            return promise.succeed(result: request.serverRedirect(to: "/hostDevices/\(hostDeviceId.hexString)"))
        }
    }
    
    // MARK: GET :hostDeviceId/sourceCode
    func getHostDeviceSourceCode(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try hostDevice.extractObjectId("userId")
                guard authentication.userId == objectUserId else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
                }
            }
            let sourceCode = try HostDevice.sourceCode(hostDevice, sharedContainer: request.sharedContainer)
            return promise.succeed(result: ServerResponse.string(sourceCode))
        }
    }
    
    // MARK: POST :hostDeviceId/ping
    func postHostDevicePing(_ request: Request) throws -> ServerResponse {
        DispatchQueue.global().async {
            do {
                let hostDeviceId = try request.parameters.next(ObjectId.self)
                let pingedAt = Date()
                guard var hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId) else {
                    throw ServerAbort(.notFound, reason: "Device not found")
                }
                let userId = try hostDevice.extractObjectId("userId")
                guard try HostDevice.collection.update("_id" == hostDeviceId, to: ["$set": ["pingedAt": pingedAt, "offline": false]], upserting: false, multiple: false) > 0 else {
                    throw ServerAbort(.notFound, reason: "Host device not found")
                }
                if hostDevice["offline"] as? Bool == true {
                    try Log.create(type: .deviceOnline, hostDeviceId: hostDeviceId)
                    Notification.send(userId: userId, hostDevice: hostDevice, kind: .backOnline, date: pingedAt)
                }
                SocketProvider.shared.send(socketFrameHolder: HostDeviceFrame(objectId: hostDeviceId, updatedAt: nil, pingedAt: pingedAt, offline: false).socketFrameHodler, userId: userId)
            } catch let error {
                Logger.error("Host Device Ping Error: \(error)")
            }
        }
        return request.serverStatus(status: .ok)
    }
    
    // MARK: POST :hostDeviceId/flash
    func postHostDeviceFlash(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try hostDevice.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
                }
            }
            return try HostDevice.flash(request: request, hostDeviceId: hostDeviceId, hostDevice: hostDevice, promise: promise)
        }
    }
    
    // MARK: POST order
    func postOrder(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceIdStrings = try request.content.syncGet([String].self, at: "objectIds")
            var hostDeviceIds: [ObjectId] = []
            for hostDeviceIdString in hostDeviceIdStrings {
                hostDeviceIds.append(try ObjectId(hostDeviceIdString))
            }
            let authentication = try request.authentication()
            guard authentication.permission != .readOnly else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
            }
            let query: Query? = (authentication.permission.isAdmin ? nil : ("userId" == authentication.userId))
            let hostDevices = try HostDevice.collection.find(query, sortedBy: ["order": .ascending], projecting: [
                "_id",
                "order"
            ])
            var last = hostDeviceIds.count
            var updates: [(filter: Query, to: Document, upserting: Bool, multiple: Bool)] = []
            for hostDevice in hostDevices {
                guard let hostDeviceId = hostDevice.objectId else { continue }
                let order: Int
                if let index = hostDeviceIds.index(of: hostDeviceId) {
                    order = hostDeviceIds.distance(from: hostDeviceIds.startIndex, to: index)
                } else {
                    order = last
                    last += 1
                }
                updates.append((filter: "_id" == hostDeviceId, to: ["$set": ["order": order]], upserting: false, multiple: false))
            }
            guard updates.count > 0 else {
                throw ServerAbort(.notFound, reason: "No host devices to update")
            }
            try HostDevice.collection.update(bulk: updates, stoppingOnError: true)
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/hostDevices"))
        }
    }
    
    // MARK: POST :hostDeviceId/devices/order
    func postHostDeviceDevicesOrder(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let deviceIdStrings = try request.content.syncGet([String].self, at: "objectIds")
            var deviceIds: [ObjectId] = []
            for deviceIdString in deviceIdStrings {
                deviceIds.append(try ObjectId(deviceIdString))
            }
            let authentication = try request.authentication()
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                "_id",
                "userId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try hostDevice.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
                }
            }
            let devices = try Device.collection.find("hostDeviceId" == hostDeviceId, sortedBy: ["order": .ascending], projecting: [
                "_id",
                "order"
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
                updates.append((filter: "_id" == deviceId, to: ["$set": ["order": order]], upserting: false, multiple: false))
            }
            guard updates.count > 0 else {
                throw ServerAbort(.notFound, reason: "No devices to update")
            }
            try Device.collection.update(bulk: updates, stoppingOnError: true)
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/hostDevices"))
        }
    }
    
    // MARK: POST :hostDeviceId/devices/register
    func postHostDeviceDevicesRegister(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            struct FormData: Decodable {
                let deviceId: String
                let oneWireType: Device.OneWireDeviceType
                let assigned: Bool
                let temperature: Double
            }
            let formData: FormData
            if let queryData = try? request.query.decode(FormData.self) {
                formData = queryData
            } else {
                formData = try request.content.syncDecode(FormData.self)
            }
            
            guard try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                "_id"
            ]) != nil else {
                throw ServerAbort(.notFound, reason: "Host Deivce not found")
            }
            if var device = try Device.collection.findOne("hostDeviceId" == hostDeviceId && "deviceId" == formData.deviceId) {
                guard let deviceObjectId = device.objectId else {
                    throw ServerAbort(.notFound, reason: "Deivce object ID not found")
                }
                device["oneWireType"] = formData.oneWireType.rawValue
                device["lastTemperature"] = formData.temperature
                device["lastActionDate"] = Date()
                device["updatedAt"] = Date()
                device["assigned"] = formData.assigned
                try Device.collection.update("_id" == deviceObjectId, to: device)
            } else {
                let order: Int
                if let lastDevice = try Device.collection.findOne("hostDeviceId" == hostDeviceId, sortedBy: ["order": .descending]), let lastOrder = lastDevice["order"]?.intValue {
                    order = lastOrder + 1
                } else {
                    order = 0
                }
                let device: Document = [
                    "name": "New Device",
                    "deviceId": formData.deviceId,
                    "hostDeviceId": hostDeviceId,
                    "oneWireType": formData.oneWireType.rawValue,
                    "type": 1,
                    "lastTemperature": formData.temperature,
                    "lastActionDate": Date(),
                    "order": order,
                    "outsideTemperature": false,
                    "outsideContainerTemperature": false,
                    "offline": false,
                    "assigned": formData.assigned,
                    "updatedAt": Date(),
                    "notifications": true,
                    "useForControl": true,
                    "hostPin": 1,
                    "color": 1
                ]
                try Device.collection.insert(device)
            }
            
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/hostDevices"))
        }
    }
    
    // MARK: POST :hostDeviceId/logs
    func postHostDeviceLogs(_ request: Request) throws -> ServerResponse {
        DispatchQueue.global().async {
            do {
                let hostDeviceId = try request.parameters.next(ObjectId.self)
                struct FormData: Decodable {
                    let type: Log.LogType
                    let deviceId: String?
                    let objectId: ObjectId?
                    let mode: Int?
                    let found: Bool?
                    let address: String?
                    let message: String?
                    let temperature: Double?
                }
                let formData: FormData
                if let queryData = try? request.query.decode(FormData.self) {
                    formData = queryData
                } else {
                    formData = try request.content.syncDecode(FormData.self)
                }
                guard try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                    "_id"
                ]) != nil else {
                    throw ServerAbort(.notFound, reason: "Host deivce not found")
                }
                var log: Document = [
                    "type": formData.type.rawValue,
                    "hostDeviceId": hostDeviceId,
                    "createdAt": Date()
                ]
                if let deviceId = formData.deviceId {
                    guard let device = try Device.collection.findOne("_id" == deviceId, projecting: [
                        "_id",
                        "name",
                        "hostDeviceId"
                    ]) else {
                        throw ServerAbort(.notFound, reason: "Deivce not found")
                    }
                    log["deviceId"] = deviceId
                    log["hostDeviceId"] = try device.extractObjectId("hostDeviceId")
                }
                if formData.type == .forceModeReceived {
                    let objectId = try formData.objectId.unwrapped("objectId")
                    let mode = try formData.mode.unwrapped("mode")
                    let found = try formData.found.unwrapped("found")
                    if try Device.collection.findOne("_id" == objectId, projecting: [
                        "_id"
                    ]) != nil {
                        log["deviceId"] = objectId
                    } else if try BrewContainer.collection.findOne("_id" == objectId, projecting: [
                        "_id"
                    ]) != nil {
                        log["containerId"] = objectId
                    } else {
                        throw ServerAbort(.notFound, reason: "Invalid objectId")
                    }
                    log["mode"] = mode
                    log["found"] = found
                }
                if let address = formData.address {
                    if log["deviceId"] == nil, let device = try Device.collection.findOne("deviceId" == address, projecting: [
                        "_id"
                    ]) {
                        log["deviceId"] = try device.extractObjectId()
                    }
                    log["address"] = address
                }
                if let message = formData.message {
                    log["message"] = message
                }
                if let temperature = formData.temperature, temperature != -100 {
                    log["temperature"] = temperature
                }
                
                try Log.collection.insert(log)
            } catch let error {
                Logger.error("Host Device Log Error: \(error)")
            }
        }
        return request.serverStatus(status: .ok)
    }
    
    // MARK: POST :hostDeviceId/devices
    func postHostDeviceDevices(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            struct FormData: Decodable {
                let name: String
                let type: Device.DeviceType
                let hostPin: Device.HostDevicePin
                let notifications: Bool?
                let cycleTimeLimit: Int?
                let activeLow: Bool?
                let backup: Bool?
                let color: Device.Color?
                let useForControl: Bool?
                
            }
            let formData = try request.content.syncDecode(FormData.self)
            
            guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                "_id",
                "userId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Host device not found")
            }
            if authentication.permission.isAdmin == false {
                let objectUserId = try hostDevice.extractObjectId("userId")
                guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
                }
            }
            
            let lastDevice = try Device.collection.findOne("hostDeviceId" == hostDeviceId, sortedBy: ["order": .descending], projecting: [
                "_id",
                "order"
            ])
            let order = (lastDevice?["order"]?.intValue ?? -1) + 1
            
            var device: Document = [
                "name": formData.name,
                "outsideTemperature": false,
                "assigned": false,
                "updatedAt": Date(),
                "type": formData.type.rawValue,
                "hostPin": formData.hostPin.rawValue,
                "hostDeviceId": hostDeviceId,
                "notifications": formData.notifications ?? true,
                "order": order,
                "offline": true,
                "homeKitHidden": false
            ]
            
            if formData.type.isSwitchDevice {
                device["cycleTimeLimit"] = formData.cycleTimeLimit ?? 0
                device["activeLow"] = formData.activeLow ?? false
            }
            if formData.type.isTemperatureControlDevice {
                device["backup"] = formData.backup ?? false
            } else {
                device["color"] = formData.color?.rawValue ?? 1
            }
            if formData.type.isTemperatureSensorDevice {
                device["useForControl"] = formData.useForControl ?? true
            }
            if formData.type.isOneWireDevice {
                device["oneWireType"] = 2
                device["deviceId"] = formData.name.collapseWhitespace.lowercased()
            }
            
            guard let deviceId = try Device.collection.insert(device) as? ObjectId else {
                throw ServerAbort(.internalServerError, reason: "Could not create device")
            }
            device["_id"] = deviceId
            
            if request.jsonResponse {
                return promise.submit(try device.makeResponse(request))
            }
            return promise.succeed(result: request.serverRedirect(to: "/hostDevices/\(hostDeviceId.hexString)"))
        }
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            let pageInfo = request.pageInfo
            let query: Query? = (authentication.permission.isAdmin ? nil : ("userId" == authentication.userId))
            let hostDevices = try HostDevice.collection.find(query, sortedBy: ["order": .ascending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try hostDevices.makeResponse(request))
            } else {
                let link = "/hostDevices?"
                var pages = try (hostDevices.count() / pageInfo.limit) + 1
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
                for hostDevice in hostDevices {
                    let hostDeviceId = try hostDevice.extractObjectId()
                    let name = try hostDevice.extractString("name")
                    let typeValue = try hostDevice.extractInteger("type")
                    let pingedAt = (hostDevice["pingedAt"] as? Date)?.longString ?? "Never"
                    let lastFlashed = (hostDevice["lastFlashedDate"] as? Date)?.longString ?? "Never"
                    let updateInterval = try hostDevice.extractInteger("updateInterval")
                    let needsUpdate = try hostDevice.extractBoolean("needsUpdate")
                    guard let type = HostDevice.ParticleDeviceType(rawValue: typeValue) else {
                        throw ServerAbort(.notFound, reason: "type is required")
                    }
                    let badge = (needsUpdate ? "danger" : "success")
                    let string = "<tr onclick=\"location.href='/hostDevices/\(hostDeviceId.hexString)'\"><td>\(name)</td><td>\(type.description)</td><td>\(pingedAt)</td><td>\(lastFlashed)</td><td>\(updateInterval.numberString ?? String(updateInterval))</td><td><span class=\"badge badge-\(badge)\">\((needsUpdate ? "Yes" : "No"))</span></td></tr>"
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
                return promise.submit(try request.renderEncoded("hostDevices", context))
            }
        }
    }
    
    // MARK: POST :hostDeviceId/publishEvent
    func postHostDevicePublishEvent(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            struct FormData: Decodable {
                let eventName: String
                let ttl: Int?
                let data: String?
                let isPrivate: Bool?
            }
            let formData = try request.content.syncDecode(FormData.self)
            return try HostDevice.publishEvent(request: request, eventName: formData.eventName, ttl: formData.ttl ?? 1800, data: formData.data, isPrivate: formData.isPrivate, redirect: "/hostDevices/\(hostDeviceId.hexString)", promise: promise)
        }
    }
    
    // MARK: POST :hostDeviceId/forceUpdate
    func postHostDeviceForceUpdate(_ request: Request) throws -> Future<ServerResponse> {
        let hostDeviceId = try request.parameters.next(ObjectId.self)
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            guard try authentication.canAccess(hostDeviceId: hostDeviceId) else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
            }
            try HostDevice.publishEvent(request: request, eventName: "forceUpdate", data: nil, redirect: "/hostDevices/\(hostDeviceId.hexString)", promise: promise)
        }
    }
    
    // MARK: GET :hostDeviceId/logs
    func getHostDeviceLogs(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let pageInfo = request.pageInfo
            let hostDeviceId = try request.parameters.next(ObjectId.self)
            let filteredType = try? request.query.get(at: "type") as Int
            let authentication = try request.authentication()
            guard try authentication.canAccess(hostDeviceId: hostDeviceId) else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/hostDevices"))
            }
            let query: Query
            if let filteredType = filteredType {
                query = "hostDeviceId" == hostDeviceId && "type" == filteredType
            } else {
                query = "hostDeviceId" == hostDeviceId
            }
            let logs = try Log.collection.find(query, sortedBy: ["createdAt": .descending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            return promise.submit(try logs.makeResponse(request))
        }
    }
}
