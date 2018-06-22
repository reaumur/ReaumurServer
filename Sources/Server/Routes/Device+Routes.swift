//
//  Device+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 8/2/17.
//

import Foundation
import Vapor
import MongoKitten

private struct InfluxQueryData: Codable {
    
    let lastSeconds: Int?
    let groupBySeconds: Int?
    let startDate: String?
    let endDate: String?
    
    var timeFilter: String {
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            return formatter
        }()
        if let lastSeconds = lastSeconds {
            return "time > now() - \(lastSeconds)s"
        } else if let startDateString = startDate, let startDateValue = Formatter.iso8601.date(from: startDateString) {
            if let endDateString = endDate, let endDateValue = Formatter.iso8601.date(from: endDateString) {
                return "time > '\(dateFormatter.string(from: startDateValue))' AND time < '\(dateFormatter.string(from: endDateValue))'"
            } else {
                return "time > '\(dateFormatter.string(from: startDateValue))'"
            }
        } else {
            return "time > now() - 24h"
        }
    }
    
    var groupBy: String {
        if let groupBySeconds = groupBySeconds {
            return "\(groupBySeconds)s"
        } else {
            return "1m"
        }
    }
}

struct DeviceRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        protectedRouter.get(use: get)
        protectedRouter.get(ObjectId.parameter, use: getDevice)
        protectedRouter.delete(ObjectId.parameter, use: deleteDevice)
        protectedRouter.post(ObjectId.parameter, use: postDevice)
        router.post(ObjectId.parameter, "action", use: postDeviceAction)
        protectedRouter.get(ObjectId.parameter, "logs", use: getDeviceLogs)
        protectedRouter.get(ObjectId.parameter, "temperatures", use: getDeviceTemperatures)
        protectedRouter.get(ObjectId.parameter, "cycles", use: getDeviceCycles)
        protectedRouter.get(ObjectId.parameter, "humidities", use: getDeviceHumidities)
        protectedRouter.post(ObjectId.parameter, "forceTemperature", use: postDeviceForceTemperature)
        protectedRouter.post(ObjectId.parameter, "forceMode", use: postDeviceForceMode)
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let pageInfo = request.pageInfo
            let authentication = try request.authentication()
            let query: Query?
            if authentication.permission.isAdmin == false {
                let hostDevices = try HostDevice.collection.find("userId" == authentication.userId, projecting: [
                    "_id"
                ])
                var hostDeviceIds: Set<ObjectId> = []
                for hostDevice in hostDevices {
                    guard let hostDeviceId = hostDevice.objectId else { continue }
                    hostDeviceIds.insert(hostDeviceId)
                }
                query = Query(aqt: AQT.in(key: "hostDeviceId", in: Array(hostDeviceIds)))
            } else {
                query = nil
            }
            let devices = try Device.collection.find(query, sortedBy: ["order": .ascending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            if request.jsonResponse {
                return promise.submit(try devices.makeResponse(request))
            } else {
                let data = try Device.tableData(pageInfo: pageInfo, authentication: authentication, devices: devices)
                let context = TemplateData.dictionary(data)
                return promise.submit(try request.renderEncoded("devices", context))
            }
        }
    }
    
    // MARK: GET :deviceId
    func getDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let deviceId = try request.parameters.next(ObjectId.self)
            guard let device = try Device.collection.findOne("_id" == deviceId) else {
                throw ServerAbort(.notFound, reason: "Device not found")
            }
            let authentication = try request.authentication()
            if authentication.permission.isAdmin == false {
                let hostDeviceId = try device.extractObjectId("hostDeviceId")
                guard try authentication.canAccess(hostDeviceId: hostDeviceId) else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
                }
            }
            
            if request.jsonResponse {
                return promise.submit(try device.makeResponse(request))
            } else {
                let containers = try BrewContainer.collection.find(projecting: [
                    "_id",
                    "name"
                ])
                let currentContainerId = device["containerId"] as? ObjectId
                var containerData: String = ""
                for container in containers {
                    guard let containerId = container.objectId, let name = container["name"] as? String else { continue }
                    let string = "<option value=\"\(containerId.hexString)\"\(containerId == currentContainerId ? "selected" : "")>\(name)</option>"
                    containerData.append(string)
                }
                if containerData.isEmpty {
                    containerData = "<option value=\"\">No Containers</option>"
                } else {
                    let string = "<option value=\"none\"\(currentContainerId == nil ? "selected" : "")>None</option>"
                    containerData.append(string)
                }
                
                let hostDeviceId = try device.extractObjectId("hostDeviceId")
                guard let hostDevice = try HostDevice.collection.findOne("_id" == hostDeviceId, projecting: [
                    "_id",
                    "name"
                ]) else {
                    throw ServerAbort(.notFound, reason: "Host Device not found")
                }
                let hostDeviceName = try hostDevice.extractString("name")
                
                let typeValue = try device.extractInteger("type")
                guard let type = Device.DeviceType(rawValue: typeValue) else {
                    throw ServerAbort(.notFound, reason: "type is required")
                }
                
                let assigned = try device.extractBoolean("assigned")
                let assignedData = "<span class=\"badge badge-\((assigned ? "success" : "danger"))\">\((assigned ? "Yes" : "No"))</span>"
                let offline = try device.extractBoolean("offline")
                let offlineData = "<span class=\"badge badge-\((offline ? "danger" : "success"))\">\((offline ? "Yes" : "No"))</span>"
                
                let updatedAt = (device["updatedAt"] as? Date)?.longString ?? "Never"
                let lastAction = (device["lastActionDate"] as? Date)?.longString ?? "None"
                
                var data: [String: TemplateData] = [
                    "objectId": .string(deviceId.hexString),
                    "name": .string(try device.extract("name") as String),
                    "type": .string(type.description),
                    "hostDevice": .string(hostDeviceName),
                    "containerData": .string(containerData),
                    "assigned": .string(assignedData),
                    "offline": .string(offlineData),
                    "updatedAt": .string(updatedAt),
                    "lastAction": .string(lastAction),
                    "admin": .bool(authentication.permission.isAdmin)
                ]
                if let deviceId = device["deviceId"] as? String {
                    data["deviceId"] = .string(deviceId)
                }
                if let hostPin = try? device.extractHostDevicePin("hostPin") {
                    data["hostPin"] = .string("<span class=\"badge badge-dark\">\(hostPin.description)</span>")
                }
                
                let notifications = try device.extract("notifications") as Bool
                data[(notifications ? "notificationsEnabled" : "notificationsDisabled")] = .string("checked")
                
                if let lastTemperature = device["lastTemperature"]?.doubleValue {
                    data["lastTemperature"] = .string("<span class=\"badge badge-dark\">\((Double.temperatureFromDouble(lastTemperature)))</span>")
                }
                if let lastHumidity = device["lastHumidity"]?.doubleValue {
                    data["lastHumidity"] = .string("<span class=\"badge badge-dark\">\((Double.humidityFromDouble(lastHumidity)))</span>")
                }
                if let turnedOn = device["turnedOn"] as? Bool {
                    let badge: String
                    if turnedOn {
                        badge = (type == .heater ? "danger" : "primary")
                    } else {
                        badge = "light"
                    }
                    data["turnedOn"] = .string("<span class=\"badge badge-\(badge)\">\((turnedOn ? "Turned On" : "Turned Off"))</span>")
                }
                if type.isSwitchDevice {
                    data["switch"] = .bool(true)
                    let cycleTimeLimit = try device.extractInteger("cycleTimeLimit")
                    data["cycleTimeLimit"] = .int(cycleTimeLimit)
                    let activeLow = try device.extract("activeLow") as Bool
                    data[(activeLow ? "activeLowEnabled" : "activeLowDisabled")] = .string("checked")
                }
                if type.isTemperatureControlDevice {
                    data["temperatureControl"] = .bool(true)
                    let backup = try device.extract("backup") as Bool
                    data[(backup ? "backupEnabled" : "backupDisabled")] = .string("checked")
                }
                if type.isTemperatureSensorDevice {
                    data["temperatureSensor"] = .bool(true)
                    if let minTemperature = device["minTemperature"] as? Double {
                        data["minTemperature"] = .double(minTemperature)
                    }
                    if let maxTemperature = device["maxTemperature"] as? Double {
                        data["maxTemperature"] = .double(maxTemperature)
                    }
                }
                if type.isTemperatureSwitchDevice {
                    data["temperatureSwitch"] = .bool(true)
                    let useForControl = try device.extract("useForControl") as Bool
                    data[(useForControl ? "useForControlEnabled" : "useForControlDisabled")] = .string("checked")
                }
                let context = TemplateData.dictionary(data)
                return promise.submit(try request.renderEncoded("device", context))
            }
        }
    }
    
    // MARK: DELETE :deviceId
    func deleteDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let deviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            guard let device = try Device.collection.findOne("_id" == deviceId, projecting: [
                "_id",
                "containerId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Device not found")
            }
            let containerId = device["containerId"] as? ObjectId
            if authentication.permission.isAdmin == false {
                let hostDeviceId = try device.extractObjectId("hostDeviceId")
                
                guard try authentication.canAccess(hostDeviceId: hostDeviceId), authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
                }
            }
            return promise.succeed(result: try DeviceRouter.delete(reqest: request, deviceId: deviceId, containerId: containerId))
        }
    }
    
    static func delete(reqest: Request, deviceId: ObjectId, containerId: ObjectId?) throws -> ServerResponse {
        try Log.collection.remove("deviceId" == deviceId)
        
        guard try Device.collection.remove("_id" == deviceId) == 1 else {
            throw ServerAbort(.notFound, reason: "Could not delete device")
        }
        if let containerId = containerId {
            BrewContainer.updateDevices(containerId)
        }
        
        return reqest.serverStatusRedirect(status: .ok, to: "/devices")
    }

    // MARK: POST :deviceId
    func postDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            struct FormData: Codable {
                var action: String?
                var name: String?
                var notifications: Bool?
                var hostPin: Device.HostDevicePin?
                var cycleTimeLimit: Int?
                var activeLow: Bool?
                var color: Device.Color?
                var useForControl: Bool?
                var backup: Bool?
                var minTemperature: Double?
                var maxTemperature: Double?
                var containerId: String?
                
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: FormData.CodingKeys.self)
                    action = try? container.decode(String.self, forKey: .action)
                    name = try? container.decode(String.self, forKey: .name)
                    notifications = try? container.decode(Bool.self, forKey: .notifications)
                    hostPin = try? container.decode(Device.HostDevicePin.self, forKey: .hostPin)
                    cycleTimeLimit = try? container.decode(Int.self, forKey: .cycleTimeLimit)
                    activeLow = try? container.decode(Bool.self, forKey: .activeLow)
                    color = try? container.decode(Device.Color.self, forKey: .color)
                    useForControl = try? container.decode(Bool.self, forKey: .useForControl)
                    backup = try? container.decode(Bool.self, forKey: .backup)
                    minTemperature = try? container.decode(Double.self, forKey: .minTemperature)
                    maxTemperature = try? container.decode(Double.self, forKey: .maxTemperature)
                    containerId = try? container.decode(String.self, forKey: .containerId)
                }
            }
            let deviceId = try request.parameters.next(ObjectId.self)
            guard let device = try Device.collection.findOne("_id" == deviceId, projecting: [
                "_id",
                "hostDeviceId",
                "type",
                "containerId"
            ]) else {
                throw ServerAbort(.notFound, reason: "Device not found")
            }
            let authentication = try request.authentication()
            if authentication.permission.isAdmin == false {
                let hostDeviceId = try device.extractObjectId("hostDeviceId")
                guard try authentication.canAccess(hostDeviceId: hostDeviceId), authentication.permission != .readOnly else {
                    return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
                }
            }
            let containerId = device["containerId"] as? ObjectId
            let type = try device.extractDeviceType("type")
            let formData = try request.content.syncDecode(FormData.self)
            if formData.action == "delete" {
                return promise.succeed(result: try DeviceRouter.delete(reqest: request, deviceId: deviceId, containerId: containerId))
            } else if formData.action == "viewLogs" {
                return promise.succeed(result: request.serverRedirect(to: "/logs?deviceId=\(deviceId.hexString)"))
            } else if formData.action == "viewTemperatures" {
                return promise.succeed(result: request.serverRedirect(to: "/temperatures?deviceId=\(deviceId.hexString)"))
            } else if formData.action == "viewCycles" {
                return promise.succeed(result: request.serverRedirect(to: "/cycles?deviceId=\(deviceId.hexString)"))
            } else if formData.action == "forceNormal", type.isSwitchDevice {
                try HostDevice.publishEvent(request: request, eventName: "updateForceMode", data: "\(deviceId.hexString),0", redirect: "/devices/\(deviceId.hexString)", promise: promise)
            } else if formData.action == "forceOn", type.isSwitchDevice {
                try HostDevice.publishEvent(request: request, eventName: "updateForceMode", data: "\(deviceId.hexString),1", redirect: "/devices/\(deviceId.hexString)", promise: promise)
            } else if formData.action == "forceOff", type.isSwitchDevice {
                try HostDevice.publishEvent(request: request, eventName: "updateForceMode", data: "\(deviceId.hexString),2", redirect: "/devices/\(deviceId.hexString)", promise: promise)
            }
            let hostDeviceId = try device.extractObjectId("hostDeviceId")
            var update: Document = [:]
            var hostDeviceNeedsUpdate = false
            if let name = formData.name {
                update["name"] = name
            }
            if let notifications = formData.notifications {
                update["notifications"] = notifications
            }
            if let hostPin = formData.hostPin {
                update["hostPin"] = hostPin.rawValue
                hostDeviceNeedsUpdate = true
            }
            if type.isSwitchDevice, let cycleTimeLimit = formData.cycleTimeLimit {
                update["cycleTimeLimit"] = cycleTimeLimit
                hostDeviceNeedsUpdate = true
            }
            if type.isSwitchDevice, let activeLow = formData.activeLow {
                update["activeLow"] = activeLow
                hostDeviceNeedsUpdate = true
            }
            if let color = formData.color {
                update["color"] = color.rawValue
            }
            if type.isOneWireDevice, let useForControl = formData.useForControl {
                update["useForControl"] = useForControl
                hostDeviceNeedsUpdate = true
            }
            if type.isTemperatureControlDevice, let backup = formData.backup {
                update["backup"] = backup
                hostDeviceNeedsUpdate = true
            }
            var unset: [String: Int] = [:]
            if type.isTemperatureSensorDevice {
                if let minTemperature = formData.minTemperature {
                    if minTemperature.isValidTemperature {
                        update["minTemperature"] = minTemperature
                    } else {
                        unset["minTemperature"] = 1
                    }
                    hostDeviceNeedsUpdate = true
                } else if request.jsonResponse == false {
                    unset["minTemperature"] = 1
                }
                if let maxTemperature = formData.maxTemperature {
                    if maxTemperature.isValidTemperature {
                        update["maxTemperature"] = maxTemperature
                    } else {
                        unset["maxTemperature"] = 1
                    }
                    hostDeviceNeedsUpdate = true
                } else if request.jsonResponse == false {
                    unset["maxTemperature"] = 1
                }
            }
            let updateContainer: Bool
            if let containerIdString = formData.containerId, let containerId = try? ObjectId(containerIdString), let currentContainerId = device["containerId"] as? ObjectId, currentContainerId != containerId {
                updateContainer = true
            } else if device["containerId"] == nil {
                updateContainer = true
            } else {
                updateContainer = false
            }
            
            if let containerIdString = formData.containerId, let containerId = try? ObjectId(containerIdString), updateContainer {
                Logger.info("Change Container")
                _ = try BrewContainer.addDevice(containerId: containerId, deviceId: deviceId, authentication: authentication)
            } else if let containerIdString = formData.containerId, containerIdString == "none", device["containerId"] != nil {
                Logger.info("Remove Container")
                _ = try BrewContainer.removeDevice(deviceId: deviceId, authentication: authentication)
            }
            guard update.count > 0 || unset.count > 0 else {
                guard let document = try Device.collection.findOne("_id" == deviceId) else {
                    throw ServerAbort(.notFound, reason: "Device not found")
                }

                if request.jsonResponse {
                    return promise.submit(try document.makeResponse(request))
                }
                return promise.succeed(result: ServerResponse.response(request.redirect(to: "/devices")))
            }
            var query: Document = [:]
            if update.count > 0 {
                query["$set"] = update
            }
            if unset.count > 0 {
                query["$unset"] = unset
            }
            if hostDeviceNeedsUpdate {
                _ = try HostDevice.collection.findAndUpdate("_id" == hostDeviceId, with: ["$set": ["needsUpdate": true]], upserting: false, returnedDocument: .new)
            }
            let document = try Device.collection.findAndUpdate("_id" == deviceId, with: query, upserting: false, returnedDocument: .new)

            if request.jsonResponse {
                return promise.submit(try document.makeResponse(request))
            }
            return promise.succeed(result: ServerResponse.response(request.redirect(to: "/devices/\(deviceId.hexString)")))
        }
    }
    
    // MARK: POST :deviceId/action
    func postDeviceAction(_ request: Request) throws -> ServerResponse {
        DispatchQueue.global().async {
            do {
                struct FormData: Decodable {
                    var createdAtString: String?
                    var temperature: Double?
                    var humidity: Double?
                    var interval: Int?
                    var turnedOn: Bool?
                }
                let formData: FormData
                if let queryData = try? request.query.decode(FormData.self) {
                    formData = queryData
                } else {
                    formData = try request.content.syncDecode(FormData.self)
                }
                let deviceId = try request.parameters.next(ObjectId.self)
                let createdAt: Date
                if let dateString = formData.createdAtString, let date = Formatter.iso8601.date(from: dateString) {
                    createdAt = date
                } else {
                    createdAt = Date()
                }
                guard var device = try Device.collection.findOne("_id" == deviceId) else {
                    throw ServerAbort(.notFound, reason: "Device not found")
                }
                guard let typeInt = device["type"]?.intValue, let type = Device.DeviceType(rawValue: typeInt) else {
                    throw ServerAbort(.notFound, reason: "Device type not found")
                }
                guard let hostDeviceId = device["hostDeviceId"] as? ObjectId else {
                    throw ServerAbort(.notFound, reason: "Host device ID not found")
                }
                let hostDevice = try HostDevice.collection.findAndUpdate("_id" == hostDeviceId, with: ["$set": ["updatedAt": Date()]], upserting: false, returnedDocument: .new)
                let userId = try hostDevice.extractObjectId("userId")
                var container: Document?
                if let containerId = device["containerId"] as? ObjectId {
                    container = try BrewContainer.collection.findOne("_id" == containerId)
                } else {
                    container = nil
                }
                
                let deviceOffline = device["offline"] as? Bool ?? false
                let lastUpdated = device["updatedAt"] as? Date ?? Date()
                let updatedAt = Date()
                device["updatedAt"] = updatedAt
                device["assigned"] = true
                device["offline"] = false
                
                if let temperature = formData.temperature {
                    guard type.isTemperatureSensorDevice else {
                        throw ServerAbort(.notFound, reason: "Invalid device type")
                    }
                    let humidity: Double?
                    if type.isHumiditySensorDevice {
                        humidity = formData.humidity
                    } else {
                        humidity = nil
                    }
                    
                    guard temperature.isValidTemperature else {
                        try Log.create(type: .temperatureOutOfRange, hostDeviceId: hostDeviceId, deviceId: deviceId)
                        try Device.collection.update("_id" == deviceId, to: device)
                        throw ServerAbort(.notFound, reason: "Invalid temperature")
                    }
                    
                    device["lastActionDate"] = createdAt
                    device["lastTemperature"] = temperature
                    if let humidity = humidity {
                        device["lastHumidity"] = humidity
                    }
                    
                    InfluxdbProiver.write(deviceId: deviceId, temperature: temperature, humidity: humidity, date: createdAt, request: request)
                    
                    var outsideTemperature = false
                    if let minTemperature = device["minTemperature"]?.doubleValue, temperature < minTemperature {
                        if device["outsideTemperature"] as? Bool ?? false == false {
                            device["outsideTemperature"] = true
                            outsideTemperature = true
                            if device["notifications"] as? Bool ?? true == true {
                                Notification.send(userId: userId, device: device, kind: .belowMinTemperature, temperature: temperature)
                            }
                        }
                    } else if let maxTemperature = device["maxTemperature"]?.doubleValue, temperature > maxTemperature {
                        if device["outsideTemperature"] as? Bool ?? false == false {
                            device["outsideTemperature"] = true
                            outsideTemperature = true
                            if device["notifications"] as? Bool ?? true == true {
                                Notification.send(userId: userId, device: device, kind: .aboveMaxTemperature, temperature: temperature)
                            }
                        }
                    } else if device["outsideTemperature"] as? Bool ?? false == true {
                        device["outsideTemperature"] = false
                        if device["notifications"] as? Bool ?? true == true {
                            Notification.send(userId: userId, device: device, kind: .insideTemperature, temperature: temperature)
                        }
                    }
                    
                    if var container = container, let containerId = container.objectId {
                        if let minTemperature = container["minTemperature"]?.doubleValue, temperature < minTemperature {
                            if device["outsideContainerTemperature"] as? Bool ?? false == false {
                                device["outsideContainerTemperature"] = true
                                if device["notifications"] as? Bool ?? true == true {
                                    Notification.send(userId: userId, device: device, kind: .belowContainerMinTemperature, temperature: temperature)
                                }
                            }
                        } else if let maxTemperature = container["maxTemperature"]?.doubleValue, temperature > maxTemperature {
                            if device["outsideContainerTemperature"] as? Bool ?? false == false {
                                device["outsideContainerTemperature"] = true
                                if device["notifications"] as? Bool ?? true == true {
                                    Notification.send(userId: userId, device: device, kind: .aboveContainerMaxTemperature, temperature: temperature)
                                }
                            }
                        } else if device["outsideContainerTemperature"] as? Bool ?? false == true {
                            device["outsideContainerTemperature"] = false
                            if device["notifications"] as? Bool ?? true == true {
                                Notification.send(userId: userId, device: device, kind: .insideContainerTemperature, temperature: temperature)
                            }
                        }
                        
                        if let humidity = humidity {
                            if let minHumidity = container["minHumidity"]?.doubleValue, humidity < minHumidity {
                                if device["outsideContainerHumidity"] as? Bool ?? false == false {
                                    device["outsideContainerHumidity"] = true
                                    if device["notifications"] as? Bool ?? true == true {
                                        Notification.send(userId: userId, device: device, kind: .belowMinHumidity, humidity: humidity)
                                    }
                                }
                            } else if let maxHumidity = container["maxHumidity"]?.doubleValue, humidity > maxHumidity {
                                if device["outsideContainerHumidity"] as? Bool ?? false == false {
                                    device["outsideContainerHumidity"] = true
                                    if device["notifications"] as? Bool ?? true == true {
                                        Notification.send(userId: userId, device: device, kind: .aboveMaxHumidity, humidity: humidity)
                                    }
                                }
                            } else if device["outsideContainerHumidity"] as? Bool ?? false == true {
                                device["outsideContainerHumidity"] = false
                                if device["notifications"] as? Bool ?? true == true {
                                    Notification.send(userId: userId, device: device, kind: .insideHumidity, humidity: humidity)
                                }
                            }
                        }
                        guard try Device.collection.update("_id" == deviceId, to: device) != 0 else {
                            throw ServerAbort(.notFound, reason: "Could not update device")
                        }
                        SocketProvider.shared.send(socketFrameHolder: DeviceFrame(objectId: deviceId, turnedOn: nil, lastTemperature: temperature, lastHumidity: humidity, lastActionDate: createdAt, updatedAt: updatedAt, offline: false, assigned: true, outsideTemperature: outsideTemperature).socketFrameHodler, userId: userId)
                        
                        let containerDevices = try Device.collection.find("containerId" == containerId)
                        var totalTemperature: Double = 0
                        var temperatureCount: Int = 0
                        var totalHumidity: Double = 0
                        var humidityCount: Int = 0
                        for containerDevice in containerDevices {
                            if let lastTemperature = containerDevice["lastTemperature"]?.doubleValue {
                                totalTemperature += lastTemperature
                                temperatureCount += 1
                            }
                            if let lastHumidity = containerDevice["lastHumidity"]?.doubleValue {
                                totalHumidity += lastHumidity
                                humidityCount += 1
                            }
                        }
                        let averageHumidity = (humidityCount > 0 ? (totalHumidity / Double(humidityCount)) : nil)
                        container["averageHumidity"] = averageHumidity
                        let averageTemperature = (temperatureCount > 0 ? (totalTemperature / Double(temperatureCount)) : nil)
                        container["averageTemperature"] = averageTemperature
                        container["updatedAt"] = createdAt
                        guard try BrewContainer.collection.update("_id" == containerId, to: container) != 0 else {
                            throw ServerAbort(.notFound, reason: "Could not update container")
                        }
                        SocketProvider.shared.send(socketFrameHolder: ContainerFrame(objectId: containerId, averageTemperature: averageTemperature, averageHumidity: averageHumidity, isHeating: nil, isCooling: nil, fanActive: nil, updatedAt: createdAt, lastActionDate: nil).socketFrameHodler, userId: userId)
                    } else {
                        guard try Device.collection.update("_id" == deviceId, to: device) != 0 else {
                            throw ServerAbort(.notFound, reason: "Could not update device")
                        }
                    }
                } else if let turnedOn = formData.turnedOn {
                    guard type.isSwitchDevice else {
                        throw ServerAbort(.notFound, reason: "Invalid device type")
                    }
                    if device["backup"] as? Bool == true, turnedOn == true {
                        if type == .heater {
                            try Log.create(type: .backupHeaterUsed, hostDeviceId: hostDeviceId, deviceId: deviceId)
                            Notification.send(userId: userId, device: device, kind: .backupHeatUsed)
                        } else if type == .cooler {
                            try Log.create(type: .backupCoolerUsed, hostDeviceId: hostDeviceId, deviceId: deviceId)
                            Notification.send(userId: userId, device: device, kind: .backupCoolingUsed)
                        }
                    }
                    device["turnedOn"] = turnedOn
                    device["lastActionDate"] = createdAt
                    guard try Device.collection.update("_id" == deviceId, to: device) != 0 else {
                        throw ServerAbort(.notFound, reason: "Could not update device")
                    }
                    SocketProvider.shared.send(socketFrameHolder: DeviceFrame(objectId: deviceId, turnedOn: turnedOn, lastTemperature: nil, lastHumidity: nil, lastActionDate: createdAt, updatedAt: updatedAt, offline: false, assigned: true, outsideTemperature: nil).socketFrameHodler, userId: userId)
                    
                    InfluxdbProiver.write(deviceId: deviceId, turnedOn: turnedOn, date: createdAt, request: request)
                    
                    if var container = container, let containerId = container.objectId {
                        let containerDevices = try Device.collection.find("containerId" == containerId)
                        var isHeating: Bool = false
                        var isCooling: Bool = false
                        var fanActive: Bool = false
                        for containerDevice in containerDevices {
                            guard containerDevice["turnedOn"] as? Bool == true, let typeInt = containerDevice["type"]?.intValue, let type = Device.DeviceType(rawValue: typeInt) else { continue }
                            if type == .heater {
                                isHeating = true
                            } else if type == .cooler {
                                isCooling = true
                            } else if type == .fan {
                                fanActive = true
                            }
                        }
                        container["isHeating"] = isHeating
                        container["isCooling"] = isCooling
                        container["fanActive"] = fanActive
                        container["updatedAt"] = createdAt
                        var updatedActionDate = false
                        if let lastActionDate = container["lastActionDate"] as? Date {
                            if lastActionDate < createdAt {
                                container["lastActionDate"] = createdAt
                                updatedActionDate = true
                            }
                        } else {
                            container["lastActionDate"] = createdAt
                            updatedActionDate = true
                        }
                        guard try BrewContainer.collection.update("_id" == containerId, to: container) != 0 else {
                            throw ServerAbort(.notFound, reason: "Could not update container")
                        }
                        SocketProvider.shared.send(socketFrameHolder: ContainerFrame(objectId: containerId, averageTemperature: nil, averageHumidity: nil, isHeating: isHeating, isCooling: isCooling, fanActive: fanActive, updatedAt: createdAt, lastActionDate: (updatedActionDate ? createdAt : nil)).socketFrameHodler, userId: userId)
                    }
                } else {
                    throw ServerAbort(.notFound, reason: "Temperature or cycle required")
                }
                if deviceOffline {
                    try Log.create(type: .deviceOnline, hostDeviceId: hostDeviceId, deviceId: deviceId)
                    Notification.send(userId: userId, device: device, kind: .backOnline, date: lastUpdated)
                }
            } catch let error {
                Logger.error("Device Action Error: \(error)")
            }
        }
        return request.serverStatus(status: .ok)
    }
    
    // MARK: GET :deviceId/logs
    func getDeviceLogs(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let deviceId = try request.parameters.next(ObjectId.self)
            let authentication = try request.authentication()
            if try authentication.canAccess(deviceId: deviceId) == false {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
            }
            let filteredType = try? request.query.get(at: "type") as Int
            let query: Query
            if let filteredType = filteredType {
                query = "deviceId" == deviceId && "type" == filteredType
            } else {
                query = "deviceId" == deviceId
            }
            let pageInfo = request.pageInfo
            let logs = try Log.collection.find(query, sortedBy: ["createdAt": .descending], skipping: pageInfo.skip, limitedTo: pageInfo.limit, withBatchSize: pageInfo.limit)
            return promise.submit(try logs.makeResponse(request))
        }
    }
    
    // MARK: GET :deviceId/temperatures
    func getDeviceTemperatures(_ request: Request) throws -> Future<ServerResponse> {
        let deviceId = try request.parameters.next(ObjectId.self)
        let influxdbUrl = Admin.settings.influxdb
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            if try authentication.canAccess(deviceId: deviceId) == false {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
            }
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Accept", "application/json")
            ])
            let queryData = try request.query.decode(InfluxQueryData.self)
            let query: String
            if request.jsonResponse {
                query = try "SELECT mean(\"temperature\") AS \"temperature\" FROM \"brew\".\"autogen\".\"temperature\" WHERE \(queryData.timeFilter) AND \"deviceId\"='\(deviceId.hexString)' GROUP BY time(\(queryData.groupBy))".urlEncodedFormEncoded()
            } else {
                query = try "SELECT mean(\"temperature\") AS \"temperature\" FROM \"brew\".\"autogen\".\"temperature\" WHERE \(queryData.timeFilter) GROUP BY time(\(queryData.groupBy)), \"deviceId\" FILL(none)".urlEncodedFormEncoded()
            }
            requestClient.get("\(influxdbUrl)/query", headers: headers, beforeSend: { request in
                let urlString = request.http.urlString + "?db=brew&q=\(query)"
                guard let url = URL(string: urlString) else {
                    throw VaporError(identifier: "serializeURL", reason: "Could not serialize URL components.")
                }
                request.http.url = url
            }).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "InfluxDB reponse error"))
                }
                return promise.succeed(result: ServerResponse.response(request.rawJsonResponse(body: response.http.body)))
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
    
    // MARK: GET :deviceId/humidities
    func getDeviceHumidities(_ request: Request) throws -> Future<ServerResponse> {
        let deviceId = try request.parameters.next(ObjectId.self)
        let influxdbUrl = Admin.settings.influxdb
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            if try authentication.canAccess(deviceId: deviceId) == false {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
            }
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Accept", "application/json")
            ])
            let queryData = try request.query.decode(InfluxQueryData.self)
            let query: String
            if request.jsonResponse {
                query = try "SELECT mean(\"humidity\") AS \"temperature\" FROM \"brew\".\"autogen\".\"humidity\" WHERE \(queryData.timeFilter) AND \"deviceId\"='\(deviceId.hexString)' GROUP BY time(\(queryData.groupBy))".urlEncodedFormEncoded()
            } else {
                query = try "SELECT mean(\"humidity\") AS \"temperature\" FROM \"brew\".\"autogen\".\"humidity\" WHERE \(queryData.timeFilter) GROUP BY time(\(queryData.groupBy)), \"deviceId\" FILL(none)".urlEncodedFormEncoded()
            }
            requestClient.get("\(influxdbUrl)/query", headers: headers, beforeSend: { request in
                let urlString = request.http.urlString + "?db=brew&q=\(query)"
                guard let url = URL(string: urlString) else {
                    throw VaporError(identifier: "serializeURL", reason: "Could not serialize URL components.")
                }
                request.http.url = url
            }).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "InfluxDB reponse error"))
                }
                return promise.succeed(result: ServerResponse.response(request.rawJsonResponse(body: response.http.body)))
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
    
    // MARK: GET :deviceId/cycles
    func getDeviceCycles(_ request: Request) throws -> Future<ServerResponse> {
        let deviceId = try request.parameters.next(ObjectId.self)
        let influxdbUrl = Admin.settings.influxdb
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            guard try authentication.canAccess(deviceId: deviceId) else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
            }
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Accept", "application/json")
            ])
            let queryData = try request.query.decode(InfluxQueryData.self)
            requestClient.get("\(influxdbUrl)/query", headers: headers, beforeSend: { request in
                let query = try "SELECT turnedOn FROM \"brew\".\"autogen\".\"cycle\" WHERE \(queryData.timeFilter) AND \"deviceId\"='\(deviceId.hexString)'".urlEncodedFormEncoded()
                let urlString = request.http.urlString + "?db=brew&q=\(query)"
                
                guard let url = URL(string: urlString) else {
                    throw VaporError(identifier: "serializeURL", reason: "Could not serialize URL components.")
                }
                request.http.url = url
            }).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "InfluxDB reponse error"))
                }
                return promise.succeed(result: ServerResponse.response(request.rawJsonResponse(body: response.http.body)))
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
    
    // MARK: POST :deviceId/forceTemperature
    func postDeviceForceTemperature(_ request: Request) throws -> Future<ServerResponse> {
        let deviceId = try request.parameters.next(ObjectId.self)
        return request.globalAsync { promise in
            let temperature = try request.content.syncGet(Double.self, at: "temperature")
            let authentication = try request.authentication()
            guard try authentication.canAccess(deviceId: deviceId), authentication.permission != .readOnly else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
            }
            try HostDevice.publishEvent(request: request, eventName: "updateTemperature", data: "\(deviceId.hexString),\(temperature)", redirect: "/devices/\(deviceId.hexString)", promise: promise)
        }
    }
    
    // MARK: POST :deviceId/forceMode
    func postDeviceForceMode(_ request: Request) throws -> Future<ServerResponse> {
        let deviceId = try request.parameters.next(ObjectId.self)
        return request.globalAsync { promise in
            let forceMode = try request.content.syncGet(Device.ForceMode.self, at: "forceMode")
            let authentication = try request.authentication()
            guard try authentication.canAccess(deviceId: deviceId), authentication.permission != .readOnly else {
                return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/devices"))
            }
            try HostDevice.publishEvent(request: request, eventName: "updateForceMode", data: "\(deviceId.hexString),\(forceMode.rawValue)", redirect: "/devices/\(deviceId.hexString)", promise: promise)
        }
    }
}
