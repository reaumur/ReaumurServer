//
//  Particle+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 10/22/17.
//

import Foundation
import Vapor
import MongoKitten

class ParticleRouter {
    
    struct ParticleDevice: Codable, Content {
        let id: String
        let name: String?
        let serial_number: String?
        let last_app: String?
        let last_ip_address: String?
        let last_heard: String?
        let product_id: Int?
        let platform_id: Int?
        let connected: Bool?
        let cellular: Bool?
        let iccid: String?
        let imei: String?
        let system_firmware_version: String?
        let default_build_target: String?
        let current_build_target: String?
        let status: String?
    }
    
    init(router: Router) {
        let adminRouter = router.grouped(AdminAuthenticationMiddleware.self)
        
        adminRouter.get("devices", use: getDevices)
        adminRouter.get("devices", String.parameter, use: getDevicesParticleDevice)
        adminRouter.post("devices", String.parameter, use: postDevicesParticleDevice)
    }
    
    // MARK: GET
    func getDevices(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let authentication = try request.authentication()
            guard let accessToken = Admin.settings.particleAccessToken else {
                throw ServerAbort(.notFound, reason: "Particle access token not set")
            }
            
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Authorization", "Bearer \(accessToken)"),
                ("Accept", "application/json")
            ])
            requestClient.get("\(Constants.Particle.url)/devices", headers: headers).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "Particle reponse error"))
                }
                do {
                    let particleDevices = try response.content.syncDecode([ParticleDevice].self)
                    
                    if request.jsonResponse {
                        return promise.submit(try particleDevices.encoded(request: request))
                    }
                    let hostDevices = try HostDevice.collection.find(projecting: [
                        "_id",
                        "name",
                        "deviceId"
                    ])
                    var hostDeviceNames: [String: String] = [:]
                    for hostDevice in hostDevices {
                        guard let hostDeviceId = hostDevice["deviceId"] as? String, let name = hostDevice["name"] as? String else { continue }
                        hostDeviceNames[hostDeviceId] = name
                    }
                    
                    var tableData: String = ""
                    for particleDevice in particleDevices {
                        let name = particleDevice.name ?? "Unknown"
                        let connected = particleDevice.connected ?? false
                        let status = particleDevice.status?.capitalized ?? "Unknown"
                        let lastHeard: String
                        if let lastHeardString = particleDevice.last_heard, let lastHeardDate = Formatter.iso8601.date(from: lastHeardString) {
                            lastHeard = lastHeardDate.longString
                        } else {
                            lastHeard = "Unknown"
                        }
                        let hostDeviceName = hostDeviceNames[particleDevice.id] ?? "Unknown"
                        let badge = (connected ? "success" : "danger")
                        let string = "<tr onclick=\"location.href='/particle/devices/\(particleDevice.id)'\"><td>\(name)</td><td>\(hostDeviceName)</td><td>\(status)</td><td>\(lastHeard)</td><td><span class=\"badge badge-\(badge)\">\((connected ? "Yes" : "No"))</span></td></tr>"
                        tableData.append(string)
                    }
                    let context = TemplateData.dictionary([
                        "tableData": .string(tableData),
                        "admin": .bool(authentication.permission.isAdmin)
                    ])
                    return promise.submit(try request.renderEncoded("particleDevices", context))
                } catch let error {
                    return promise.fail(error: error)
                }
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
    
    // MARK: GET :particleDeviceId
    func getDevicesParticleDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let particleDeviceId = try request.parameters.next(String.self)
            let authentication = try request.authentication()
            guard let accessToken = Admin.settings.particleAccessToken else {
                throw ServerAbort(.notFound, reason: "Particle access token not set")
            }
            
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Authorization", "Bearer \(accessToken)"),
                ("Accept", "application/json")
            ])
            requestClient.get("\(Constants.Particle.url)/devices/\(particleDeviceId)", headers: headers).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "Particle reponse error"))
                }
                do {
                    let particleDevice = try response.content.syncDecode(ParticleDevice.self)
                    
                    if request.jsonResponse {
                        return promise.submit(try particleDevice.encoded(request: request))
                    }
                    
                    let hostDevice = try HostDevice.collection.findOne("deviceId" == particleDeviceId, projecting: [
                        "_id",
                        "name"
                    ])
                    let hostDeviceName = (hostDevice == nil ? "None" : hostDevice?["name"] as? String ?? "")
                    
                    let lastHeard: String
                    if let lastHeardString = particleDevice.last_heard, let lastHeardDate = Formatter.iso8601.date(from: lastHeardString) {
                        lastHeard = lastHeardDate.longString
                    } else {
                        lastHeard = "Unknown"
                    }
                    let connectedData = "<span class=\"badge badge-\((particleDevice.connected == true ? "success" : "danger"))\">\((particleDevice.connected == true ? "Yes" : "No"))</span>"
                    
                    let data: [String: TemplateData] = [
                        "deviceId": .string(particleDeviceId),
                        "hostDevice": .string(hostDeviceName),
                        "name": .string(particleDevice.name ?? "None"),
                        "admin": .bool(authentication.permission.isAdmin),
                        "defaultBuildTarget": .string(particleDevice.default_build_target ?? "Unknown"),
                        "systemFirmwareVersion": .string(particleDevice.system_firmware_version ?? "Unknown"),
                        "currentBuildTarget": .string(particleDevice.current_build_target ?? "current_build_target"),
                        "lastIpAddress": .string(particleDevice.last_ip_address ?? "None"),
                        "lastHeard": .string(lastHeard),
                        "status": .string(particleDevice.status?.capitalized ?? "Unknown"),
                        "connected": .string(connectedData),
                        "cellular": .string(particleDevice.cellular == true ? "Yes" : "No"),
                        "iccid": .string(particleDevice.iccid ?? "None"),
                        "imei": .string(particleDevice.imei ?? "None"),
                        "canRegister": .bool(hostDevice == nil)
                    ]
                    let context = TemplateData.dictionary(data)
                    return promise.submit(try request.renderEncoded("particleDevice", context))
                } catch let error {
                    return promise.fail(error: error)
                }
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
    
    // MARK: POST :particleDeviceId
    func postDevicesParticleDevice(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let particleDeviceId = try request.parameters.next(String.self)
            guard let accessToken = Admin.settings.particleAccessToken else {
                throw ServerAbort(.notFound, reason: "Particle access token not set")
            }
            
            let action = try? request.content.syncGet(String.self, at: "action")
            if  action == "register" {
                let authentication = try request.authentication()
                
                let requestClient = try request.make(Client.self)
                let headers = HTTPHeaders([
                    ("Authorization", "Bearer \(accessToken)"),
                    ("Accept", "application/json")
                ])
                requestClient.get("\(Constants.Particle.url)/devices/\(particleDeviceId)", headers: headers).do { response in
                    guard response.http.status.isValid else {
                        return promise.fail(error: ServerAbort(response.http.status, reason: "Particle reponse error"))
                    }
                    do {
                        let particleDevice = try response.content.syncDecode(ParticleDevice.self)
                        
                        let name = particleDevice.name ?? "Host"
                        guard let platformId = particleDevice.platform_id, let type = HostDevice.ParticleDeviceType(platformId: platformId) else {
                            throw ServerAbort(.notFound, reason: "Invalid platform ID required")
                        }
                        
                        let hostDevice = try HostDevice.create(name: name, deviceId: particleDevice.id, type: type, userId: authentication.userId)
                        let hostDeviceId = try hostDevice.extractObjectId()
                        
                        if request.jsonResponse {
                            return promise.submit(try hostDevice.makeResponse(request))
                        }
                        return promise.succeed(result: request.serverRedirect(to: "/hostDevices/\(hostDeviceId.hexString)"))
                    } catch let error {
                        return promise.fail(error: error)
                    }
                }.catch { error in
                        return promise.fail(error: error)
                }
            }
            
            let name = try request.content.syncGet(String.self, at: "name")
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Authorization", "Bearer \(accessToken)"),
                ("Accept", "application/json"),
                ("Content-Type", "application/json")
            ])
            let content: [String: String] = [
                "name": name
            ]
            requestClient.put("\(Constants.Particle.url)/devices/\(particleDeviceId)", headers: headers, beforeSend: { request in
                try request.content.encode(content)
            }).do { response in
                guard response.http.status.isValid else {
                    return promise.fail(error: ServerAbort(response.http.status, reason: "Particle reponse error"))
                }
                if request.jsonResponse {
                    return promise.succeed(result: ServerResponse.response(response))
                }
                return promise.succeed(result: ServerResponse.response(request.redirect(to: "/particle/devices/\(particleDeviceId)")))
            }.catch { error in
                return promise.fail(error: error)
            }
        }
    }
}
