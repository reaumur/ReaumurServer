//
//  Admin+Routes.swift
//  Server
//
//  Created by BluDesign, LLC on 7/2/17.
//

import Foundation
import Vapor
import MongoKitten

struct AdminRouter {
    
    init(router: Router) {
        let adminRouter = router.grouped(AdminAuthenticationMiddleware.self)
        
        adminRouter.get(use: get)
        adminRouter.post(use: post)
        adminRouter.get("uploadInflux", use: getUploadInflux)
    }
    
    struct Settings: Content {
        let registrationEnabled: Bool?
        let secureCookie: Bool?
        let notificationEmail: String?
        let domain: String?
        let insecureDomain: String?
        let apnsBundleId: String?
        let apnsTeamId: String?
        let apnsKeyId: String?
        let apnsKeyPath: String?
        let slackWebHookUrl: String?
        let offlineMinutes: Int?
        let timeZone: String?
        var timeZones: [String]?
        var timeZoneData: String?
        var particleAccessToken: String?
        var particleAccessTokenSet: Bool?
        let mailgunFromEmail: String?
        let mailgunApiUrl: String?
        var mailgunApiKey: String?
        var mailgunApiKeySet: Bool?
        var admin: Bool?
        
        init() {
            registrationEnabled = Admin.settings.registrationEnabled
            secureCookie = Admin.settings.secureCookie
            notificationEmail = Admin.settings.notificationEmail
            domain = Admin.settings.domain
            insecureDomain = Admin.settings.insecureDomain
            apnsBundleId = Admin.settings.apnsBundleId
            apnsTeamId = Admin.settings.apnsTeamId
            apnsKeyId = Admin.settings.apnsKeyId
            apnsKeyPath = Admin.settings.apnsKeyPath
            slackWebHookUrl = Admin.settings.slackWebHookUrl
            offlineMinutes = Admin.settings.offlineMinutes
            timeZone = Admin.settings.timeZone
            particleAccessTokenSet = Admin.settings.particleAccessToken != nil
            mailgunFromEmail = Admin.settings.mailgunFromEmail
            mailgunApiUrl = Admin.settings.mailgunApiUrl
            mailgunApiKeySet = Admin.settings.mailgunApiKey != nil
        }
    }
    
    // MARK: GET
    func get(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            var settings = Settings()
            let timeZones = TimeZone.knownTimeZoneIdentifiers.sorted { $0.localizedCaseInsensitiveCompare($1) == ComparisonResult.orderedAscending }
            
            if request.jsonResponse {
                settings.timeZones = timeZones
                return promise.submit(try settings.encoded(request: request))
            }
            var timeZoneData: String = ""
            let currentTimeZone = Admin.settings.timeZone
            for timeZone in timeZones {
                let string: String
                if timeZone == currentTimeZone {
                    string = "<option value=\"\(timeZone)\" selected>\(timeZone.replacingOccurrences(of: "_", with: " "))</option>"
                } else {
                    string = "<option value=\"\(timeZone)\">\(timeZone.replacingOccurrences(of: "_", with: " "))</option>"
                }
                timeZoneData.append(string)
            }
            settings.timeZoneData = timeZoneData
            settings.admin = try? request.authentication().permission.isAdmin
            return promise.submit(try request.renderEncoded("admin", settings))
        }
    }
    
    // MARK: POST
    func post(_ request: Request) throws -> Future<ServerResponse> {
        return request.globalAsync { promise in
            let settings = try request.content.syncDecode(Settings.self)
            if let registrationEnabled = settings.registrationEnabled {
                Admin.settings.registrationEnabled = registrationEnabled
            }
            if let secureCookie = settings.secureCookie {
                Admin.settings.secureCookie = secureCookie
            }
            if let notificationEmail = settings.notificationEmail {
                Admin.settings.notificationEmail = notificationEmail
            }
            if let domain = (settings.domain?.isEmpty == true ? settings.domain : settings.domain?.url?.domain) {
                Admin.settings.domain = domain
            }
            if let insecureDomain = (settings.insecureDomain?.isEmpty == true ? settings.insecureDomain : settings.insecureDomain?.url?.domain) {
                Admin.settings.insecureDomain = insecureDomain
            }
            var apnsUpdated = false
            if let apnsBundleId = settings.apnsBundleId {
                Admin.settings.apnsBundleId = apnsBundleId
                apnsUpdated = true
            }
            if let apnsTeamId = settings.apnsTeamId {
                Admin.settings.apnsTeamId = apnsTeamId
                apnsUpdated = true
            }
            if let apnsKeyId = settings.apnsKeyId {
                Admin.settings.apnsKeyId = apnsKeyId
                apnsUpdated = true
            }
            if let apnsKeyPath = settings.apnsKeyPath {
                Admin.settings.apnsKeyPath = apnsKeyPath
                apnsUpdated = true
            }
            if let slackWebHookUrl = settings.slackWebHookUrl {
                Admin.settings.slackWebHookUrl = slackWebHookUrl
            }
            if let offlineMinutes = settings.offlineMinutes {
                Admin.settings.offlineMinutes = offlineMinutes
            }
            if let timeZoneString = settings.timeZone {
                if let timeZone = TimeZone(identifier: timeZoneString) {
                    Admin.settings.timeZone = timeZoneString
                    Formatter.longFormatter.timeZone = timeZone
                } else {
                    Logger.error("Invalid Timezone: \(timeZoneString)")
                }
            }
            if let particleAccessToken = settings.particleAccessToken, particleAccessToken.isHiddenText == false {
                Admin.settings.particleAccessToken = particleAccessToken
            }
            if let mailgunFromEmail = settings.mailgunFromEmail {
                Admin.settings.mailgunFromEmail = mailgunFromEmail
            }
            if let mailgunApiUrl = settings.mailgunApiUrl {
                Admin.settings.mailgunApiUrl = mailgunApiUrl
            }
            if let mailgunApiKey = settings.mailgunApiKey, mailgunApiKey.isHiddenText == false {
                Admin.settings.mailgunApiKey = mailgunApiKey
            }
            
            try Admin.settings.save()
            
            if apnsUpdated {
                PushProvider.startApns(container: request.sharedContainer)
            }
            return promise.succeed(result: request.serverStatusRedirect(status: .ok, to: "/admin"))
        }
    }
    
    // MARK: GET uploadInflux
    func getUploadInflux(_ request: Request) throws -> HTTPStatus {
        DispatchQueue.global().async {
            InfluxdbProiver.getUploadInflux()
        }
        return .ok
    }
}
