// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Server",
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "3.1.0")),
        .package(url: "https://github.com/vapor/http", .upToNextMajor(from: "3.1.0")),
        .package(url: "https://github.com/vapor/jwt.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/vapor/leaf.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/vapor/console.git", .upToNextMajor(from: "3.1.0")),
        .package(url: "https://github.com/vapor/websocket", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/vapor/validation.git", .upToNextMajor(from: "2.1.0")),
        .package(url: "https://github.com/vapor-community/clibressl.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/vapor-community/copenssl.git", .upToNextMajor(from: "1.0.0-rc")),
        .package(url: "https://github.com/OpenKitten/MongoKitten.git", .upToNextMajor(from: "4.0.0")),
        .package(url: "https://github.com/BrettRToomey/Jobs.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/reaumur/CCurl.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/reaumur/HAP.git",  .branch("swift-nio-http"))
    ],
    targets: [
        .target(name: "Server",
            dependencies: [
                "Vapor",
                "JWT",
                "Leaf",
                "Console",
                "WebSocket",
                "Validation",
                "CLibreSSL",
                "COpenSSL",
                "MongoKitten",
                "Jobs",
                "CCurl",
                "HAP"
            ],
            exclude: [
                "Config",
                "Deploy",
                "Public",
                "Resources",
                "Tests",
                "Database"
        ]),
        .target(name: "App", dependencies: ["Server"])
    ]
)
