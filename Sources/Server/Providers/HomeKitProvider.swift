//
//  HomeKitProvider.swift
//  Server
//
//  Created by Chandler Huff on 12/28/18.
//

import Foundation
import HAP
import MongoKitten
import Vapor

final class HomeKitProvider: Provider {
    
    func willBoot(_ container: Container) throws -> Future<Void> {
        Logger.debug("HomeKit Provider: Will Boot")
        return .done(on: container)
    }
    
    func register(_ services: inout Services) throws {
        
    }
    
    func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        
        Logger.debug("HomeKit Provider: Did Boot")
        let homeKitEnabled = Environment.get("HOMEKIT_ENABLED")?.bool ?? true
        guard homeKitEnabled else {
            Logger.error("HomeKit Provider Disabled Not Starting")
            return .done(on: container)
        }
        let homeKitPort = Environment.get("HOMEKIT_PORT")?.intValue ?? 8001
        let homeKitPath = Environment.get("HOMEKIT_CONFIG_FILE") ?? "HomeKitConfiguration.json"
        let directory = try container.make(DirectoryConfig.self).workDir
        
        let promise = container.eventLoop.newPromise(Void.self)
        DispatchQueue.global().async {
            do {
                let path: String
                if homeKitPath.hasSuffix("/") {
                    path = homeKitPath
                } else {
                    path = "\(directory)Resources/Keys/\(homeKitPath)"
                }
                Logger.debug("Starting HomeKit Provider Config Path: \(path)")
                let bridge = HAP.Device(bridgeInfo: HAP.Service.Info(name: Constants.name, serialNumber: "00001", manufacturer: Constants.name, model: "Bridge", firmwareRevision: Constants.version), storage: FileStorage(filename: path), accessories: [])
                HomeKitProvider.shared.bridge = bridge
                HomeKitProvider.shared.server = try HAP.Server(device: bridge, listenPort: homeKitPort)
                
                let containers = try BrewContainer.collection.find()
                HomeKitProvider.shared.setup(containers: containers)
                let devices = try Device.collection.find()
                HomeKitProvider.shared.setup(devices: devices)
                promise.succeed()
            } catch let error {
                Logger.error("HomeKit Provider Start Error: \(error)")
                promise.fail(error: error)
            }
        }
        return promise.futureResult
    }
    
    static let shared = HomeKitProvider()
    
    private var containerAccessories: [ObjectId: ContainerAccessory] = [:]
    private var deviceAccessories: [ObjectId: DeviceAccessory] = [:]
    
    var server: HAP.Server?
    var bridge: HAP.Device?
    
    func container(forId containerId: ObjectId) -> ContainerAccessory? {
        return containerAccessories[containerId]
    }
    
    func device(forId deviceId: ObjectId) -> DeviceAccessory? {
        return deviceAccessories[deviceId]
    }
    
    func removeContainer(forId containerId: ObjectId) {
        guard let containerAccessory = containerAccessories[containerId] else { return }
        bridge?.removeAccessories([containerAccessory])
        containerAccessories.removeValue(forKey: containerId)
    }
    
    func removeDevice(forId deviceId: ObjectId) {
        guard let deviceAccessory = deviceAccessories[deviceId] else { return }
        bridge?.removeAccessories([deviceAccessory])
        deviceAccessories.removeValue(forKey: deviceId)
    }
    
    func setup(containers: CollectionSlice<Document>) {
        guard let bridge = bridge else { return }
        var newAccessories: [Accessory] = []
        for container in containers {
            guard let containerAccessory = try? ContainerAccessory(container: container), bridge.canAddAccessory(accessory: containerAccessory) else {
                continue
            }
            containerAccessories[containerAccessory.containerId] = containerAccessory
            newAccessories.append(containerAccessory)
        }
        guard newAccessories.isEmpty == false else { return }
        bridge.addAccessories(newAccessories)
    }
    
    func setup(devices: CollectionSlice<Document>) {
        guard let bridge = bridge else { return }
        var newAccessories: [Accessory] = []
        for device in devices {
            guard let deviceAccessory = try? DeviceAccessory(device: device), bridge.canAddAccessory(accessory: deviceAccessory) else {
                continue
            }
            deviceAccessories[deviceAccessory.deviceId] = deviceAccessory
            newAccessories.append(deviceAccessory)
        }
        guard newAccessories.isEmpty == false else { return }
        bridge.addAccessories(newAccessories)
    }
    
    func upsert(container: Document) throws {
        guard let bridge = bridge else { return }
        let containerId = try container.extractObjectId()
        if let containerAccessory = containerAccessories[containerId] {
            let averageTemperature = try container.extractDouble("averageTemperature")
            containerAccessory.update(averageTemperature: averageTemperature)
        } else {
            let containerAccessory = try ContainerAccessory(container: container)
            guard bridge.canAddAccessory(accessory: containerAccessory) else {
                throw ServerAbort(.internalServerError, reason: "HAP Container Upsert Can't Add \(containerAccessory.containerId.hexString)")
            }
            containerAccessories[containerAccessory.containerId] = containerAccessory
            bridge.addAccessories([containerAccessory])
        }
    }
    
    func upsert(device: Document) throws {
        guard let bridge = bridge else { return }
        let deviceId = try device.extractObjectId()
        if let deviceAccessory = deviceAccessories[deviceId] {
            let lastTemperature = try device.extractDouble("lastTemperature")
            deviceAccessory.update(averageTemperature: lastTemperature)
            let offline = try device.extractBoolean("offline")
            deviceAccessory.update(offline: offline)
        } else {
            let deviceAccessory = try DeviceAccessory(device: device)
            guard bridge.canAddAccessory(accessory: deviceAccessory) else {
                throw ServerAbort(.internalServerError, reason: "HAP Device Upsert Can't Add \(deviceAccessory.deviceId.hexString)")
            }
            deviceAccessories[deviceAccessory.deviceId] = deviceAccessory
            bridge.addAccessories([deviceAccessory])
        }
    }
}
