import MirmirKit
import SwiftUI

/// A search result's Download in the models table: the same rounded button
/// for every repository. A GGUF repository with several quantizations adds a
/// chevron listing each with its size and fit; picking one chooses it for
/// the inspector too, and the button downloads the chosen one.
struct HubDownload: View {
    let result: CatalogModel
    let choices: VariantChoices
    let model: AppModel
    let start: (String) -> Void

    var body: some View {
        let variant = choices.variant(of: result)
        let pullID = result.pullID(for: variant)
        if let download = model.downloads[pullID] {
            ModelStatus(load: nil, download: download, loadability: .loadable, state: .available)
        } else {
            let downloaded = model.isDownloaded(result, variant: variant)
            DownloadButton(
                title: title(variant, downloaded: downloaded),
                help: help(pullID),
                downloaded: downloaded,
                action: { start(pullID) },
                options: result.variants.count > 1 ? options(chosen: variant) : nil
            )
        }
    }

    private func title(_ variant: CatalogVariant?, downloaded: Bool) -> String {
        // A single quantization needs no name; several name the chosen one.
        let name = result.variants.count > 1 ? variant.map { " \($0.name)" } ?? "" : ""
        return (downloaded ? "Downloaded" : "Download") + name
    }

    private func help(_ pullID: String) -> String {
        // The Hub marks a repository gated for everyone; whether this
        // server's token was granted access shows only when it downloads.
        if result.gated { return "Gated repository: accept its terms on Hugging Face and add your token in Configuration." }
        return result.variants.count > 1 ? "Download \(pullID); the arrow chooses another quantization" : "Download \(pullID)"
    }

    private func options(chosen: CatalogVariant?) -> some View {
        ForEach(result.variants) { option in
            Button {
                choices.choose(option.name, for: result)
            } label: {
                if option.name == chosen?.name {
                    Label(menuLabel(option), systemImage: "checkmark")
                } else {
                    Text(menuLabel(option))
                }
            }
        }
    }

    private func menuLabel(_ variant: CatalogVariant) -> String {
        variant.label(defaultVariant: result.defaultVariant) + variant.memoryFit.marker
    }
}

/// A rounded, tinted button; with `options`, a chevron beside the title opens
/// them in a menu while the title keeps its action. Once downloaded, the
/// title is a green, inert mark and only the chevron still responds.
struct DownloadButton<Options: View>: View {
    let title: String
    let help: String
    let downloaded: Bool
    let action: () -> Void
    let options: Options?

    var body: some View {
        let tint = downloaded ? Palette.success : Palette.signal
        HStack(spacing: 0) {
            Button(action: action) {
                Text(title).padding(.leading, 10).padding(.trailing, options == nil ? 10 : 6)
            }
            .buttonStyle(CapsulePartStyle(tint: tint))
            .disabled(downloaded)
            if let options {
                Rectangle().fill(tint.opacity(0.3)).frame(width: 1).padding(.vertical, 4)
                Menu {
                    options
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .menuStyle(.button)
                .buttonStyle(CapsulePartStyle(tint: tint))
                .menuIndicator(.hidden)
                .frame(width: 22)
                .help("Choose a quantization")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(tint)
        .frame(height: 20)
        .background(Palette.soft(tint))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.25)))
        .contentShape(Capsule())
        .fixedSize()
        .help(help)
    }
}

/// One part of `DownloadButton`: its label on the shared capsule, darker
/// while pressed.
private struct CapsulePartStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? tint.opacity(0.15) : .clear)
    }
}
