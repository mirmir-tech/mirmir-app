import Foundation
import MirmirRPC

extension RemoteKeyScope {
    init?(_ wire: Mirmir_V1_RemoteKeyScope) {
        switch wire {
        case .use: self = .use
        case .control: self = .control
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    var wire: Mirmir_V1_RemoteKeyScope {
        switch self {
        case .use: .use
        case .control: .control
        }
    }
}

extension RemoteKey {
    init(_ wire: Mirmir_V1_RemoteKey) {
        self.init(
            id: wire.id,
            name: wire.name,
            scope: RemoteKeyScope(wire.scope),
            displayPrefix: wire.displayPrefix,
            createdAt: Date(unixMilliseconds: wire.createdAtUnixMs),
            lastUsedAt: wire.hasLastUsedAtUnixMs ? Date(unixMilliseconds: wire.lastUsedAtUnixMs) : nil
        )
    }
}

extension RemoteAccessStatus {
    init(_ wire: Mirmir_V1_RemoteAccessStatus) {
        let listener = wire.hasListener ? wire.listener : nil
        self.init(
            bind: wire.bind.isEmpty ? nil : wire.bind,
            listener: listener.map { listener in
                RemoteListener(
                    address: listener.address,
                    fingerprint: CertificateFingerprint(listener.certificateFingerprint),
                    certificate: CertificateSource(listener.certificateSource)
                )
            },
            error: wire.error.isEmpty ? nil : wire.error,
            keys: wire.keys.map(RemoteKey.init),
            clients: wire.clients.map { client in
                RemoteClient(
                    keyID: client.keyID,
                    keyName: client.keyName,
                    scope: RemoteKeyScope(client.scope),
                    peerAddress: client.peerAddress,
                    firstSeen: Date(unixMilliseconds: client.firstSeenUnixMs),
                    lastSeen: Date(unixMilliseconds: client.lastSeenUnixMs),
                    requests: client.requests
                )
            }
        )
    }
}

extension CertificateSource {
    init?(_ wire: Mirmir_V1_RemoteCertificateSource) {
        switch wire {
        case .selfSigned: self = .selfSigned
        case .configured: self = .configured
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}
