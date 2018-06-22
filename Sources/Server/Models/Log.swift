//
//  Log.swift
//  Server
//
//  Created by BluDesign, LLC on 9/21/17.
//

import Foundation
import MongoKitten

struct Log {
    
    // MARK: - Parameters
    
    static let collectionName = "log"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    
    enum LogType: Int, CustomStringConvertible, Codable {
        /// Unknown issue occurred.
        case unkown = 0,
        /// The temperature from a `Device` was over a 200 or under -100 degress fahrenheit.
        temperatureOutOfRange = 1,
        /// There was a large `Temperature` change.
        largeTemperatureChange = 2,
        /// The `Cycle` limit for a `Device` was reached.
        cycleLimit = 3,
        /// The OneWire Address CRC verification failed.
        oneWireAddressCrcFail = 4,
        /// The OneWire Data CRC verification failed.
        oneWireDataCrcFail = 5,
        /// An unkown type of a OneWire `Device` was found.
        oneWireUnknownDevice = 6,
        /// There was no response from a  OneWire `Device`.
        noUpdateForDevice = 7,
        /// A `Device` was found to be offline.
        deviceOffline = 8,
        /// A `Device` came back online after being offline.
        deviceOnline = 9,
        /// A `Container` went over its maximum temperature.
        overMaxTemperature = 10,
        /// A `Container` went over its minimum temperature.
        underMinTemperature = 11,
        /// A backup header `Device` was used.
        backupHeaterUsed = 12,
        /// A backup cooler `Device` was used.
        backupCoolerUsed = 13,
        /// A `HostDevice` was powered on.
        hostStarted = 14,
        /// A `HostDevice` received a refresh.
        refreshReceived = 15,
        /// A `HostDevice` received a force mode setting.
        forceModeReceived = 16
        
        /// Localized description of `LogType`.
        var description: String {
            switch self {
            case .unkown: return "Unknown"
            case .temperatureOutOfRange: return "Temperature Out of Range"
            case .largeTemperatureChange: return "Large Temperature Change"
            case .cycleLimit: return "Cycle Limit Reached"
            case .oneWireAddressCrcFail: return "One Wire Address CRC Failed"
            case .oneWireDataCrcFail: return "One Wire Data CRC Failed"
            case .oneWireUnknownDevice: return "Unknown One Wire Device Type"
            case .noUpdateForDevice: return "No Update For Device"
            case .deviceOffline: return "Device Offline"
            case .deviceOnline: return "Device Back Online"
            case .overMaxTemperature: return "Over Max Temperature"
            case .underMinTemperature: return "Under Min Temperature"
            case .backupHeaterUsed: return "Backup Heater Used"
            case .backupCoolerUsed: return "Backup Cooler Used"
            case .hostStarted: return "Host Device Started"
            case .refreshReceived: return "Host Device Refresh Received"
            case .forceModeReceived: return "Host Device Force Mode Received"
            }
        }
        
        /// array of all possible `LogType` values.
        static let allValues = [temperatureOutOfRange, largeTemperatureChange, cycleLimit, oneWireAddressCrcFail, oneWireDataCrcFail, oneWireUnknownDevice, noUpdateForDevice, deviceOffline, deviceOnline, overMaxTemperature, underMinTemperature, backupHeaterUsed, backupCoolerUsed, hostStarted, refreshReceived, forceModeReceived]
    }
    
    static func create(type: LogType, hostDeviceId: ObjectId, deviceId: ObjectId? = nil, containerId: ObjectId? = nil) throws {
        var document: Document = [
            "createdAt": Date(),
            "hostDeviceId": hostDeviceId,
            "type": type.rawValue
        ]
        if let deviceId = deviceId {
            document["deviceId"] = deviceId
        }
        if let containerId = containerId {
            document["containerId"] = containerId
        }
        try Log.collection.insert(document)
    }
}
