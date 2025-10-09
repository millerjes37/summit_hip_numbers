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
           installPhase = ''
             # Copy assets to bin directory where the binary is
             cp config.toml $out/bin/
             cp -r videos $out/bin/ 2>/dev/null || true
             cp -r splash $out/bin/ 2>/dev/null || true
           '';
        };                # Cross-compilation to Windows
        packages.windows =
          let
            pkgs-windows = import nixpkgs {
              system = "x86_64-w64-mingw32";
              crossSystem = {
                config = "x86_64-w64-mingw32";
              };
            };
            gstVersion = "1.24.10";
            gstMsi = pkgs.fetchurl {
              url = "https://gstreamer.freedesktop.org/data/pkg/windows/${gstVersion}/mingw/gstreamer-1.0-mingw-x86_64-${gstVersion}.msi";
              sha256 = "25349c03cb16edf55273b5d8fbc3319d013e6e0e907afe386e7cd8e6b08c0e32";
            };
          in
          pkgs.rustPlatform.buildRustPackage {
            pname = "summit_hip_numbers-windows";
            version = "0.1.0";
            src = ./.;            cargoLock = {              lockFile = ./Cargo.lock;            };            # Use the Windows toolchain            toolchain = pkgs.rust-bin.stable.latest.default.override {              targets = [ "x86_64-pc-windows-gnu" ];            };                        # GStreamer dependencies for Windows
            nativeBuildInputs = [ pkgs.msitools ] ++ (with pkgs; [
              pkg-config
            ]);
            buildInputs = [ ];
            installPhase = ''
              mkdir -p $out
              cp target/x86_64-pc-windows-gnu/release/summit_hip_numbers.exe $out/
              # Extract GStreamer runtime MSI for standalone bundle
              cd $out
              msiextract ${gstMsi}
              cd -
              # Copy config and assets
              cp config.toml $out/
              cp -r videos $out/ 2>/dev/null || true
              cp -r splash $out/ 2>/dev/null || true
            '';          };      });}