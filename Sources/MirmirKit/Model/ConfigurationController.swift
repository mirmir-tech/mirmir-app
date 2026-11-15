import Foundation
import Observation

/// Drives the Server settings of the current instance: reads its
/// configuration and applies one change at a time. mirmir validates every
/// change; a refusal is shown as the server words it.
@MainActor
@Observable
public final class ConfigurationController {
    public private(set) var configuration: ServerConfiguration?
    /// The instance the configuration belongs to.
    public private(set) var instanceID: UUID?
    public private(set) var error: String?
    /// The server's answer to the last change, such as a token's account.
    public private(set) var message: String?
    public private(set) var working = false
    /// A change was saved that takes effect when the server restarts.
    public private(set) var restartPending = false

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    #if DEBUG
    /// Sample settings for previews: refresh leaves them alone.
    public static func preview(_ model: AppModel, restartPending: Bool = false) -> ConfigurationController {
        let controller = ConfigurationController(model: model)
        controller.configuration = PreviewData.configuration.managedByApp()
        controller.instanceID = model.currentInstanceID
        controller.restartPending = restartPending
        return controller
    }
    #endif

    /// Whether the app can restart the server whose settings are shown: only
    /// the bundled server it started.
    public var canRestartServer: Bool {
        model.currentInstance.isThisMac && model.supervisor.ownership.isRunning
    }

    public func refresh() async {
        // Previews show the sample settings they were given.
        guard !model.isPreview else { return }
        let instance = model.currentInstance
        if instance.id != instanceID {
            configuration = nil
            message = nil
            restartPending = false
            instanceID = instance.id
        }
        guard let connection = model.connection else {
            error = "\(instance.name) is not connected."
            return
        }
        working = true
        defer { working = false }
        do {
            let configuration = try await connection.configuration()
            guard model.isCurrent(connection) else { return }
            self.configuration = adapted(configuration, thisMac: instance.isThisMac)
            error = nil
        } catch {
            guard model.isCurrent(connection) else { return }
            self.error = error.localizedDescription
        }
    }

    /// Applies a change; returns whether the server accepted it.
    @discardableResult
    public func apply(_ change: ConfigurationChange) async -> Bool {
        let instance = model.currentInstance
        guard let connection = model.connection else {
            error = "\(instance.name) is not connected."
            return false
        }
        working = true
        defer { working = false }
        do {
            let update = try await connection.updateConfiguration(change)
            guard model.isCurrent(connection) else { return false }
            configuration = adapted(update.configuration, thisMac: instance.isThisMac)
            instanceID = instance.id
            message = update.message.isEmpty ? nil : update.message
            if update.restartRequired { restartPending = true }
            error = nil
            return true
        } catch {
            guard model.isCurrent(connection) else { return false }
            self.error = error.localizedDescription
            message = nil
            return false
        }
    }

    /// Restarts the bundled server so saved settings take effect.
    public func restartServer() {
        guard canRestartServer else { return }
        restartPending = false
        message = nil
        model.restartServer()
    }

    public func clearError() {
        error = nil
    }

    /// This Mac is always the bundled server in the app's container.
    private func adapted(_ configuration: ServerConfiguration, thisMac: Bool) -> ServerConfiguration {
        thisMac ? configuration.managedByApp() : configuration
    }
}
