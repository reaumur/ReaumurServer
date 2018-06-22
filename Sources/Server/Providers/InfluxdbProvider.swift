//
//  InfluxdbProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 5/17/18.
//

import Foundation
import Vapor
import MongoKitten

final class InfluxdbProiver: Provider {
    
    func willBoot(_ container: Container) throws -> Future<Void> {
        return .done(on: container)
    }
    
    func register(_ services: inout Services) throws {
        
    }
    
    func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        let requestClient = try container.make(Client.self)
        InfluxdbProiver.ping(clinet: requestClient)
        let influxdbUrl = Admin.settings.influxdb
        let promise = container.eventLoop.newPromise(Void.self)
        requestClient.get("\(influxdbUrl)/ping").do { response in
            guard response.http.status.isValid else {
                Logger.error("InfluxDB Ping Response Invalid: \(response.http.status)")
                exit(1)
            }
            Logger.debug("Influx Provider: Connected")
            promise.succeed()
        }.catch { error in
            Logger.error("InfluxDB Connect Error: \(error)")
            exit(1)
        }
        return promise.futureResult
    }
    
    static func ping(clinet requestClient: Client) {
    }
    
    static func write(deviceId: ObjectId, temperature: Double, humidity: Double? = nil, date: Date, request: Request) {
        let influxdbUrl = Admin.settings.influxdb
        do {
            let requestClient = try request.make(Client.self)
            requestClient.post("\(influxdbUrl)/write?db=brew&precision=s", beforeSend: { request in
                try request.content.encode("temperature,deviceId=\(deviceId.hexString) temperature=\(temperature) \(Int(date.timeIntervalSince1970))", as: .plainText)
            }).do { response in
                guard response.http.status.isValid else {
                    Logger.error("InfluxDB Response Invalid: \(response.http.status)")
                    return
                }
            }.catch { error in
                Logger.error("InfluxDB Error: \(error)")
            }
            if let humidity = humidity {
                requestClient.post("\(influxdbUrl)/write?db=brew&precision=s", beforeSend: { request in
                    try request.content.encode("humidity,deviceId=\(deviceId.hexString) humidity=\(humidity) \(Int(date.timeIntervalSince1970))", as: .plainText)
                }).do { response in
                    guard response.http.status.isValid else {
                        Logger.error("InfluxDB Response Invalid: \(response.http.status)")
                        return
                    }
                }.catch { error in
                    Logger.error("InfluxDB Error: \(error)")
                }
            }
        } catch let error {
            Logger.error("InfluxDB Client Error: \(error)")
        }
    }
    
    static func write(deviceId: ObjectId, turnedOn: Bool, date: Date, request: Request) {
        let influxdbUrl = Admin.settings.influxdb
        do {
            let requestClient = try request.make(Client.self)
            requestClient.post("\(influxdbUrl)/write?db=brew&precision=s", beforeSend: { request in
                try request.content.encode("cycle,deviceId=\(deviceId.hexString) turnedOn=\((turnedOn ? "true" : "false")) \(Int(date.timeIntervalSince1970))", as: .plainText)
            }).do { response in
                guard response.http.status.isValid else {
                    Logger.error("InfluxDB Response Invalid: \(response.http.status)")
                    return
                }
                }.catch { error in
                    Logger.error("InfluxDB Error: \(error)")
            }
        } catch let error {
            Logger.error("InfluxDB Client Error: \(error)")
        }
    }
    
    static func getUploadInflux() {
        do {
            let directory = try MainApplication.shared.application.make(DirectoryConfig.self).workDir
            let temperatureUrl = URL(fileURLWithPath: directory.appending("Resources/temperature.txt"))
            let humidityUrl = URL(fileURLWithPath: directory.appending("Resources/humidity.txt"))
            let cycleUrl = URL(fileURLWithPath: directory.appending("Resources/cycle.txt"))
            try? FileManager.default.removeItem(at: temperatureUrl)
            try? FileManager.default.removeItem(at: humidityUrl)
            try? FileManager.default.removeItem(at: cycleUrl)
            Logger.info("InfluxDB Export Start - Output Path: \(temperatureUrl)")
            guard let temperatureOutputStream = OutputStream(url: temperatureUrl, append: true) else {
                throw ServerAbort(.internalServerError, reason: "Unable to open temperature file")
            }
            guard let humidityOutputStream = OutputStream(url: humidityUrl, append: true) else {
                throw ServerAbort(.internalServerError, reason: "Unable to open humidity file")
            }
            temperatureOutputStream.open()
            humidityOutputStream.open()
            func append(outputStream: OutputStream) {
                let appendString = "# DDL\nCREATE DATABASE brew\n\n# DML\n# CONTEXT-DATABASE:brew\n# CONTEXT-RETENTION-POLICY:autogen\n"
                outputStream.write(appendString, maxLength: appendString.count)
            }
            append(outputStream: temperatureOutputStream)
            append(outputStream: humidityOutputStream)
            
            let temperatures = try MongoProvider.shared.database["temperature"].find(sortedBy: ["createdAt": .descending], withBatchSize: 10000)
            for temperature in temperatures {
                guard let deviceId = temperature["deviceId"] as? ObjectId, let temperatureValue = temperature["temperature"] as? Double, let createdAt = temperature["createdAt"] as? Date else { continue }
                let string = "temperature,deviceId=\(deviceId.hexString) temperature=\(temperatureValue) \(Int(createdAt.timeIntervalSince1970))\n"
                guard temperatureOutputStream.write(string, maxLength: string.count) > 0 else {
                    throw ServerAbort(.internalServerError, reason: "Unable to write to temperature file")
                }
                if let humidity = temperature["humidity"] as? Double {
                    let string = "humidity,deviceId=\(deviceId.hexString) humidity=\(humidity) \(Int(createdAt.timeIntervalSince1970))\n"
                    guard humidityOutputStream.write(string, maxLength: string.count) > 0 else {
                        throw ServerAbort(.internalServerError, reason: "Unable to write to humidity file")
                    }
                }
            }
            
            temperatureOutputStream.close()
            humidityOutputStream.close()
            
            guard let cycleOutputStream = OutputStream(url: cycleUrl, append: true) else {
                throw ServerAbort(.internalServerError, reason: "Unable to open cycle file")
            }
            cycleOutputStream.open()
            append(outputStream: cycleOutputStream)
            let cycles = try MongoProvider.shared.database["cycle"].find(sortedBy: ["createdAt": .descending], withBatchSize: 10000)
            for cycle in cycles {
                guard let deviceId = cycle["deviceId"] as? ObjectId, let turnedOn = cycle["turnedOn"] as? Bool, let createdAt = cycle["createdAt"] as? Date else { continue }
                let string = "cycle,deviceId=\(deviceId.hexString) turnedOn=\((turnedOn ? "true" : "false")) \(Int(createdAt.timeIntervalSince1970))\n"
                guard cycleOutputStream.write(string, maxLength: string.count) > 0 else {
                    throw ServerAbort(.internalServerError, reason: "Unable to write to temperature file")
                }
            }
            cycleOutputStream.close()
            
            Logger.info("InfluxDB Export Complete")
        } catch let error {
            Logger.error("InfluxDB Export Error: \(error)")
        }
    }
}
