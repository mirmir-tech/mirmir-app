#!/usr/bin/env bash
# Regenerates Sources/MirmirRPC/Generated from Proto/mirmir.proto.
#
# The protoc plugins are built from the package's resolved checkouts so the
# generated code always matches the SwiftProtobuf and GRPC runtime versions in
# Package.resolved. Only `protoc` itself must be on PATH.
#
# With --sync, Proto/mirmir.proto is first refreshed from a sibling mirmir
# checkout (Workmir layout: ../mirmir/proto/mirmir.proto, or MIRMIR_PROTO).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ "${1:-}" == "--sync" ]]; then
    source_proto="${MIRMIR_PROTO:-$root/../mirmir/proto/mirmir.proto}"
    [[ -f "$source_proto" ]] || { echo "missing $source_proto" >&2; exit 1; }
    cp "$source_proto" Proto/mirmir.proto
    echo "synced Proto/mirmir.proto from $source_proto"
fi

command -v protoc >/dev/null || { echo "protoc is required (brew install protobuf)" >&2; exit 1; }

swift package resolve >/dev/null
tools="$root/.build/protoc-tools"
swift build -c release --package-path .build/checkouts/swift-protobuf \
    --scratch-path "$tools/swift-protobuf" --product protoc-gen-swift >/dev/null
swift build -c release --package-path .build/checkouts/grpc-swift-protobuf \
    --scratch-path "$tools/grpc-swift-protobuf" --product protoc-gen-grpc-swift-2 >/dev/null

out="Sources/MirmirRPC/Generated"
rm -f "$out"/*.swift
protoc \
    --plugin=protoc-gen-swift="$tools/swift-protobuf/release/protoc-gen-swift" \
    --plugin=protoc-gen-grpc-swift="$tools/grpc-swift-protobuf/release/protoc-gen-grpc-swift-2" \
    --proto_path=Proto \
    --swift_out="$out" --swift_opt=Visibility=Public \
    --grpc-swift_out="$out" --grpc-swift_opt=Visibility=Public,Server=false \
    Proto/mirmir.proto
echo "generated: $(ls "$out" | tr '\n' ' ')"
