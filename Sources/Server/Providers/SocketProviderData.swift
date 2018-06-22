//
//  SocketProviderData.swift
//  Server
//
//  Created by BluDesign, LLC on 5/13/18.
//

import Foundation
import MongoKitten

protocol SocketDataEncodable: Encodable {
    var socketFrame: SocketFrame { get }
    var type: SocketFrameHolder.FrameType { get }
}

extension SocketDataEncodable {
    var socketFrameHodler: SocketFrameHolder {
        return SocketFrameHolder(type: type, data: socketFrame)
    }
    
    var jsonValue: Any? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .init(rawValue: 0))
    }
}

struct ContainerFrame: Codable, SocketDataEncodable {
    let objectId: ObjectId
    let averageTemperature: Double?
    let averageHumidity: Double?
    let isHeating: Bool?
    let isCooling: Bool?
    let fanActive: Bool?
    let updatedAt: Date?
    let lastActionDate: Date?
    
    var socketFrame: SocketFrame {
        return .container(container: self)
    }
    var type: SocketFrameHolder.FrameType {
        return .container
    }
}

struct TemperatureFrame: Codable, SocketDataEncodable {
    let objectId: ObjectId
    let deviceId: String
    let createdAt: Date
    let temperature: Double
    let interval: Int
    let humididty: Double?
    let container: ContainerFrame?
    
    var socketFrame: SocketFrame {
        return .temperature(temperature: self)
    }
    var type: SocketFrameHolder.FrameType {
        return .temperature
    }
}

struct CycleFrame: Codable, SocketDataEncodable {
    let objectId: ObjectId
    let deviceId: String
    let createdAt: Date
    let turnedOn: Bool
    let container: ContainerFrame?
    
    var socketFrame: SocketFrame {
        return .cycle(cycle: self)
    }
    var type: SocketFrameHolder.FrameType {
        return .cycle
    }
}

struct HostDeviceFrame: Codable, SocketDataEncodable {
    let objectId: ObjectId
    let updatedAt: Date?
    let pingedAt: Date?
    let offline: Bool?
    
    var socketFrame: SocketFrame {
        return .hostDevice(hostDevice: self)
    }
    var type: SocketFrameHolder.FrameType {
        return .hostDevice
    }
}

struct DeviceFrame: Codable, SocketDataEncodable {
    let objectId: ObjectId
    let turnedOn: Bool?
    let lastTemperature: Double?
    let lastHumidity: Double?
    let lastActionDate: Date?
    let updatedAt: Date?
    let offline: Bool?
    let assigned: Bool?
    let outsideTemperature: Bool?
    
    var socketFrame: SocketFrame {
        return .device(device: self)
    }
    var type: SocketFrameHolder.FrameType {
        return .device
    }
}

enum SocketFrame {
    case temperature(temperature: TemperatureFrame)
    case cycle(cycle: CycleFrame)
    case hostDevice(hostDevice: HostDeviceFrame)
    case container(container: ContainerFrame)
    case device(device: DeviceFrame)
    
    var jsonValue: Any? {
        switch self {
        case let .temperature(socketData): return socketData.jsonValue
        case let .cycle(socketData): return socketData.jsonValue
        case let .hostDevice(socketData): return socketData.jsonValue
        case let .container(socketData): return socketData.jsonValue
        case let .device(socketData): return socketData.jsonValue
        }
    }
}

struct SocketFrameHolder: Codable {
    enum FrameType: Int, Codable {
        case ping = 1
        case pong = 2
        case temperature = 3
        case cycle = 4
        case hostDevice = 5
        case container = 6
        case device = 7
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case data
    }
    
    let type: FrameType
    let data: SocketFrame?
    
    init(type: FrameType, data: SocketFrame? = nil) {
        self.type = type
        self.data = data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(FrameType.self, forKey: .type)
        switch type {
        case .temperature: data = try? container.decode(TemperatureFrame.self, forKey: .data).socketFrame
        case .cycle: data = try? container.decode(CycleFrame.self, forKey: .data).socketFrame
        case .hostDevice: data = try? container.decode(HostDeviceFrame.self, forKey: .data).socketFrame
        case .container: data = try? container.decode(ContainerFrame.self, forKey: .data).socketFrame
        case .device: data = try? container.decode(DeviceFrame.self, forKey: .data).socketFrame
        default: data = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let data = data {
            switch data {
            case let .temperature(socketData): try container.encode(socketData, forKey: .data)
            case let .cycle(socketData): try container.encode(socketData, forKey: .data)
            case let .hostDevice(socketData): try container.encode(socketData, forKey: .data)
            case let .container(socketData): try container.encode(socketData, forKey: .data)
            case let .device(socketData): try container.encode(socketData, forKey: .data)
            }
        }
    }
    
    var stringValue: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
