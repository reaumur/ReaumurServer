//
//  HostDevice.swift
//  Server
//
//  Created by BluDesign, LLC on 9/9/17.
//

import Foundation
import MongoKitten
import Vapor

struct HostDevice {
    
    // MARK: - Parameters
    
    static let collectionName = "hostDevice"
    static var collection: MongoKitten.Collection {
        return MongoProvider.shared.database[collectionName]
    }
    
    /// Type of `ParticleDevice`.
    enum ParticleDeviceType: Int, Codable {
        /// Unown type of `ParticleDevice`.
        case unkown = 0,
        /// A Partile Core device.
        particleCore = 1,
        /// A Partile Photon device.
        particlePhoton = 2,
        /// A Partile Electron device.
        particleElectron = 3,
        /// A Partile P1 device.
        particleP1 = 4,
        /// A Partile P1 device.
        particleArgon = 5
        
        init?(platformId: Int) {
            switch platformId {
            case 0: self = .particleCore
            case 6: self = .particlePhoton
            case 8: self = .particleP1
            case 10: self = .particleElectron
            case 12: self = .particleArgon
            default: return nil
            }
        }
        
        /// Localized description of `ParticleDeviceType`.
        var description: String {
            switch self {
            case .unkown: return "Unknown"
            case .particleCore: return "Particle Core"
            case .particlePhoton: return "Particle Photon"
            case .particleElectron: return "Particle Electron"
            case .particleP1: return "Particle P1"
            case .particleArgon: return "Particle Argon"
            }
        }
    }
    
    static func sourceCode(_ hostDevice: Document, sharedContainer: Container) throws -> String {
        let hostDeviceId = try hostDevice.extractObjectId()
        let userId = try hostDevice.extractObjectId("userId")
        let typeValue = try hostDevice.extractInteger("type")
        guard let type = HostDevice.ParticleDeviceType(rawValue: typeValue) else {
            throw ServerAbort(.notFound, reason: "type is required")
        }
        
        var sourceCode = "\n\n\n"
        
        guard let hostUrlString = Admin.settings.domain, let hostUrl = URL(string: hostUrlString) else {
            throw ServerAbort(.badRequest, reason: "Server address not set")
        }
        let url: URL
        if hostUrl.scheme == "http" {
            url = hostUrl
        } else {
            guard let hostInsecureUrlString = Admin.settings.insecureDomain, let hostInsecureUrl = URL(string: hostInsecureUrlString), hostInsecureUrl.scheme == "http" else {
                throw ServerAbort(.badRequest, reason: "Insecure server address not set")
            }
            url = hostInsecureUrl
        }
        guard let host = url.host else {
            throw ServerAbort(.badRequest, reason: "Server host address required")
        }
        let port = url.port ?? 80
        let hostCompents = host.components(separatedBy: ".")
        if hostCompents.count == 4 {
            sourceCode += "String apiUrl;\n"
            sourceCode += "uint8_t server[] = { \(hostCompents[0]), \(hostCompents[1]), \(hostCompents[2]), \(hostCompents[3]) };\n"
            sourceCode += "IPAddress apiIp( server );\n"
        } else {
            sourceCode += "String apiUrl = \"\(host)\";\n"
            sourceCode += "IPAddress apiIp;\n"
        }
        sourceCode += "int apiPort = \(port);\n\n"
        
        if let updateLedPin = (try? hostDevice.extractHostDevicePin("updateLedPin"))?.value {
            sourceCode += "int updateLedPin = \(updateLedPin);\n"
        } else {
            sourceCode += "int updateLedPin = 666222;\n"
        }
        let updateInterval = try hostDevice.extractInteger("updateInterval")
        sourceCode += "int updateInterval = \(updateInterval);\n"
        sourceCode += "String userId = \"\(userId.hexString)\";\n"
        sourceCode += "String hostId = \"\(hostDeviceId.hexString)\";\n\n"
        
        var containerSourceCode = "Container containers[] = {\n"
        var addedContainer = false
        var temperatureSensorSourceCode = "DigitalTemperatureDevice temperatureSensors[] = {\n"
        var addedTemperatureSensor = false
        var humidititySensorSourceCode = "HumidityDevice humiditySensors[] = {\n"
        var addedHumiditySensor = false
        var coolingSwitchSourceCode = "SwitchDevice coolingSwitches[] = {\n"
        var addedCoolingSwitch = false
        var heatingSwitchSourceCode = "SwitchDevice heatingSwitches[] = {\n"
        var addedHeatingSwitch = false
        var pinModeSourceCode = ""
        var digitalWriteSourceCode = ""
        
        let devices = try Device.collection.find("hostDeviceId" == hostDeviceId, projecting: [
            "_id",
            "containerId",
            "type",
            "deviceId",
            "useForControl",
            "hostPin",
            "cycleTimeLimit",
            "activeLow",
            "backup"
        ])
        var containerIds: Set<ObjectId> = []
        
        func switchDeviceSourceCode(device: Document, objectId: ObjectId, containerId: ObjectId) throws -> String {
            var sourceCode = ""
            guard let hostDevicePin = try device.extractHostDevicePin("hostPin").value else {
                throw ServerAbort(.badRequest, reason: "Invalid host device pin pin")
            }
            let cycleTimeLimit = try device.extractInteger("cycleTimeLimit") * 60000
            let activeLow = try device.extractBoolean("activeLow")
            let backup = try device.extractBoolean("backup")
            sourceCode += "  SwitchDevice(\"\(objectId.hexString)\", "
            sourceCode += "\"\(containerId.hexString)\", "
            sourceCode += "\(hostDevicePin), "
            sourceCode += "\(cycleTimeLimit), "
            sourceCode += "\((activeLow ? "true" : "false")), "
            sourceCode += "\((backup ? "true" : "false"))),\n"
            pinModeSourceCode += "    pinMode(\(hostDevicePin), OUTPUT);\n"
            digitalWriteSourceCode += "    digitalWrite(\(hostDevicePin), \((activeLow ? "HIGH" : "LOW")));\n"
            return sourceCode
        }
        
        for device in devices {
            do {
                let containerId = try device.extractObjectId("containerId")
                let objectId = try device.extractObjectId()
                let type = try device.extractDeviceType("type")
                switch type {
                case .digitalTemperatureSensor:
                    let deviceId = try device.extractString("deviceId")
                    let useForControl = try device.extractBoolean("useForControl")
                    temperatureSensorSourceCode += "  DigitalTemperatureDevice(\"\(deviceId)\", "
                    temperatureSensorSourceCode += "\"\(objectId.hexString)\", "
                    temperatureSensorSourceCode += "\"\(containerId.hexString)\", "
                    temperatureSensorSourceCode += "\((useForControl ? "true" : "false")), "
                    temperatureSensorSourceCode += "\(device.extractTemperature("maxTemperature")), "
                    temperatureSensorSourceCode += "\(device.extractTemperature("minTemperature"))),\n"
                    addedTemperatureSensor = true
                case .humiditySensorDHT11, .humiditySensorDHT22:
                    guard let hostDevicePin = try device.extractHostDevicePin("hostPin").value else {
                        throw ServerAbort(.badRequest, reason: "Invalid host device pin pin")
                    }
                    humidititySensorSourceCode += "  HumidityDevice(\(hostDevicePin), "
                    humidititySensorSourceCode += "\((type == .humiditySensorDHT22 ? "DHT22" : "DHT11")), "
                    humidititySensorSourceCode += "\"\(objectId.hexString)\", "
                    humidititySensorSourceCode += "\"\(containerId.hexString)\"),\n"
                    pinModeSourceCode += "    pinMode(\(hostDevicePin), INPUT);\n"
                    digitalWriteSourceCode += "    digitalWrite(\(hostDevicePin), HIGH);\n"
                    addedHumiditySensor = true
                case .cooler:
                    coolingSwitchSourceCode += try switchDeviceSourceCode(device: device, objectId: objectId, containerId: containerId)
                    addedCoolingSwitch = true
                case .heater:
                    heatingSwitchSourceCode += try switchDeviceSourceCode(device: device, objectId: objectId, containerId: containerId)
                    addedHeatingSwitch = true
                default:
                    continue
                }
                containerIds.insert(containerId)
            } catch let error {
                Logger.error("Device Error: \(error)")
            }
        }
        if let updateLedPin = (try? hostDevice.extractHostDevicePin("updateLedPin"))?.value {
            pinModeSourceCode += "    pinMode(\(updateLedPin), OUTPUT);\n"
            digitalWriteSourceCode += "    digitalWrite(\(updateLedPin), LOW);\n"
        }
        
        let containers = try BrewContainer.collection.find(Query(aqt: AQT.in(key: "_id", in: Array(containerIds))))
        for container in containers {
            guard let containerId = container.objectId else { continue }
            guard let conflictAction = container["conflictAction"]?.intValue else { continue }
            containerSourceCode += "  Container(\"\(containerId.hexString)\", "
            containerSourceCode += "\(container.extractTemperature("maxTemperature")), "
            containerSourceCode += "\(container.extractTemperature("minTemperature")), "
            containerSourceCode += "\(container.extractTemperature("wantedHeatTemperature")), "
            containerSourceCode += "\(container.extractTriggerTemperature("turnOnBelowHeatTemperature")), "
            containerSourceCode += "\(container.extractTriggerTemperature("turnOffAboveHeatTemperature")), "
            containerSourceCode += "\(container.extractTemperature("wantedCoolTemperature")), "
            containerSourceCode += "\(container.extractTriggerTemperature("turnOnAboveCoolTemperature")), "
            containerSourceCode += "\(container.extractTriggerTemperature("turnOffBelowCoolTemperature")), "
            containerSourceCode += "\(conflictAction)),\n"
            addedContainer = true
        }
        
        if addedContainer {
            sourceCode += containerSourceCode.dropLast(2) + "\n};\n\n"
        } else {
            sourceCode += containerSourceCode + "\n};\n\n"
        }
        if addedTemperatureSensor {
            sourceCode += temperatureSensorSourceCode.dropLast(2) + "\n};\n\n"
        } else {
            sourceCode += temperatureSensorSourceCode + "\n};\n\n"
        }
        if addedHumiditySensor {
            sourceCode += humidititySensorSourceCode.dropLast(2) + "\n};\n\n"
        } else {
            sourceCode += humidititySensorSourceCode + "\n};\n\n"
        }
        if addedCoolingSwitch {
            sourceCode += coolingSwitchSourceCode.dropLast(2) + "\n};\n\n"
        } else {
            sourceCode += coolingSwitchSourceCode + "\n};\n\n"
        }
        if addedHeatingSwitch {
            sourceCode += heatingSwitchSourceCode.dropLast(2) + "\n};\n\n"
        } else {
            sourceCode += heatingSwitchSourceCode + "\n};\n\n"
        }
        
        let oneWirePin = "D0"
        sourceCode += "unsigned int nextTemperatureUpload = 0;\nunsigned int nextTemperatureCheck = 0;\nint oneWireCount = 0;\nint currentInterval = 5;\nboolean registerOneWire = false;\nboolean sendDeviceStatus = false;\nHttpClient http;\nOneWire oneWire = OneWire(\(oneWirePin));\n\nvoid setup() {\n"
        
        sourceCode += pinModeSourceCode
        sourceCode += digitalWriteSourceCode
        sourceCode += "\n"
        
        let directory = try sharedContainer.make(DirectoryConfig.self).workDir
        let hostFirmwarePath = directory.appending("Resources/Firmware/host.txt")
        let hostFirmwareUrl = URL(fileURLWithPath: hostFirmwarePath)
        let hostFirmwareHeaderPath = directory.appending("Resources/Firmware/hostHeader.txt")
        let hostFirmwareHeaderUrl = URL(fileURLWithPath: hostFirmwareHeaderPath)
        let hostFirmware = try String(contentsOf: hostFirmwareUrl)
        let hostHeaderFirmware = try String(contentsOf: hostFirmwareHeaderUrl)
        
        let finalSourceCode = hostHeaderFirmware + sourceCode + hostFirmware
        
        return finalSourceCode
    }
    
    static func publishEvent(request: Request, eventName: String, ttl: Int = 1800, data eventData: String? = nil, isPrivate: Bool? = nil, redirect: String, promise: EventLoopPromise<ServerResponse>) throws {
        guard let accessToken = Admin.settings.particleAccessToken else {
            throw ServerAbort(.badRequest, reason: "Particle access token not set")
        }
        let requestClient = try request.make(Client.self)
        let headers = HTTPHeaders([
            ("Authorization", "Bearer \(accessToken)"),
            ("Accept", "application/json"),
            ("Content-Type", "application/json")
        ])
        var content: [String: String] = [
            "name": eventName,
            "ttl": String(ttl)
        ]
        if let eventData = eventData {
            content["data"] = eventData
        }
        if let isPrivate = isPrivate {
            content["private"] = (isPrivate ? "true" : "false")
        }
        requestClient.post("\(Constants.Particle.url)/devices/events", headers: headers, beforeSend: { request in
            try request.content.encode(content)
        }).do { response in
            guard response.http.status.isValid else {
                return promise.fail(error: ServerAbort(response.http.status, reason: "Particle reponse error"))
            }
            if request.jsonResponse {
                return promise.succeed(result: ServerResponse.response(response))
            }
            return promise.succeed(result: ServerResponse.response(request.redirect(to: redirect)))
        }.catch { error in
            return promise.fail(error: error)
        }
    }
    
    static func flash(request: Request, hostDeviceId: ObjectId, hostDevice: Document, promise: EventLoopPromise<ServerResponse>) throws {
        struct ErrorResponse: Codable {
            let error: String
        }
        struct SuccessResponse: Codable {
            let ok: Bool
            let message: String
        }
        struct SourceCode: Codable {
            let source: File
        }
        guard let accessToken = Admin.settings.particleAccessToken else {
            throw ServerAbort(.notFound, reason: "Particle access token not set")
        }
        let deviceId = try hostDevice.extractString("deviceId")
        let sourceCodeString = try HostDevice.sourceCode(hostDevice, sharedContainer: request.sharedContainer)
        let sourceCode = SourceCode(source: File(data: sourceCodeString, filename: "source.ino"))
        
        let requestClient = try request.make(Client.self)
        
        requestClient.put("\(Constants.Particle.url)/devices/\(deviceId)?access_token=\(accessToken)", beforeSend: { request in
            try request.content.encode(sourceCode, as: MediaType.formData)
        }).do { response in
            guard response.http.status.isValid else {
                return promise.fail(error: ServerAbort(response.http.status, reason: "Particle reponse error"))
            }
            if let errorResponse = try? response.content.syncDecode(ErrorResponse.self) {
                return promise.fail(error: ServerAbort(.internalServerError, reason: errorResponse.error))
            }
            do {
                let successResponse = try response.content.syncDecode(SuccessResponse.self)
                guard successResponse.ok else {
                    return promise.fail(error: ServerAbort(.internalServerError, reason: successResponse.message))
                }
                let hostDevice = try HostDevice.collection.findAndUpdate("_id" == hostDeviceId, with: ["$set": ["lastFlashedDate": Date(), "needsUpdate": false]], upserting: false, returnedDocument: .new)
                if request.jsonResponse {
                    return promise.submit(try hostDevice.makeResponse(request))
                }
                return promise.succeed(result: ServerResponse.response(request.redirect(to: "/hostDevices/\(hostDeviceId.hexString)")))
            } catch let error {
                return promise.fail(error: error)
            }
        }.catch { error in
            return promise.fail(error: error)
        }
    }
    
    static func create(name: String, deviceId: String, type: HostDevice.ParticleDeviceType, updateLedPin: Device.HostDevicePin = .d7, updateInterval: Int = 1, userId: ObjectId) throws -> Document {
        let lastDevice = try HostDevice.collection.findOne(sortedBy: ["order": .descending], projecting: [
            "_id",
            "order"
        ])
        let order = (lastDevice?["order"]?.intValue ?? -1) + 1

        var hostDevice: Document = [
            "name": name,
            "order": order,
            "needsUpdate": true,
            "updatedAt": Date(),
            "deviceId": deviceId,
            "type": type.rawValue,
            "userId": userId,
            "offline": false,
            "updateInterval": updateInterval,
            "updateLedPin": updateLedPin.rawValue
        ]

        guard let hostDeviceId = try HostDevice.collection.insert(hostDevice) as? ObjectId else {
            throw ServerAbort(.internalServerError, reason: "Could not create host device")
        }
        hostDevice["_id"] = hostDeviceId
        return hostDevice
    }
}
