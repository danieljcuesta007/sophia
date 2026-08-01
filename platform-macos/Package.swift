// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SophiaWriteMac",
    platforms: [.macOS(.v14)],
    targets: [
        // C ABI of the Rust core. The header is a symlink to the canonical copy in
        // core/ffi/include/; the library comes from `cargo build --release` in core/.
        .target(
            name: "CSophiaFFI",
            path: "Core/CSophiaFFI"
        ),
        // Cadence's insertion engine, vendored verbatim (blueprint §12.3):
        // direct AX → paste+restore → clipboard+notify, readback verification,
        // secure-field refusal, deadline-bounded AX calls.
        .target(
            name: "SophiaInsertion",
            path: "Insertion/Sources/SophiaInsertion"
        ),
        // The menu-bar agent (LSUIElement when packaged; accessory policy in dev).
        // NOTE: no .testTarget — this machine has Command Line Tools only (no XCTest).
        // Invariants are covered by `sophia-write selftest` (run headlessly).
        .executableTarget(
            name: "sophia-write",
            dependencies: ["CSophiaFFI", "SophiaInsertion"],
            path: "App/Sources/sophia-write",
            linkerSettings: [
                .linkedLibrary("sophia_ffi"),
                .unsafeFlags(["-L\(Context.packageDirectory)/../core/target/release"]),
            ]
        ),
    ]
)
