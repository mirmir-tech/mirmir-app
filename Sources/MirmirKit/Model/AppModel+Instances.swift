import Foundation

/// Saving, editing and removing instances. A remote server's chats belong to
/// its identity (`InstanceRecord.id`), so an edit keeps that identity and a
/// removed server's chats wait for a server at the same address.
extension AppModel {
    /// Saves an instance; a remote server's API key goes to the credential
    /// store, never to `instances.json`. A server at the address of a removed
    /// one takes over that one's identity, so its chats and images return.
    public func add(_ record: InstanceRecord, key: String? = nil) {
        let record = reattached(record)
        if let key {
            do {
                try credentials.setKey(key, for: record.id)
            } catch {
                notice = error.localizedDescription
                return
            }
        }
        removedInstances.removeAll { $0.id == record.id }
        instances.append(record)
        persistInstances()
        summaries[record.id] = .checking
        Task { await probe(record) }
    }

    /// Replaces a saved remote server in place, keeping its identity and so
    /// its chats. `key` replaces the saved API key; nil keeps it. A changed
    /// address, certificate or key reconnects (or probes) the server.
    public func update(_ record: InstanceRecord, key: String? = nil) {
        guard !record.isThisMac, let index = instances.firstIndex(where: { $0.id == record.id }) else { return }
        if let key {
            do {
                try credentials.setKey(key, for: record.id)
            } catch {
                notice = error.localizedDescription
                return
            }
        }
        let reconnects = key != nil || instances[index].target != record.target
        instances[index] = record
        persistInstances()
        guard reconnects else { return }
        if record.id == currentInstanceID {
            connectCurrent()
        } else {
            summaries[record.id] = .checking
            Task { await probe(record) }
        }
    }

    /// Removes a remote server and its API key. Its chats stay saved and
    /// return when a server at the same address is added again.
    public func remove(instance id: UUID) {
        guard id != InstanceRecord.thisMacID, let record = instances.first(where: { $0.id == id }) else { return }
        instances.removeAll { $0.id == id }
        credentials.removeKey(for: id)
        summaries[id] = nil
        if chatCount(of: id) > 0 {
            removedInstances.removeAll { $0.id == id || $0.target.sameAddress(as: record.target) }
            removedInstances.append(record)
        }
        persistInstances()
        if currentInstanceID == id { select(instance: InstanceRecord.thisMacID) }
    }

    /// The saved API key of a remote server, for testing an edit that keeps it.
    public nonisolated func savedKey(for id: UUID) -> String? {
        credentials.key(for: id)
    }

    /// How many chats belong to the instance.
    public func chatCount(of id: UUID) -> Int {
        chat.conversations.count { $0.instanceID == id }
    }

    /// The record with the identity of a removed server at the same address,
    /// when there is one; else the record as given.
    func reattached(_ record: InstanceRecord) -> InstanceRecord {
        guard let removed = removedInstances.last(where: { $0.target.sameAddress(as: record.target) }),
              !instances.contains(where: { $0.id == removed.id })
        else { return record }
        return InstanceRecord(id: removed.id, name: record.name, target: record.target)
    }

    func persistInstances() {
        guard !isPreview else { return }
        do {
            try instanceFile.save(instances.filter { !$0.isThisMac })
            try removedInstanceFile.save(removedInstances)
        } catch {
            notice = "Could not save instances: \(error.localizedDescription)"
        }
    }
}

extension InstanceTarget {
    /// The same server: This Mac, or a remote server at the same host (in
    /// any case) and port, whatever certificate is trusted.
    func sameAddress(as other: InstanceTarget) -> Bool {
        switch (self, other) {
        case (.personal, .personal): true
        case (.remote(let a), .remote(let b)): a.host.lowercased() == b.host.lowercased() && a.port == b.port
        default: false
        }
    }
}
