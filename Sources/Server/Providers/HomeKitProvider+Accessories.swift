//
//  HomeKitProvider+Accessories.swift
//  Server
//
//  Created by Chandler Huff on 12/29/18.
//

import Foundation
import HAP
import MongoKitten

private extension Double {
    var celsiusValue: Double {
        return (self - 32) / 1.8
    }
}

extension Accessory {
    class ReaumurThermometer: Accessory {
        let temperatureSensor = Service.ReaumurTemperatureSensor()
        
        init(info: Service.Info) {
            super.init(info: info, type: .sensor, services: [temperatureSensor])
        }
    }
}

extension Service {
    class ReaumurTemperatureSensor: Service {
        let currentTemperature = GenericCharacteristic<CurrentTemperature>(
            type: .currentTemperature,
            value: 0,
            permissions: [.read, .events],
            maxValue: 100,
            minValue: -100)
        let isActive = GenericCharacteristic<Bool>(type: .statusActive, value: nil, permissions: [.read, .events], description: nil, format: .bool)
        
        init() {
            super.init(type: .temperatureSensor, characteristics: [AnyCharacteristic(currentTemperature), AnyCharacteristic(isActive)])
        }
    }
}

final class ContainerAccessory: Accessory.Thermometer {
    
    let containerId: ObjectId
    
    init(container: Document) throws {
        let containerId = try container.extractObjectId()
        let name = try container.extractString("name")
        if let homeKitHidden = container["homeKitHidden"] as? Bool, homeKitHidden {
            throw ServerAbort(.internalServerError, reason: "Container Hidden in HomeKit: \(containerId.hexString)")
        }
        self.containerId = containerId
        super.init(info: Service.Info(name: name, serialNumber: containerId.hexString, manufacturer: Constants.name, model: "Container", firmwareRevision: Constants.version))
        if let averageTemperature = container["averageTemperature"]?.doubleValue {
            temperatureSensor.currentTemperature.value = averageTemperature.celsiusValue
        }
    }
    
    func update(averageTemperature: Double?) {
        temperatureSensor.currentTemperature.value = averageTemperature?.celsiusValue
    }
}

final class DeviceAccessory: Accessory.ReaumurThermometer {
    
    let containerId: ObjectId
    let deviceId: ObjectId
    
    init(device: Document) throws {
        let deviceId = try device.extractObjectId()
        let containerId = try device.extractObjectId("containerId")
        let name = try device.extractString("name")
        if let homeKitHidden = device["homeKitHidden"] as? Bool, homeKitHidden {
            throw ServerAbort(.internalServerError, reason: "Device Hidden in HomeKit: \(deviceId.hexString)")
        }
        guard let typeInt = device["type"]?.intValue, let type = Device.DeviceType(rawValue: typeInt), type.isTemperatureSensorDevice else {
            throw ServerAbort(.internalServerError, reason: "Device Type Invalid: \(deviceId.hexString)")
        }
        self.deviceId = deviceId
        self.containerId = containerId
        super.init(info: Service.Info(name: name, serialNumber: deviceId.hexString, manufacturer: Constants.name, model: "Device", firmwareRevision: Constants.version))
        if let lastTemperature = device["lastTemperature"]?.doubleValue {
            temperatureSensor.currentTemperature.value = lastTemperature.celsiusValue
        }
        if let offline = device["offline"] as? Bool {
            temperatureSensor.isActive.value = !offline
        }
    }
    
    func update(averageTemperature: Double?) {
        temperatureSensor.currentTemperature.value = averageTemperature?.celsiusValue
    }
    
    func update(offline: Bool) {
        guard temperatureSensor.isActive.value != offline else { return }
        temperatureSensor.isActive.value = !offline
    }
}
