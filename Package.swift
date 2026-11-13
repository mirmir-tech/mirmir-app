// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MirmirApp",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Mirmir", targets: ["MirmirApp"]),
        .library(name: "MirmirKit", targets: ["MirmirKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.4"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.12.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.39.0"),
        // Already resolved through grpc-swift-nio-transport; used directly for
        // certificate pinning (NIOSSL) and its SHA-256 fingerprint (Crypto).
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "6.0.0"),
    ],
    targets: [
        // Generated from Proto/mirmir.proto by scripts/generate-proto.sh.
        .target(
            name: "MirmirRPC",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        // Typed domain, transport, stores, and view models. No SwiftUI views.
        .target(
            name: "MirmirKit",
            dependencies: [
                "MirmirRPC",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .executableTarget(
            name: "MirmirApp",
            dependencies: ["MirmirKit"]
        ),
        .testTarget(
            name: "MirmirKitTests",
            dependencies: ["MirmirKit"]
        ),
    ]
)
