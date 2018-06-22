//
//  Device.swift
//  Server
//
//  Created by BluDesign, LLC on 8/2/17.
//

import Foundation
import MongoKitten
import Vapor

struct Device {
    
    // MARK: - Parameters
    
    static let collectionName = "device"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    
    enum Color: Int, Codable {
        case clear = 0
        case orange
        case green
        case brown
        case seaGreen
        case purple
        case indigo
        case yellow
        case lightLime
        case line
        case pink
        case salmon
    }
    
    enum DeviceType: Int, Codable {
        /// Unknown device type.
        case unkown = 0
        /// One Wire digital temperature sensor.
        case digitalTemperatureSensor = 1
        /// Analog temperature sensor.
        case analogTemperatureSensor = 2
        /// Switch that controls fan.
        case fan = 3
        /// Switch that controls heater.
        case heater = 4
        /// Switch that controls cooler.
        case cooler = 5
        /// General switch.
        case `switch` = 6
        /// Humidity sensor.
        case humiditySensorDHT11 = 7
        /// Humidity sensor.
        case humiditySensorDHT22 = 8
        
        static var userCreatableDeviceTypes: [DeviceType] {
            return [.heater, .cooler, .humiditySensorDHT11, .humiditySensorDHT22]
        }
        
        /// Localized description of `DeviceType`.
        var description: String {
            switch self {
            case .unkown: return "Unknown"
            case .digitalTemperatureSensor: return "Digital Temperature Sensor"
            case .analogTemperatureSensor: return "Analog Temperature Sensor"
            case .fan: return "Fan"
            case .heater: return "Heater"
            case .cooler: return "Cooler"
            case .switch: return "Switch"
            case .humiditySensorDHT11: return "Humidity Sensor (DHT11)"
            case .humiditySensorDHT22: return "Humidity Sensor (DHT21/DHT22)"
            }
        }
        
        /// True if the `Device` is a heater or cooler.
        var isTemperatureControlDevice: Bool {
            return (self == .heater || self == .cooler)
        }
        
        /// True if `Device` is any kind of switch.
        var isSwitchDevice: Bool {
            return (self == .heater || self == .cooler || self == .fan || self == .switch)
        }
        
        static var switchValues: [Int] {
            return [DeviceType.heater.rawValue, DeviceType.cooler.rawValue, DeviceType.fan.rawValue, DeviceType.switch.rawValue]
        }
        
        /// True if `Device` is an analog or digital temperature or humidity sensor.
        var isTemperatureSensorDevice: Bool {
            return (self == .digitalTemperatureSensor || self == .analogTemperatureSensor || self == .humiditySensorDHT11 || self == .humiditySensorDHT22)
        }
        
        static var temperatureSensorValues: [Int] {
            return [DeviceType.digitalTemperatureSensor.rawValue, DeviceType.analogTemperatureSensor.rawValue, DeviceType.humiditySensorDHT11.rawValue, DeviceType.humiditySensorDHT22.rawValue]
        }
        
        /// True if `Device` is an analog or digital temperature.
        var isTemperatureSwitchDevice: Bool {
            return (self == .digitalTemperatureSensor || self == .analogTemperatureSensor)
        }
        
        /// True if `Device` is an humidity sensor.
        var isHumiditySensorDevice: Bool {
            return (self == .humiditySensorDHT11 || self == .humiditySensorDHT22)
        }
        
        /// True if `Device` is a One Wire digital temperature sensor.
        var isOneWireDevice: Bool {
            return (self == .digitalTemperatureSensor)
        }
        
        var defaultOfflineValue: Bool {
            return isTemperatureSensorDevice || isHumiditySensorDevice
        }
        
        var defaultCycleTimeLimit: Int? {
            if isSwitchDevice {
                return 0
            }
            return nil
        }
    }
    
    // swiftlint:disable type_name
    /// Pin on a Particle.io `HostDevice`.
    enum HostDevicePin: Int, Codable {
        /// Unknown Pin
        case unkown = 0
        /// D0 Pin
        case d0 = 1
        /// D1 Pin
        case d1 = 2
        /// D2 Pin
        case d2 = 3
        /// D3 Pin
        case d3 = 4
        /// D4 Pin
        case d4 = 5
        /// D5 Pin
        case d5 = 6
        /// D6 Pin
        case d6 = 7
        /// D7 Pin
        case d7 = 8
        /// A0 Pin
        case a0 = 9
        /// A1 Pin
        case a1 = 10
        /// A2 Pin
        case a2 = 11
        /// A3 Pin
        case a3 = 12
        /// A4 Pin
        case a4 = 13
        /// A5 Pin
        case a5 = 14
        /// DAC Pin
        case dac = 15
        /// WKP Pin
        case wkp = 16
        /// RX Pin
        case rx = 17
        /// TX Pin
        case tx = 18
        /// VIN Pin
        case vin = 19
        /// VBAT Pin
        case vbat = 20
        /// RST Pin
        case rst = 21
        /// V3 Pin
        case v3 = 22
        /// GNDD Pin
        case gndd = 23
        /// GNDA Pin
        case gnda = 24
        
        static var availablePins: Set<HostDevicePin> {
            return [.d1, .d2, .d3, .d4, .d5, .d6, .d7, .a0, .a1, .a2, .a3, .a4, .a5]
        }
        
        /// Localized description of `HostDevicePin`.
        var description: String {
            switch self {
            case .unkown: return "Unknown"
            case .d0: return "D0"
            case .d1: return "D1"
            case .d2: return "D2"
            case .d3: return "D3"
            case .d4: return "D4"
            case .d5: return "D5"
            case .d6: return "D6"
            case .d7: return "D7"
            case .a0: return "A0"
            case .a1: return "A1"
            case .a2: return "A2"
            case .a3: return "A3"
            case .a4: return "A4"
            case .a5: return "A5"
            case .dac: return "DAC"
            case .wkp: return "WKP"
            case .rx: return "RX"
            case .tx: return "TX"
            case .vin: return "VIN"
            case .vbat: return "VBAT"
            case .rst: return "RST"
            case .v3: return "3V3"
            case .gndd: return "GND Digital"
            case .gnda: return "GND Analog"
            }
        }
        
        /// Pin String Value
        var value: String? {
            switch self {
            case .d0: return "D0"
            case .d1: return "D1"
            case .d2: return "D2"
            case .d3: return "D3"
            case .d4: return "D4"
            case .d5: return "D5"
            case .d6: return "D6"
            case .d7: return "D7"
            case .a0: return "A0"
            case .a1: return "A1"
            case .a2: return "A2"
            case .a3: return "A3"
            case .a4: return "A4"
            case .a5: return "A5"
            default: return nil
            }
        }
    }
    // swiftlint:enable type_name
    
    /// Type of Dallas One Wire Device.
    enum OneWireDeviceType: Int, Codable {
        /// Unknown One Wire Device
        case unkown = 0
        /// DS1820 Device
        case ds1820 = 1
        /// DS18B20 Device
        case ds18B20 = 2
        /// DS1822 Device
        case ds1822 = 3
        /// DS2438 Device
        case ds2438 = 4
        
        /// Localized description of `OneWireDeviceType`.
        var description: String {
            switch self {
            case .unkown: return "Unknown"
            case .ds1820: return "DS1820/DS18S20"
            case .ds18B20: return "DS18B20"
            case .ds1822: return "DS1822"
            case .ds2438: return "DS2438"
            }
        }
    }
    
    /// Force mode for `Device`.
    enum ForceMode: Int, Codable {
        /// Normal Mode
        case normal = 0
        /// Always On Mode
        case alwaysOn = 1
        /// Always Off Mode
        case alwaysOff = 2
    }
    
    static func tableData(pageInfo: Request.PageInfo, authentication: Request.Authentication, devices: CollectionSlice<Document>, showContainer: Bool = true) throws -> [String: TemplateData] {
        let query: Query? = (authentication.permission.isAdmin ? nil : ("userId" == authentication.userId))
        let hostDevices = try HostDevice.collection.find(query, projecting: [
            "_id",
            "name"
        ])
        var hostDeviceNames: [ObjectId: String] = [:]
        for hostDevice in hostDevices {
            guard let hostDeviceId = hostDevice.objectId, let name = hostDevice["name"] as? String else { continue }
            hostDeviceNames[hostDeviceId] = name
        }
        let containers = try BrewContainer.collection.find(query, projecting: [
            "_id",
            "name"
        ])
        var containerNames: [ObjectId: String] = [:]
        for container in containers {
            guard let containerId = container.objectId, let name = container["name"] as? String else { continue }
            containerNames[containerId] = name
        }
        let link = "/devices?"
        var pages = try (devices.count() / pageInfo.limit) + 1
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
        for device in devices {
            let deviceId = try device.extractObjectId()
            let hostDeviceId = try device.extractObjectId("hostDeviceId")
            let name = try device.extractString("name")
            let lastActionDate = (try? device.extractDate("lastActionDate"))?.longString ?? "Never"
            let type = try device.extractDeviceType("type")
            let offline = device["offline"] as? Bool ?? false
            let lastAction: String
            let badge: String
            if offline {
                lastAction = "Offline"
                badge = "danger"
            } else if let lastTemperature = device["lastTemperature"]?.doubleValue {
                lastAction = Double.temperatureFromDouble(lastTemperature)
                badge = "dark"
            } else if let turnedOn = device["turnedOn"] as? Bool {
                lastAction = (turnedOn ? "Turned On" : "Turned Off")
                if turnedOn {
                    badge = "success"
                } else {
                    badge = "light"
                }
            } else {
                lastAction = "None"
                badge = "light"
            }
            let hostDeviceName = hostDeviceNames[hostDeviceId] ?? "Unknown"
            let containerName: String
            if showContainer {
                if let containerId = device["containerId"] as? ObjectId {
                    containerName = containerNames[containerId] ?? "Unknown"
                } else {
                    containerName = "None"
                }
            } else {
                if let useForControl = device["useForControl"] as? Bool {
                    if useForControl {
                        containerName = "<span class=\"badge badge-success\">Yes</span>"
                    } else {
                        containerName = "<span class=\"badge badge-danger\">No</span>"
                    }
                } else {
                    containerName = ""
                }
            }
            let string = "<tr onclick=\"location.href='/devices/\(deviceId.hexString)'\"><td>\(name)</td><td>\(type.description)</td><td>\(lastActionDate)</td><td><span class=\"badge badge-\(badge)\">\(lastAction)</span></td><td>\(hostDeviceName)</td><td>\(containerName)</td></tr>"
            tableData.append(string)
        }
        return [
            "tableData": .string(tableData),
            "pageData": .string(pageData),
            "page": .int(pageInfo.page),
            "nextPage": .string((pageInfo.page + 1 > pages ? "#" : "\(link)page=\(pageInfo.page + 1)")),
            "prevPage": .string((pageInfo.page - 1 <= 0 ? "#" : "\(link)page=\(pageInfo.page - 1)")),
            "admin": .bool(authentication.permission.isAdmin)
        ]
    }
    
    static func checkOfflineStatus() {
        do {
            let devices = try Device.collection.find(projecting: [
                "_id", "name", "offline", "updatedAt", "type", "hostDeviceId"
            ])
            let hostDevicesIds = try HostDevice.collection.find(projecting: [
                "_id", "userId"
            ])
            var hostDeviceUserIds: [ObjectId: ObjectId] = [:]
            for hostDevice in hostDevicesIds {
                guard let hostDeviceId = hostDevice.objectId, let userId = try? hostDevice.extractObjectId("userId") else { continue }
                hostDeviceUserIds[hostDeviceId] = userId
            }
            let offlineDate = Date(timeIntervalSinceNow: -(Double(Admin.settings.offlineMinutes) * 60))
            for device in devices {
                guard let objectId = device.objectId, let typeInt = device["type"] as? Int, let type = Device.DeviceType(rawValue: typeInt), type.isTemperatureSensorDevice, (device["offline"] as? Bool ?? false) == false, let updatedAt = device["updatedAt"] as? Date, updatedAt < offlineDate else { continue }
                try Device.collection.update("_id" == objectId, to: ["$set": ["offline": true]], upserting: false, multiple: false)
                if let hostDeviceId = try? device.extractObjectId("hostDeviceId"), let userId = hostDeviceUserIds[hostDeviceId] {
                    SocketProvider.shared.send(socketFrameHolder: DeviceFrame(objectId: objectId, turnedOn: nil, lastTemperature: nil, lastHumidity: nil, lastActionDate: nil, updatedAt: nil, offline: true, assigned: nil, outsideTemperature: nil).socketFrameHodler, userId: userId)
                }
                Notification.send(userId: objectId, device: device, kind: .offline, date: updatedAt)
            }
            let hostDevices = try HostDevice.collection.find(projecting: [
                "_id", "name", "offline", "pingedAt", "userId"
            ])
            for hostDevice in hostDevices {
                guard let objectId = hostDevice.objectId, (hostDevice["offline"] as? Bool ?? false) == false, let pingedAt = hostDevice["pingedAt"] as? Date, pingedAt < offlineDate, let userId = try? hostDevice.extractObjectId("userId") else { continue }
                try HostDevice.collection.update("_id" == objectId, to: ["$set": ["offline": true]], upserting: false, multiple: false)
                SocketProvider.shared.send(socketFrameHolder: HostDeviceFrame(objectId: objectId, updatedAt: nil, pingedAt: nil, offline: true).socketFrameHodler, userId: userId)
                Notification.send(userId: objectId, hostDevice: hostDevice, kind: .offline, date: pingedAt)
            }
        } catch let error {
            Logger.error("Check Offline Status Error: \(error)")
        }
    }
}
