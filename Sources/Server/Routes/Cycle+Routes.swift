//
//  Cycle+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 10/12/17.
//

import Foundation
import Vapor
import MongoKitten
import Crypto

struct CycleRouter {
    
    init(router: Router) {
        let protectedRouter = router.grouped(AuthenticationMiddleware.self)
        
        protectedRouter.get(use: get)
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        let influxdbUrl = Admin.settings.influxdb
        return request.globalAsync { promise in
            let filteredDeviceId = try? request.query.get(at: "deviceId") as ObjectId
            let authentication = try request.authentication()
            var deviceIds: Set<ObjectId> = []
            let devices: CollectionSlice<Document>
            if authentication.permission.isAdmin == false {
                let hostDevices = try HostDevice.collection.find("userId" == authentication.userId, projecting: [
                    "_id"
                ])
                var hostDeviceIds: Set<ObjectId> = []
                for hostDevice in hostDevices {
                    guard let hostDeviceId = hostDevice.objectId else { continue }
                    hostDeviceIds.insert(hostDeviceId)
                }
                devices = try Device.collection.find(Query(aqt: AQT.in(key: "hostDeviceId", in: Array(hostDeviceIds))) && Query(aqt: AQT.in(key: "type", in: Device.DeviceType.switchValues)), projecting: [
                    "_id", "name"
                ])
                
                if let deviceId = filteredDeviceId {
                    var found = false
                    for device in devices where device.objectId == deviceId {
                        found = true
                        break
                    }
                    guard found else {
                        return promise.succeed(result: request.serverStatusRedirect(status: .forbidden, to: "/temperatures"))
                    }
                    deviceIds.insert(deviceId)
                } else {
                    for device in devices {
                        guard let deviceId = device.objectId else { continue }
                        deviceIds.insert(deviceId)
                    }
                }
                guard deviceIds.count > 0 else {
                    let context = TemplateData.dictionary([
                        "deviceData": .string("<option value=\"\"\(filteredDeviceId == nil ? "selected" : "")>All Devices</option>"),
                        "admin": .bool(authentication.permission.isAdmin)
                    ])
                    return promise.submit(try request.renderEncoded("cycles", context))
                }
            } else {
                devices = try Device.collection.find(Query(aqt: AQT.in(key: "type", in: Device.DeviceType.switchValues)), projecting: [
                    "_id", "name"
                ])
                if let deviceId = filteredDeviceId {
                    deviceIds.insert(deviceId)
                }
            }
            
            let requestClient = try request.make(Client.self)
            let headers = HTTPHeaders([
                ("Accept", "application/json")
            ])
            let deviceFilter: String
            if let deviceId = deviceIds.first {
                deviceFilter = " AND \"deviceId\"='\(deviceId.hexString)'"
            } else if deviceIds.count > 0 {
                var filterString = ""
                for deviceId in deviceIds {
                    if filterString.isEmpty {
                        filterString.append("OR \"deviceId\"='\(deviceId.hexString)'")
                    } else {
                        filterString.append(" AND (\"deviceId\"='\(deviceId.hexString)'")
                    }
                }
                filterString.append(")")
                deviceFilter = filterString
            } else {
                deviceFilter = ""
            }
            let query = try "SELECT \"turnedOn\" FROM \"brew\".\"autogen\".\"cycle\" WHERE \((filteredDeviceId == nil ? "time > now() - 12h" : "time > now() - 24h"))\(deviceFilter) GROUP BY \"deviceId\"".urlEncodedFormEncoded()
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
                do {
                    if request.jsonResponse {
                        return promise.succeed(result: ServerResponse.response(request.rawJsonResponse(body: response.http.body)))
                    }
                    if let data = response.http.body.data, let dictionary = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: 0)) as? [String: Any], let result = (dictionary["results"] as? [[String: Any]])?.first {
                        var allValues: [(deviceId: ObjectId, value: Bool, date: Date)] = []
                        if let series = result["series"] as? [[String: Any]] {
                            for group in series {
                                guard let deviceIdString = (group["tags"] as? [String: String])?["deviceId"], let deviceId = try? ObjectId(deviceIdString), let values = group["values"] as? [[Any]] else { continue }
                                for value in values {
                                    guard let dateString = value.first as? String, let date = Formatter.iso8601.date(from: dateString), let itemValue = value.last as? Bool else { continue }
                                    allValues.append((deviceId: deviceId, value: itemValue, date: date))
                                }
                            }
                        }
                        
                        var deviceNames: [ObjectId: String] = [:]
                        var deviceData: String = "<option value=\"\"\(filteredDeviceId == nil ? "selected" : "")>All Devices</option>"
                        for device in devices {
                            guard let deviceId = device.objectId, let name = device["name"] as? String else { continue }
                            let string = "<option value=\"\(deviceId.hexString)\"\(deviceId == filteredDeviceId ? "selected" : "")>\(name)</option>"
                            deviceNames[deviceId] = name
                            deviceData.append(string)
                        }
                        var tableData: String = ""
                        for value in allValues {
                            let deviceName = deviceNames[value.deviceId] ?? "Unknown"
                            let string = "<tr><td>\(deviceName)</td><td>\(value.date.longString)</td><td>\((value.value ? "Turned On" : "Turned Off"))</td></tr>"
                            tableData.append(string)
                        }
                        
                        let context = TemplateData.dictionary([
                            "tableData": .string(tableData),
                            "deviceData": .string(deviceData),
                            "admin": .bool(authentication.permission.isAdmin)
                        ])
                        return promise.submit(try request.renderEncoded("cycles", context))
                        
                    } else {
                        throw ServerAbort(.internalServerError, reason: "InfluxDB invalid response")
                    }
                } catch let error {
                    return promise.fail(error: error)
                }
                }.catch { error in
                    return promise.fail(error: error)
            }
        }
    }
}
