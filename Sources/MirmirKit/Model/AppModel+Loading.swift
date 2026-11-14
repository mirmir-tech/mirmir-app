import Foundation

// Loading, unloading and inspecting models, and saving what a model loads
// with. `inspections` holds each model's inspection at its saved context; an
// estimate for a candidate context (`estimate`) is returned, never stored.

extension AppModel {
    /// Loads a model. A given `context` is saved for it and used by this
    /// load; without one (the menu bar's Switch) the saved context is used.
    /// Pass a context only when the model's inspection reports one: older
    /// servers drop it.
    public func load(_ selector: String, context: ContextChoice? = nil) {
        guard let connection else { return }
        loads[selector] = LoadProgress(phase: "queued", current: 0, total: nil, detail: "", finished: false)
        Task { await load(selector, context: context, on: connection) }
    }

    /// Unloads the model served as `serving`, then loads `selector` with
    /// `context`, so a changed context applies now.
    public func reload(_ selector: String, serving: String, context: ContextChoice) {
        guard let connection else { return }
        loads[selector] = LoadProgress(phase: "unloading", current: 0, total: nil, detail: "", finished: false)
        Task {
            do {
                _ = try await connection.unload(selector: serving)
            } catch {
                report(error, "Unloading \(serving) failed", from: connection)
                if isCurrent(connection) { loads[selector] = nil }
                return
            }
            await load(selector, context: context, on: connection)
        }
    }

    public func unload(_ selector: String) {
        guard let connection else { return }
        Task {
            do {
                _ = try await connection.unload(selector: selector)
            } catch {
                report(error, "Unloading \(selector) failed", from: connection)
            }
            await refreshInspection(selector, on: connection)
            try? await refreshModels(connection)
        }
    }

    public func inspect(_ selector: String) async {
        guard let connection else { return }
        do {
            let inspection = try await connection.inspect(selector: selector)
            if isCurrent(connection) { inspections[selector] = inspection }
        } catch {
            guard !isPreview else { return }
            report(error, "Inspecting \(selector) failed", from: connection)
        }
    }

    /// The memory the model would need with `context`, for a choice not yet
    /// saved. Leaves `inspections` alone; nil when the server cannot say.
    public func estimate(_ selector: String, context: ContextChoice) async -> MemoryEstimate? {
        guard let connection else { return nil }
        do {
            return try await connection.inspect(selector: selector, context: context).memory
        } catch {
            if !isPreview { report(error, "Estimating memory for \(selector) failed", from: connection) }
            return nil
        }
    }

    /// Saves generation defaults, a context for the model's next load, or
    /// both, then shows what the server saved.
    public func updateSettings(_ selector: String, _ settings: GenerationSettings?, context: ContextChoice? = nil) async {
        guard let connection, settings != nil || context != nil else { return }
        do {
            try await connection.updateSettings(selector: selector, settings: settings, context: context)
            let inspection = try await connection.inspect(selector: selector)
            if isCurrent(connection) { inspections[selector] = inspection }
        } catch {
            report(error, "Saving settings failed", from: connection)
        }
    }

    func setLoad(_ selector: String, _ progress: LoadProgress, from connection: RuntimeConnection) {
        if isCurrent(connection) { loads[selector] = progress }
    }

    private func load(_ selector: String, context: ContextChoice?, on connection: RuntimeConnection) async {
        do {
            try await connection.load(selector: selector, context: context) { progress in
                await self.setLoad(selector, progress, from: connection)
            }
        } catch {
            report(error, "Loading \(selector) failed", from: connection)
        }
        if isCurrent(connection) { loads[selector] = nil }
        // A load saves its context and changes the resident one.
        await refreshInspection(selector, on: connection)
        try? await refreshModels(connection)
    }

    /// Re-inspects a model whose inspection is shown, as residency changes
    /// its estimate and resident context.
    private func refreshInspection(_ selector: String, on connection: RuntimeConnection) async {
        guard isCurrent(connection), inspections[selector] != nil else { return }
        guard let inspection = try? await connection.inspect(selector: selector) else { return }
        if isCurrent(connection) { inspections[selector] = inspection }
    }
}
