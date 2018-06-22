//
//  MongoProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 3/25/17.
//

import Foundation
import Vapor
import MongoKitten

final class MongoProvider: Provider {
    
    func willBoot(_ container: Container) throws -> Future<Void> {
        Logger.debug("Mongo Provider: Will Boot Connected: \(server.isConnected)")
        return .done(on: container)
    }
    
    func register(_ services: inout Services) throws {
        
    }
    
    func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        try createIndexes()
        Logger.debug("Mongo Provider: Did Boot Connected: \(server.isConnected)")
        return .done(on: container)
    }
    
    
    // MARK: - Enums
    
    enum Error: Swift.Error {
        case config(String)
    }
    
    // MARK: - Parameters
    
    static let shared = MongoProvider()
    
    var database: MongoKitten.Database
    var server: MongoKitten.Server
    
    // MARK: - Life Cycle
    
    init() {
        do {
            Logger.debug("Starting Mongo Provider")
            let databaseName = Environment.get("MONGO_DATABASE") ?? "brew"
            let host = Environment.get("MONGO_HOST") ?? "localhost"
            let port = Environment.get("MONGO_PORT")?.intValue ?? 27017
            let credentials: MongoCredentials?
            if let username = Environment.get("MONGO_USERNAME"), let password = Environment.get("MONGO_PASSWORD") {
                credentials = MongoCredentials(username: username, password: password)
            } else {
                credentials = nil
            }
            let clientSettings = ClientSettings(host: MongoHost(hostname:host, port: UInt16(port)), sslSettings: nil, credentials: credentials, maxConnectionsPerServer: 100, defaultTimeout: TimeInterval(1800), applicationName: nil)
            server = try Server(clientSettings)
//            server.logger = PrintLogger()
//            server.whenExplaining = { explaination in
//                Logger.verbose("Explained: \(explaination)")
//            }
            database = server[databaseName]
        } catch let error {
            print(error)
            exit(1)
        }
    }
    
    // MARK: - Methods
    
    func createIndexes() throws {
        Logger.debug("Mongo Provider: Creating Indexes")
        let collections = try database.listCollections()
        var collectionNames: Set<String> = []
        for collection in collections {
            collectionNames.insert(collection.name)
        }
        if collectionNames.contains("application") {
            try migrateDatabase(clearUsers: true)
            collectionNames = []
            let collections = try database.listCollections()
            for collection in collections {
                collectionNames.insert(collection.name)
            }
        }
        if collectionNames.contains(User.collectionName) == false {
            try database.createCollection(named: User.collectionName)
        }
        if collectionNames.contains(AuthenticityToken.collectionName) == false {
            try database.createCollection(named: AuthenticityToken.collectionName)
        }
        if collectionNames.contains(AuthorizationCode.collectionName) == false {
            try database.createCollection(named: AuthorizationCode.collectionName)
        }
        if collectionNames.contains(PasswordReset.collectionName) == false {
            try database.createCollection(named: PasswordReset.collectionName)
        }
        if collectionNames.contains(AccessToken.collectionName) == false {
            try database.createCollection(named: AccessToken.collectionName)
        }
        if collectionNames.contains(Log.collectionName) == false {
            try database.createCollection(named: Log.collectionName)
        }
        if User.collection.containsIndex("email") == false {
            Logger.info("Creating User email Index")
            try User.collection.createIndex(named: "email", withParameters: .sort(field: "email", order: .ascending))
        }
        if AuthenticityToken.collection.containsIndex("ttl") == false {
            Logger.info("Creating AuthenticityToken ttl Index")
            try AuthenticityToken.collection.createIndex(named: "ttl", withParameters: .sort(field: "createdAt", order: .ascending), .expire(afterSeconds: 600))
        }
        if AuthorizationCode.collection.containsIndex("ttl") == false {
            Logger.info("Creating AuthorizationCode ttl Index")
            try AuthorizationCode.collection.createIndex(named: "ttl", withParameters: .sort(field: "createdAt", order: .ascending), .expire(afterSeconds: 600))
        }
        if PasswordReset.collection.containsIndex("ttl") == false {
            Logger.info("Creating PasswordReset ttl Index")
            try PasswordReset.collection.createIndex(named: "ttl", withParameters: .sort(field: "createdAt", order: .ascending), .expire(afterSeconds: 3600))
        }
        if AccessToken.collection.containsIndex("ttl") == false {
            Logger.info("Creating AccessToken ttl Index")
            try AccessToken.collection.createIndex(named: "ttl", withParameters: .sort(field: "endOfLife", order: .ascending), .expire(afterSeconds: 0))
        }
        if AccessToken.collection.containsIndex("token") == false {
            Logger.info("Creating AccessToken token Index")
            try AccessToken.collection.createIndex(named: "token", withParameters: .sort(field: "token", order: .ascending))
        }
        if AccessToken.collection.containsIndex("refreshToken") == false {
            Logger.info("Creating AccessToken refreshToken Index")
            try AccessToken.collection.createIndex(named: "refreshToken", withParameters: .sort(field: "refreshToken", order: .ascending))
        }
        if Log.collection.containsIndex("createdAt") == false {
            Logger.info("Creating Log createdAt Index")
            try Log.collection.createIndex(named: "createdAt", withParameters: .sort(field: "createdAt", order: .descending))
        }
        if Log.collection.containsIndex("type") == false {
            Logger.info("Creating Log type Index")
            try Log.collection.createIndex(named: "type", withParameters: .sort(field: "type", order: .descending))
        }
        if Log.collection.containsIndex("device") == false {
            Logger.info("Creating Log device Index")
            try Log.collection.createIndex(named: "device", withParameters: .sort(field: "deviceId", order: .descending))
        }
        Logger.debug("Mongo Provider: Creating Indexes Complete")
    }
    
    func migrateDatabase(clearUsers: Bool) throws {
        Logger.info("Migrating Database from Brew Server")
        if clearUsers {
            try? database["user"].drop()
            let userId = try User.register(credentials: EmailPassword(email: "admin@example.com", password: "admin")).id
            try BrewContainer.collection.update(to: ["$set": ["userId": userId]], multiple: true)
            try HostDevice.collection.update(to: ["$set": ["userId": userId]], multiple: true)
            let containers = try BrewContainer.collection.find(projecting: ["_id"])
            for container in containers {
                BrewContainer.updateDevices(try container.extractObjectId())
            }
        }
        try? database["installation"].drop()
        try? database["application"].drop()
        try? database["AccessToken"].drop()
        
        let devices = try Device.collection.find(projecting: [
            "_id", "deviceId", "lastTemperatureDate", "lastCycleDate"
        ])
        var addressDeviceIds: [String: ObjectId] = [:]
        var updates: [(filter: Query, to: Document, upserting: Bool, multiple: Bool)] = []
        for device in devices {
            guard let objectId = device.objectId else { continue }
            if let address = device["deviceId"] as? String {
                addressDeviceIds[address] = objectId
            }
            if let lastTemperatureDate = device["lastTemperatureDate"] as? Date {
                updates.append((filter: "_id" == objectId, to: ["$set": ["lastActionDate": lastTemperatureDate], "$unset": ["lastTemperatureDate": 1]], upserting: false, multiple: false))
            } else if let lastCycleDate = device["lastCycleDate"] as? Date {
                updates.append((filter: "_id" == objectId, to: ["$set": ["lastActionDate": lastCycleDate], "$unset": ["lastCycleDate": 1]], upserting: false, multiple: false))
            } else {
                Logger.info("Cant Update Device: \(device)")
            }
        }
        Logger.info("Migrating Database Device Addresses: \(addressDeviceIds)")
        if updates.isEmpty == false {
            Logger.info("Migrating Database Device Updates: \(updates.count) Updated: \(try Device.collection.update(bulk: updates))")
        }
        
        var logUpdates: [(filter: Query, to: Document, upserting: Bool, multiple: Bool)] = []
        for (address, deviceId) in addressDeviceIds {
            logUpdates.append((filter: "address" == address, to: ["$set": ["deviceId": deviceId]], upserting: false, multiple: true))
        }
        if logUpdates.isEmpty == false {
            Logger.info("Migrating Database Log Updates: \(logUpdates.count) Updated: \(try Log.collection.update(bulk: logUpdates))")
        }
        
        Logger.info("Migrating Database from Brew Server - Completed")
    }
}

extension MongoKitten.Collection {
    func containsIndex(_ name: String) -> Bool {
        do {
            let indexes = try listIndexes()
            for index in indexes {
                guard let indexName = index["name"] as? String else { continue }
                if name == indexName {
                    return true
                }
            }
        } catch {
            do {
                try dropIndex(named: name)
            } catch {}
            return false
        }
        return false
    }
}
