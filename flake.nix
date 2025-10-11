{  description = "A flake for the Summit Hip Numbers media player";  inputs = {    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";    rust-overlay.url = "github:oxalica/rust-overlay";    flake-utils.url = "github:numtide/flake-utils";  };  outputs = { self, nixpkgs, rust-overlay, flake-utils }:    flake-utils.lib.eachDefaultSystem (system:      let        # Rust overlay for easy Rust toolchain management        overlays = [ (import rust-overlay) ];        pkgs = import nixpkgs {          inherit system overlays;        };        # Rust toolchain        rustToolchain = pkgs.rust-bin.stable.latest.default.override {          extensions = [ "rust-src" ];        };                # Common dependencies for both native and cross-compilation
        commonDeps = with pkgs; [
          pkg-config
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-ugly
          cargo-bundle
          # GUI dependencies for Wayland/X11
          wayland
          libxkbcommon
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXi
        ];

        gstLibs = with pkgs; [
          glib
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-ugly
        ];      in      {                # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = [ rustToolchain ] ++ commonDeps ++ [ pkgs.cargo-bundle ];
        };                # Native build
        packages.default = pkgs.rustPlatform.buildRustPackage {
           pname = "summit_hip_numbers";
           version = "0.1.0";
           src = ./.;
           cargoLock = {
             lockFile = ./Cargo.lock;
           };
           nativeBuildInputs = [ pkgs.pkg-config ];
           buildInputs = gstLibs;
             postInstall = ''
               # Copy assets to bin directory where the binary is
               cp config.toml $out/bin/
               cp -r videos $out/bin/ 2>/dev/null || true
               cp -r splash $out/bin/ 2>/dev/null || true
               cp -r logo $out/bin/ 2>/dev/null || true
             '';
         };

        # macOS build with cargo-bundle for DMG
        packages.macos = pkgs.rustPlatform.buildRustPackage {
           nativeBuildInputs = with pkgs; [
            pkg-config
            cargo-bundle
          ];
          buildInputs = [ ];
          postBuild = ''
            cargo-bundle --release --format dmg
          '';
           installPhase = ''
             mkdir -p $out
             cp -r target/release/bundle/osx/* $out/
             # Copy config and assets
             cp config.toml $out/
             cp -r videos $out/ 2>/dev/null || true
             cp -r splash $out/ 2>/dev/null || true
             cp -r logo $out/ 2>/dev/null || true
           '';
        };
      });
}