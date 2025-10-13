{
  description = "A flake for the Summit Hip Numbers media player";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Rust overlay for easy Rust toolchain management
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        lib = pkgs.lib;

        # Rust toolchain
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" ];
        };
        
        # Common dependencies for both native and cross-compilation
        commonDeps = with pkgs; [
          pkg-config
          ffmpeg.dev
          cargo-bundle
        ] ++ lib.optionals pkgs.stdenv.isLinux [
          # Linux-specific GUI dependencies
          wayland
          libxkbcommon
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXi
          libGL
          mesa
          libglvnd
          vulkan-loader
          alsa-lib
          fontconfig
          freetype
        ];

        ffmpegLibs = with pkgs; [
          ffmpeg.dev
        ];

        # Build inputs for GUI applications
        guiLibs = with pkgs; lib.optionals stdenv.isLinux [
          # Linux GUI libraries
          libGL
          mesa
          libglvnd
          vulkan-loader
          # X11 libraries
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXi
          # Wayland libraries
          wayland
          libxkbcommon
          # Audio
          alsa-lib
          # Fonts
          fontconfig
          freetype
        ];
      in
      {
        
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = [ rustToolchain ] ++ commonDeps ++ [ pkgs.cargo-bundle ];
        };
        
        packages = {
        # Native build
         default = pkgs.rustPlatform.buildRustPackage {
             pname = "summit_hip_numbers";
             version = "0.1.0";
             src = ./.;
             cargoLock = {
               lockFile = ./Cargo.lock;
             };
             
             # Build only the main package
             cargoBuildFlags = [ "--package" "summit_hip_numbers" ];
             
             nativeBuildInputs = [ pkgs.pkg-config ];
             buildInputs = ffmpegLibs ++ guiLibs;
             
             # Environment variables for proper GUI operation (Linux only)
             env = lib.optionalAttrs pkgs.stdenv.isLinux {
               WINIT_UNIX_BACKEND = "x11";
               XDG_SESSION_TYPE = "x11";
               GDK_BACKEND = "x11";
             };
             
              postInstall = ''
                # Copy assets to bin directory where the binary is
                cp assets/config.toml $out/bin/
                cp -r assets/videos $out/bin/ 2>/dev/null || true
                cp -r assets/splash $out/bin/ 2>/dev/null || true
                cp -r assets/logo $out/bin/ 2>/dev/null || true

                # Create version file
                echo "Build: $(date -u +'%Y-%m-%d %H:%M:%S UTC')" > $out/bin/VERSION.txt
                echo "Git Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')" >> $out/bin/VERSION.txt
                echo "Variant: full" >> $out/bin/VERSION.txt
              '';
           };

           demo = pkgs.rustPlatform.buildRustPackage {
             pname = "summit_hip_numbers_demo";
             version = "0.1.0";
             src = ./.;
             cargoLock = {
               lockFile = ./Cargo.lock;
             };
             
             # Build demo variant with features flag
             cargoBuildFlags = [ "--package" "summit_hip_numbers" "--features" "demo" ];
             
             nativeBuildInputs = [ pkgs.pkg-config ];
             buildInputs = ffmpegLibs ++ guiLibs;
             
             # Environment variables for proper GUI operation (Linux only)
             env = lib.optionalAttrs pkgs.stdenv.isLinux {
               WINIT_UNIX_BACKEND = "x11";
               XDG_SESSION_TYPE = "x11";
               GDK_BACKEND = "x11";
             };
             
              postInstall = ''
                # Copy assets to bin directory where the binary is
                cp assets/config.toml $out/bin/
                cp -r assets/videos $out/bin/ 2>/dev/null || true
                cp -r assets/splash $out/bin/ 2>/dev/null || true
                cp -r assets/logo $out/bin/ 2>/dev/null || true

                # Create version file
                echo "Build: $(date -u +'%Y-%m-%d %H:%M:%S UTC')" > $out/bin/VERSION.txt
                echo "Git Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')" >> $out/bin/VERSION.txt
                echo "Variant: demo" >> $out/bin/VERSION.txt

                # Rename binary for demo
                mv $out/bin/summit_hip_numbers $out/bin/summit_hip_numbers_demo
              '';
           };

           usb-prep = pkgs.rustPlatform.buildRustPackage {
             pname = "summit_usb_prep";
             version = "0.1.0";
             src = ./.;
             cargoLock = {
               lockFile = ./Cargo.lock;
             };
             
             # Build only the USB prep tool package
             cargoBuildFlags = [ "--package" "summit_usb_prep" ];
             
             nativeBuildInputs = [ pkgs.pkg-config ];
             buildInputs = guiLibs;
             
             # Environment variables for proper GUI operation (Linux only)
             env = lib.optionalAttrs pkgs.stdenv.isLinux {
               WINIT_UNIX_BACKEND = "x11";
               XDG_SESSION_TYPE = "x11";
               GDK_BACKEND = "x11";
             };
             
              postInstall = ''
                # Copy logo assets
                mkdir -p $out/share/summit_usb_prep
                cp -r assets/logo $out/share/summit_usb_prep/ 2>/dev/null || true
              '';
           };
        } // lib.optionalAttrs pkgs.stdenv.isDarwin {

        # macOS build with cargo-bundle for DMG (only available on Darwin)
        macos = pkgs.rustPlatform.buildRustPackage {
           pname = "summit_hip_numbers";
           version = "0.1.0";
           src = ./.;
           cargoLock = {
             lockFile = ./Cargo.lock;
           };
           
           # Build only the main package
           cargoBuildFlags = [ "--package" "summit_hip_numbers" ];
           
           nativeBuildInputs = with pkgs; [
            pkg-config
            cargo-bundle
           ];
           buildInputs = ffmpegLibs;
           postBuild = ''
             cargo-bundle --release --format dmg
           '';
            installPhase = ''
              mkdir -p $out
              cp -r target/release/bundle/osx/* $out/
              # Copy config and assets
              cp assets/config.toml $out/
              cp -r assets/videos $out/ 2>/dev/null || true
              cp -r assets/splash $out/ 2>/dev/null || true
              cp -r assets/logo $out/ 2>/dev/null || true
            '';
         };
        };
      });
}