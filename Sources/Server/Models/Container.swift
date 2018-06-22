//
//  BrewContainer.swift
//  Server
//
//  Created by BluDesign, LLC on 9/19/17.
//

import Foundation
import Vapor
import MongoKitten

struct BrewContainer {
    
    // MARK: - Parameters
    
    static let collectionName = "container"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    
    // MARK: - Enums
    
    /// Action to take when both heating and cooling are needed in a `BrewContainer`.
    enum ConflictActionType: Int, CustomStringConvertible {
        /// Turn off both heating and cooling when there is a conflict.
        case nothing = 0
        /// Turn on heating when there is a conflict.
        case heat = 1
        /// Turn on cooling when there is a conflict.
        case cool = 2
        
        /// Localized description of conflict action.
        public var description: String {
            switch self {
            case .nothing: return "Do Nothing"
            case .heat: return "Heat"
            case .cool: return "Cool"
            }
        }
    }
    
    static func updateDevices(_ containerId: ObjectId) {
        do {
            let devices = try Device.collection.find("containerId" == containerId, projecting: [
                "_id",
                "type",
                "turnedOn"
            ])
            var isHeating: Bool = false
            var isCooling: Bool = false
            var fanActive: Bool = false
            var deviceTypes: Set<Int> = []
            for device in devices {
                guard let typeInt = device["type"]?.intValue else { continue }
                deviceTypes.insert(typeInt)
                guard device["turnedOn"] as? Bool == true, let type = Device.DeviceType(rawValue: typeInt) else { continue }
                if type == .heater {
                    isHeating = true
                } else if type == .cooler {
                    isCooling = true
                } else if type == .fan {
                    fanActive = true
                }
            }
            let containsTemperatureControlDevices = deviceTypes.contains(Device.DeviceType.heater.rawValue) || deviceTypes.contains(Device.DeviceType.cooler.rawValue)
            let containsTemperatureSensorDevices = deviceTypes.contains(Device.DeviceType.digitalTemperatureSensor.rawValue) || deviceTypes.contains(Device.DeviceType.humiditySensorDHT11.rawValue) || deviceTypes.contains(Device.DeviceType.humiditySensorDHT22.rawValue)
            let containsDevices = deviceTypes.count != 0
            
            try BrewContainer.collection.update("_id" == containerId, to: ["$set": [
                "containsControllers": containsTemperatureControlDevices,
                "containsSensors": containsTemperatureSensorDevices,
                "containsDevices": containsDevices,
                "isHeating": isHeating,
                "isCooling": isCooling,
                "fanActive": fanActive
            ]], upserting: false)
        } catch let error {
            Logger.error("Update Container Error: \(error)")
        }
    }
    
    // MARK: Add Device to Container
    static func addDevice(containerId: ObjectId, deviceId: ObjectId, authentication: Request.Authentication) throws -> Document {
        guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
            "_id",
            "userId"
        ]) else {
            throw ServerAbort(.notFound, reason: "Container not found")
        }
        if authentication.permission.isAdmin == false {
            let objectUserId = try container.extractObjectId("userId")
            guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                throw ServerAbort(.forbidden, reason: "Insufficient premissions")
            }
        }
        
        let lastDevice = try Device.collection.findOne("containerId" == containerId, sortedBy: ["order": .descending], projecting: [
            "_id",
            "order"
        ])
        let order = (lastDevice?["order"]?.intValue ?? -1) + 1
        
        let update: Document = [
            "containerOrder": order,
            "containerId": containerId
        ]
        let device = try Device.collection.findAndUpdate("_id" == deviceId, with: ["$set": update], upserting: false, returnedDocument: .new)
        BrewContainer.updateDevices(containerId)
        return device
    }
    
    // MARK: Remove Device from Container
    static func removeDevice(deviceId: ObjectId, authentication: Request.Authentication) throws -> Document {
        guard let device = try Device.collection.findOne("_id" == deviceId, projecting: [
            "_id",
            "containerId"
        ]) else {
            throw ServerAbort(.notFound, reason: "Device not found")
        }
        let containerId = try device.extractObjectId("containerId")
        
        guard let container = try BrewContainer.collection.findOne("_id" == containerId, projecting: [
            "_id",
            "userId"
        ]) else {
            throw ServerAbort(.notFound, reason: "Container not found")
        }
        if authentication.permission.isAdmin == false {
            let objectUserId = try container.extractObjectId("userId")
            guard authentication.userId == objectUserId, authentication.permission != .readOnly else {
                throw ServerAbort(.forbidden, reason: "Insufficient premissions")
            }
        }
        // TODO: Test
        
        guard let deviceContainerId = device["containerId"] as? ObjectId, deviceContainerId == containerId else {
            throw ServerAbort(.notFound, reason: "Device not in container")
        }
        
        let object = try Device.collection.findAndUpdate("_id" == deviceId, with: ["$unset": ["containerId": 1]], upserting: false, returnedDocument: .new)
        BrewContainer.updateDevices(containerId)
        return object
        
    }
}
