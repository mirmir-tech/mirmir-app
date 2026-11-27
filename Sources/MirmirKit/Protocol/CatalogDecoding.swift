import MirmirRPC

extension CatalogVariant {
    init(_ wire: Mirmir_V1_CatalogVariant) {
        self.init(
            name: wire.name,
            size: VariantSize(kind: wire.sizeKind, bytes: wire.hasWeightBytes ? wire.weightBytes : nil),
            requiredBytes: wire.hasRequiredBytes ? wire.requiredBytes : nil,
            memoryFit: MemoryFit(wire: wire.memoryFit),
            downloaded: wire.downloaded
        )
    }
}

extension VariantSize {
    /// `size_kind` with the size it qualifies; a kind without a size is
    /// unknown.
    init(kind: String, bytes: UInt64?) {
        switch (kind, bytes) {
        case ("exact", let bytes?): self = .exact(bytes)
        case ("estimated", let bytes?): self = .estimated(bytes)
        default: self = .unknown
        }
    }
}

extension ModelVariants {
    init(_ wire: Mirmir_V1_ListModelVariantsResponse) {
        self.init(
            variants: wire.variants.map(CatalogVariant.init),
            defaultVariant: wire.hasDefaultVariant ? wire.defaultVariant : nil
        )
    }
}
