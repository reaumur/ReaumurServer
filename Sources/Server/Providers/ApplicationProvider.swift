//
//  MainApplicationProvider.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor
import Jobs

final class MainApplicationProvider: Provider {
    
    func register(_ services: inout Services) throws {
        
    }
    
    func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        Logger.info("Starting Offline Device Check")
        Jobs.add(interval: .seconds(60)) {
            Device.checkOfflineStatus()
        }
        return .done(on: container)
    }
}
