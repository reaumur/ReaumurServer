//
//  MainApplication+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 3/24/17.
//

import Foundation
import Vapor

extension MainApplication {
    
    // MARK: - Methods
    
    static func routes() -> EngineRouter {
        let router = EngineRouter.default()
        router.get { request -> Response in
            return request.redirect(to: "/containers")
        }
        
        _ = AdminRouter(router: router.grouped("admin"))
        _ = BrewClientRouter(router: router.grouped("clients"))
        _ = BrewContainerRouter(router: router.grouped("containers"))
        _ = CycleRouter(router: router.grouped("cycles"))
        _ = DeviceRouter(router: router.grouped("devices"))
        _ = HostDeviceRouter(router: router.grouped("hostDevices"))
        _ = LogRouter(router: router.grouped("logs"))
        _ = NotificationRouter(router: router.grouped("notifications"))
        _ = OAuthRouter(router: router.grouped("oauth"))
        _ = ParticleRouter(router: router.grouped("particle"))
        _ = PushDeviceRouter(router: router.grouped("pushDevices"))
        _ = TemperatureRouter(router: router.grouped("temperatures"))
        _ = UserRouter(router: router.grouped("users"))
        
        return router
    }
}
