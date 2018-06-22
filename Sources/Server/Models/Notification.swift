//
//  Notification.swift
//  Server
//
//  Created by BluDesign, LLC on 12/5/17.
//

import Foundation
import MongoKitten

struct Notification {
    
    // MARK: - Parameters
    
    static let collectionName = "notification"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    
    enum Kind: Int, CustomStringConvertible {
        case aboveMaxTemperature = 1
        case belowMinTemperature = 2
        case insideTemperature = 3
        case aboveMaxHumidity = 4
        case belowMinHumidity = 5
        case insideHumidity = 6
        case offline = 7
        case backOnline = 8
        case backupHeatUsed = 9
        case backupCoolingUsed = 10
        case aboveContainerMaxTemperature = 11
        case belowContainerMinTemperature = 12
        case insideContainerTemperature = 13
        
        var description: String {
            switch self {
            case .aboveMaxTemperature: return "Above Max Temperature"
            case .belowMinTemperature: return "Below Min Temperature"
            case .insideTemperature: return "Back Inside Min/Max Temperature"
            case .aboveMaxHumidity: return "Above Max Humidity"
            case .belowMinHumidity: return "Below Min Humidity"
            case .insideHumidity: return "Back Inside Min/Max Humidity"
            case .offline: return "Offline"
            case .backOnline: return "Back Online"
            case .backupHeatUsed: return "Backup Heating Device Used"
            case .backupCoolingUsed: return "Backup Cooling Device Used"
            case .aboveContainerMaxTemperature: return "Above Container Max Temperature"
            case .belowContainerMinTemperature: return "Below Container Min Temperature"
            case .insideContainerTemperature: return "Back Inside Container Min/Max Temperature"
            }
        }
        
        var isError: Bool {
            switch self {
            case .aboveMaxTemperature: return true
            case .belowMinTemperature: return true
            case .insideTemperature: return false
            case .aboveMaxHumidity: return true
            case .belowMinHumidity: return true
            case .insideHumidity: return false
            case .offline: return true
            case .backOnline: return false
            case .backupHeatUsed: return true
            case .backupCoolingUsed: return true
            case .aboveContainerMaxTemperature: return true
            case .belowContainerMinTemperature: return true
            case .insideContainerTemperature: return false
            }
        }
    }
    
    static func send(userId: ObjectId, device: Document, kind: Kind, temperature: Double? = nil, humidity: Double? = nil, date: Date? = nil) {
        guard let objectId = device.objectId, let name = device["name"] as? String, let hostDeviceId = device["hostDeviceId"] as? ObjectId else {
            return
        }
        PushProvider.sendPush(title: "Device: \(name)", body: kind.description, userId: userId)
        var fields: [(title: String, value: String)] = []
        if let temperature = temperature {
            fields.append((title: "Temperature", value: "\(Double.temperatureFromDouble(temperature))"))
        }
        if let humidity = humidity {
            fields.append((title: "Humidity", value: "\(Double.humidityFromDouble(humidity))"))
        }
        if kind == .backOnline, let date = date {
            fields.append((title: "First Offline", value: "\(date.longString)"))
        }
        if kind == .offline, let date = date {
            fields.append((title: "Offline Since", value: "\(date.longString)"))
        }
        PushProvider.sendSlack(objectName: "Device: \(name)", objectLink: "/devices/\(objectId.hexString)", title: kind.description, titleLink: "/notifications", isError: kind.isError, fields: fields)
        
        var notification: Document = [
            "type": kind.rawValue,
            "deviceId": objectId,
            "hostDeviceId": hostDeviceId,
            "createdAt": Date(),
            "userId": userId
        ]
        if let temperature = temperature {
            notification["temperature"] = temperature
        }
        if let humidity = humidity {
            notification["humidity"] = humidity
        }
        _ = try? Notification.collection.insert(notification)
    }
    
    static func send(userId: ObjectId, container: Document, kind: Kind) {
        guard let objectId = container.objectId, let name = container["name"] as? String else {
            return
        }
        PushProvider.sendPush(title: "Container: \(name)", body: kind.description, userId: userId)
        PushProvider.sendSlack(objectName: "Container: \(name)", objectLink: "/containers/\(objectId.hexString)", title: kind.description, titleLink: "/notifications", isError: kind.isError, fields: [])
        
        let notification: Document = [
            "type": kind.rawValue,
            "containerId": objectId,
            "createdAt": Date(),
            "userId": userId
        ]
        _ = try? Notification.collection.insert(notification)
    }
    
    static func send(userId: ObjectId, hostDevice: Document, kind: Kind, date: Date? = nil) {
        guard let objectId = hostDevice.objectId, let name = hostDevice["name"] as? String else {
            return
        }
        var fields: [(title: String, value: String)] = []
        if kind == .backOnline, let date = date {
            fields.append((title: "First Offline", value: "\(date.longString)"))
        }
        if kind == .offline, let date = date {
            fields.append((title: "Offline Since", value: "\(date.longString)"))
        }
        PushProvider.sendPush(title: "Host Device: \(name)", body: kind.description, userId: userId)
        PushProvider.sendSlack(objectName: "Host Device: \(name)", objectLink: "/hostDevices/\(objectId.hexString)", title: kind.description, titleLink: "/notifications", isError: kind.isError, fields: [])
        
        let notification: Document = [
            "type": kind.rawValue,
            "hostDeviceId": objectId,
            "createdAt": Date(),
            "userId": userId
        ]
        _ = try? Notification.collection.insert(notification)
    }
    
    static func sendTest(userId: ObjectId) {
        PushProvider.sendPush(title: "Test Notification", body: "Test Push Notification - \(Date().longString)", userId: userId)
        PushProvider.sendSlack(objectName: "Test Notification", objectLink: nil, title: "Test Push Notification - \(Date().longString)", titleLink: "/admin", isError: false, fields: [])
    }
}
