use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::{env, fs};

#[derive(Parser)]
#[command(name = "xtask")]
#[command(about = "Build automation for Summit HIP Numbers")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Build distribution packages for all platforms
    Dist {
        /// Specific platform to build (linux, macos, windows, or all)
        #[arg(long, default_value = "all")]
        platform: String,

        /// Variant to build (full, demo, or all)
        #[arg(long, default_value = "all")]
        variant: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Dist { platform, variant } => build_dist(&platform, &variant)?,
    }

    Ok(())
}

fn build_dist(platform: &str, variant: &str) -> Result<()> {
    let root = project_root();
    let dist_dir = root.join("dist");

    // Determine which platforms to build
    let platforms = if platform == "all" {
        vec!["linux", "macos", "windows"]
    } else {
        vec![platform]
    };

    // Determine which variants to build
    let variants = if variant == "all" {
        vec!["full", "demo"]
    } else {
        vec![variant]
    };

    for platform in platforms {
        for variant in variants.iter() {
            println!("\n=== Building {} - {} ===", platform, variant);
            build_platform(&root, &dist_dir, platform, variant)?;
        }
    }

    println!("\n✓ All distributions built successfully!");
    println!("Outputs in: {}", dist_dir.display());

    Ok(())
}

fn ensure_ffmpeg(root: &Path, platform: &str) -> Result<PathBuf> {
    let ffmpeg_dir = root.join(".ffmpeg").join(format!("{}-x64", platform));

    if ffmpeg_dir.exists() {
        println!("  ✓ FFmpeg already downloaded for {}", platform);
        return Ok(ffmpeg_dir);
    }

    println!("  ⬇ Downloading portable FFmpeg for {}...", platform);

    match platform {
        "windows" => download_ffmpeg_windows(&ffmpeg_dir)?,
        "macos" => {
            // macOS uses Homebrew-provided FFmpeg libraries
            println!("  ℹ macOS will use Homebrew FFmpeg libraries");
            return Ok(ffmpeg_dir); // Return dummy path, we'll set env vars later
        }
        "linux" => {
            // Linux uses vendored FFmpeg (compiled from source)
            println!("  ℹ Linux will use vendored FFmpeg (compiled from source)");
            return Ok(ffmpeg_dir); // Return dummy path
        }
        _ => bail!("Unsupported platform: {}", platform),
    }

    println!("  ✓ FFmpeg downloaded to: {}", ffmpeg_dir.display());
    Ok(ffmpeg_dir)
}

fn download_ffmpeg_windows(ffmpeg_dir: &Path) -> Result<()> {
    // Download FFmpeg full build with headers from gyan.dev
    let url = "https://github.com/GyanD/codexffmpeg/releases/download/7.1/ffmpeg-7.1-full_build-shared.zip";

    println!("    Downloading from: {}", url);
    let response = reqwest::blocking::get(url).context("Failed to download FFmpeg")?;

    if !response.status().is_success() {
        bail!("Failed to download FFmpeg: HTTP {}", response.status());
    }

    let bytes = response.bytes().context("Failed to read response")?;

    println!("    Extracting FFmpeg archive...");
    let cursor = std::io::Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(cursor)?;

    fs::create_dir_all(ffmpeg_dir)?;

    // Extract files we need (bin/ and lib/)
    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let outpath = match file.enclosed_name() {
            Some(path) => path,
            None => continue,
        };

        // Strip the top-level directory (e.g., "ffmpeg-7.1-essentials_build/")
        // and check if remaining path starts with bin/lib/include
        let components: Vec<_> = outpath.components().collect();
        if components.len() < 2 {
            continue;
        }

        // Skip the first component (top-level directory)
        let relative_path: PathBuf = components[1..].iter().collect();

        // Check if this is a bin/lib/include file
        let first_dir = relative_path.components().next();
        let should_extract = match first_dir {
            Some(std::path::Component::Normal(dir)) => {
                let dir_str = dir.to_string_lossy();
                dir_str == "bin" || dir_str == "lib" || dir_str == "include"
            }
            _ => false,
        };

        if !should_extract {
            continue;
        }

        let outpath = ffmpeg_dir.join(&relative_path);

        if file.name().ends_with('/') {
            fs::create_dir_all(&outpath)?;
        } else {
            if let Some(p) = outpath.parent() {
                fs::create_dir_all(p)?;
            }
            let mut outfile = fs::File::create(&outpath)?;
            std::io::copy(&mut file, &mut outfile)?;
        }
    }

    Ok(())
}

fn setup_macos_ffmpeg_env(build_cmd: &mut Command, platform: &str) -> Result<()> {
    // Use Homebrew FFmpeg paths (GitHub Actions installs via brew)
    let ffmpeg_lib_path = PathBuf::from("/opt/homebrew/lib");
    let ffmpeg_include_path = PathBuf::from("/opt/homebrew/include");
    let ffmpeg_pkgconfig_path = PathBuf::from("/opt/homebrew/lib/pkgconfig");

    println!(
        "  ✓ Using Homebrew FFmpeg lib: {}",
        ffmpeg_lib_path.display()
    );
    println!(
        "  ✓ Using Homebrew FFmpeg include: {}",
        ffmpeg_include_path.display()
    );
    println!(
        "  ✓ Using Homebrew FFmpeg pkgconfig: {}",
        ffmpeg_pkgconfig_path.display()
    );

    // Set environment variables for FFmpeg linking
    build_cmd.env("CPATH", &ffmpeg_include_path);
    build_cmd.env("LIBRARY_PATH", &ffmpeg_lib_path);

    // Set pkg-config path
    let current_pkg_config_path = env::var("PKG_CONFIG_PATH").unwrap_or_default();
    let new_pkg_config_path = if current_pkg_config_path.is_empty() {
        ffmpeg_pkgconfig_path.to_string_lossy().to_string()
    } else {
        format!(
            "{}:{}",
            ffmpeg_pkgconfig_path.display(),
            current_pkg_config_path
        )
    };
    build_cmd.env("PKG_CONFIG_PATH", new_pkg_config_path);

    // On macOS, force use of libc++ instead of libstdc++
    if platform == "macos" {
        build_cmd.env("CXXSTDLIB", "c++");
        build_cmd.env("CXXFLAGS", "-stdlib=libc++");
        build_cmd.env("LDFLAGS", "-stdlib=libc++");
    }

    Ok(())
}

fn find_ffmpeg_lib_path() -> Result<PathBuf> {
    // Find FFmpeg lib directory in nix store
    let output = Command::new("find")
        .args(["/nix/store", "-name", "libavcodec*.dylib", "-type", "f"])
        .output()
        .context("Failed to find FFmpeg libraries")?;

    if !output.status.success() {
        bail!("No FFmpeg libraries found in nix store");
    }

    let lib_path_str = String::from_utf8(output.stdout)
        .context("Invalid UTF-8 in find output")?
        .lines()
        .next()
        .context("No FFmpeg library found")?
        .to_string();

    let lib_path = PathBuf::from(lib_path_str);
    let lib_dir = lib_path
        .parent()
        .context("FFmpeg library has no parent directory")?;

    Ok(lib_dir.to_path_buf())
}

#[allow(dead_code)]
fn download_ffmpeg_macos(ffmpeg_dir: &Path) -> Result<()> {
    // Download static FFmpeg build from evermeet.cx (universal binary)
    let url = "https://evermeet.cx/ffmpeg/ffmpeg-7.1.7z";

    println!("    Downloading from: {}", url);
    let response = reqwest::blocking::get(url).context("Failed to download FFmpeg")?;

    if !response.status().is_success() {
        bail!("Failed to download FFmpeg: HTTP {}", response.status());
    }

    let bytes = response.bytes().context("Failed to read response")?;

    println!("    Extracting FFmpeg archive...");

    // Use 7z to extract (since it's a 7z archive)
    // First write to a temp file
    let temp_file = ffmpeg_dir.with_extension("7z");
    fs::create_dir_all(ffmpeg_dir.parent().unwrap())?;
    fs::write(&temp_file, &bytes).context("Failed to write temp file")?;

    // Extract using 7z command
    let status = Command::new("7z")
        .args([
            "x",
            temp_file.to_str().unwrap(),
            &format!("-o{}", ffmpeg_dir.display()),
        ])
        .status()
        .context("Failed to extract FFmpeg archive with 7z")?;

    if !status.success() {
        // Try tar if 7z fails
        println!("    7z failed, trying tar...");
        let status = Command::new("tar")
            .args([
                "-xf",
                temp_file.to_str().unwrap(),
                "-C",
                ffmpeg_dir.parent().unwrap().to_str().unwrap(),
            ])
            .status()
            .context("Failed to extract FFmpeg archive with tar")?;

        if !status.success() {
            bail!("Failed to extract FFmpeg archive");
        }
    }

    // Clean up temp file
    let _ = fs::remove_file(&temp_file);

    // Find the extracted ffmpeg binary and move it to the expected location
    let extracted_dir = ffmpeg_dir;
    if extracted_dir.exists() {
        // The archive extracts to a directory, we need to organize it like Windows
        // Create bin/ and lib/ directories
        let bin_dir = ffmpeg_dir.join("bin");
        let lib_dir = ffmpeg_dir.join("lib");
        let include_dir = ffmpeg_dir.join("include");

        fs::create_dir_all(&bin_dir)?;
        fs::create_dir_all(&lib_dir)?;
        fs::create_dir_all(&include_dir)?;

        // Find ffmpeg binary and copy it
        for entry in fs::read_dir(extracted_dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.file_name().and_then(|n| n.to_str()) == Some("ffmpeg")
                && entry.file_type()?.is_file()
            {
                fs::copy(&path, bin_dir.join("ffmpeg"))?;
                break;
            }
        }

        // For static linking, we don't need separate libs since it's all in the binary
        // But create dummy .pc files if needed
        println!("    ✓ FFmpeg static binary extracted");
    }

    Ok(())
}

fn ensure_cross_installed() -> Result<()> {
    // Check if cross is installed
    if Command::new("cross").arg("--version").output().is_ok() {
        println!("  ✓ cross is already installed");
        return Ok(());
    }

    println!("  ⬇ Installing cross for cross-compilation...");
    let status = Command::new("cargo")
        .args([
            "install",
            "cross",
            "--git",
            "https://github.com/cross-rs/cross",
        ])
        .status()
        .context("Failed to install cross")?;

    if !status.success() {
        bail!("Failed to install cross");
    }

    println!("  ✓ cross installed successfully");
    Ok(())
}

fn build_platform(root: &Path, dist_dir: &Path, platform: &str, variant: &str) -> Result<()> {
    // Detect current platform
    let current_os = env::consts::OS;

    // Ensure FFmpeg is available for target platform
    let ffmpeg_dir = ensure_ffmpeg(root, platform)?;

    // Build the application
    println!("  [1/4] Building application...");
    let mut build_cmd = Command::new("cargo");
    build_cmd
        .arg("build")
        .arg("--release")
        .arg("--package")
        .arg("summit_hip_numbers");

    if variant == "demo" {
        build_cmd.arg("--features").arg("demo");
    }

    // Check if Docker is available for cross-compilation
    let docker_available = Command::new("docker")
        .arg("--version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false);

    // Use native builds for Linux on Linux runners to avoid GLIBC issues
    // Use cross for Linux from non-Linux runners (e.g., macOS ARM64)
    // For Windows, try to use downloaded FFmpeg if Docker not available
    // Only macOS requires native builds (can't cross-compile to macOS)
    let (target, use_cross) = match platform {
        "linux" => {
            if current_os == "linux" {
                // Native Linux build on Linux runner
                ("x86_64-unknown-linux-gnu", false)
            } else if !docker_available {
                println!("  ⚠ Skipping Linux build (requires Docker for cross-compilation)");
                return Ok(());
            } else {
                // Cross-compilation from non-Linux runner
                ("x86_64-unknown-linux-gnu", true)
            }
        }
        "windows" => {
            if docker_available {
                ("x86_64-pc-windows-gnu", true)
            } else {
                // Try Windows build with downloaded FFmpeg
                println!("  ℹ Attempting Windows build with downloaded FFmpeg (experimental)");
                ("x86_64-pc-windows-gnu", false)
            }
        }
        "macos" => {
            if current_os != "macos" {
                println!("  ⚠ Skipping macOS build (requires macOS runner)");
                return Ok(());
            }
            // Detect current architecture and use it for native build
            let arch = env::consts::ARCH;
            let target = match arch {
                "aarch64" => "aarch64-apple-darwin",
                "x86_64" => "x86_64-apple-darwin",
                _ => {
                    println!("  ⚠ Unsupported macOS architecture: {}", arch);
                    return Ok(());
                }
            };

            // Ensure target is installed
            println!("  Ensuring Rust target {} is installed...", target);
            let status = Command::new("rustup")
                .args(["target", "add", target])
                .status()
                .context("Failed to run rustup")?;

            if !status.success() {
                bail!("Failed to install Rust target: {}", target);
            }

            (target, false)
        }
        _ => return Err(anyhow::anyhow!("Unsupported platform: {}", platform)),
    };

    build_cmd.arg("--target").arg(target);

    // Set FFmpeg environment variables
    // For Windows cross-compilation, use system FFmpeg libraries installed in Docker container
    if platform == "windows" && ffmpeg_dir.exists() && !use_cross {
        let bin_dir = ffmpeg_dir.join("bin");
        let lib_dir = ffmpeg_dir.join("lib");
        let include_dir = ffmpeg_dir.join("include");

        if bin_dir.exists() || lib_dir.exists() {
            build_cmd.env("FFMPEG_DIR", &ffmpeg_dir);
            if lib_dir.exists() {
                build_cmd.env("FFMPEG_LIB_DIR", &lib_dir);
            }
            if include_dir.exists() {
                build_cmd.env("FFMPEG_INCLUDE_DIR", &include_dir);
            }
        }
    } else if platform == "macos" {
        // For macOS, set up nix FFmpeg paths
        setup_macos_ffmpeg_env(&mut build_cmd, platform)?;
    }

    let status = if use_cross {
        // Ensure cross is installed
        ensure_cross_installed()?;

        println!("  Using cross for {} target", target);
        let mut cross_cmd = Command::new("cross");
        cross_cmd.args(build_cmd.get_args().collect::<Vec<_>>());

        // Copy environment variables to cross
        for (key, value) in build_cmd.get_envs() {
            if let Some(val) = value {
                cross_cmd.env(key, val);
            }
        }

        cross_cmd.status().context("Failed to run cross")?
    } else {
        build_cmd.status().context("Failed to run cargo build")?
    };

    if !status.success() {
        return Err(anyhow::anyhow!(
            "Build failed for {} - {}",
            platform,
            variant
        ));
    }

    // Create distribution directory
    println!("  [2/4] Creating distribution directory...");
    let dist_name = format!("{}-{}", platform, variant);
    let platform_dist = dist_dir.join(&dist_name);
    fs::create_dir_all(&platform_dist)?;

    // Copy binary
    println!("  [3/4] Copying binary and assets...");
    let binary_name = if platform == "windows" {
        if variant == "demo" {
            "summit_hip_numbers_demo.exe"
        } else {
            "summit_hip_numbers.exe"
        }
    } else if variant == "demo" {
        "summit_hip_numbers_demo"
    } else {
        "summit_hip_numbers"
    };

    let binary_src = if platform == "macos" && current_os == "macos" {
        // For native macOS builds, don't use target triple
        root.join("target").join("release").join(binary_name)
    } else {
        // For cross-compilation, use target triple
        root.join("target")
            .join(target)
            .join("release")
            .join(binary_name)
    };

    if !binary_src.exists() {
        return Err(anyhow::anyhow!(
            "Binary not found at: {}",
            binary_src.display()
        ));
    }

    let binary_dest = platform_dist.join(binary_name);
    fs::copy(&binary_src, &binary_dest).context(format!(
        "Failed to copy binary to {}",
        binary_dest.display()
    ))?;

    // Make executable on Unix
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&binary_dest)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&binary_dest, perms)?;
    }

    // Copy assets
    copy_assets(root, &platform_dist)?;

    // Bundle Windows DLLs if needed
    if platform == "windows" {
        bundle_windows_dlls(root, &platform_dist)?;
    }

    // Bundle macOS dylibs if needed
    if platform == "macos" {
        // On macOS with nix, FFmpeg libraries are available system-wide
        // so we don't need to bundle them
        println!("  ℹ macOS uses system FFmpeg libraries (no bundling needed)");
    }

    // Create archive
    println!("  [4/4] Creating archive...");
    create_archive(&dist_name, &platform_dist, platform)?;

    println!("  ✓ {} - {} complete", platform, variant);

    Ok(())
}

fn copy_assets(root: &Path, dist: &Path) -> Result<()> {
    // Copy distribution config (config.dist.toml -> config.toml)
    let dist_config = root.join("config.dist.toml");
    if dist_config.exists() {
        fs::copy(&dist_config, dist.join("config.toml"))
            .context("Failed to copy config.dist.toml")?;
        println!("  ✓ Copied config.dist.toml -> config.toml");
    } else {
        // Fallback to assets/config.toml if config.dist.toml doesn't exist
        let assets_config = root.join("assets").join("config.toml");
        if assets_config.exists() {
            fs::copy(&assets_config, dist.join("config.toml"))
                .context("Failed to copy config.toml")?;
            println!("  ✓ Copied config.toml");
        } else {
            println!("  ⚠ No config file found");
        }
    }

    // Copy or create asset directories
    let assets = root.join("assets");
    for dir in &["videos", "splash", "logo"] {
        let src = assets.join(dir);
        let dest = dist.join(dir);

        if src.exists() {
            copy_dir_recursive(&src, &dest)?;
            println!("  ✓ Copied {} directory", dir);
        } else {
            // Create empty directory structure for user to populate
            fs::create_dir_all(&dest)
                .with_context(|| format!("Failed to create {} directory", dir))?;
            println!("  ✓ Created empty {} directory", dir);
        }
    }

    Ok(())
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_recursive(&entry.path(), &dst.join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.join(entry.file_name()))?;
        }
    }
    Ok(())
}

#[allow(dead_code)]
fn bundle_macos_dylibs(dist_dir: &Path) -> Result<()> {
    println!("  [3.5/4] Bundling macOS dylibs...");

    let ffmpeg_lib_path = find_ffmpeg_lib_path()?;

    let mut copied = 0;
    let mut dylib_names = Vec::new();

    // Copy FFmpeg dylibs that the application links against
    let ffmpeg_libs = [
        "libavcodec*.dylib",
        "libavformat*.dylib",
        "libavutil*.dylib",
        "libswscale*.dylib",
        "libswresample*.dylib",
    ];

    for pattern in &ffmpeg_libs {
        let output = Command::new("find")
            .args([
                ffmpeg_lib_path.to_str().unwrap(),
                "-name",
                pattern,
                "-type",
                "f",
            ])
            .output()
            .with_context(|| format!("Failed to find {} libraries", pattern))?;

        if !output.status.success() {
            continue;
        }

        let lib_paths = String::from_utf8(output.stdout).context("Invalid UTF-8 in find output")?;

        for lib_path_str in lib_paths.lines() {
            let lib_path = PathBuf::from(lib_path_str);
            let filename = lib_path.file_name().unwrap();
            let dest = dist_dir.join(filename);

            // Use cp command for better permission handling with nix store files
            let status = Command::new("cp")
                .args([lib_path_str, &dest.to_string_lossy()])
                .status()
                .with_context(|| format!("Failed to copy dylib: {}", filename.to_string_lossy()))?;

            if !status.success() {
                bail!("cp command failed for {}", filename.to_string_lossy());
            }

            dylib_names.push(filename.to_string_lossy().to_string());
            copied += 1;
        }
    }

    if copied > 0 {
        dylib_names.sort();
        println!("  ✓ Copied {} dylibs:", copied);
        for dylib in &dylib_names {
            println!("    - {}", dylib);
        }
    } else {
        println!("  ⚠ No FFmpeg dylibs found to bundle");
    }

    Ok(())
}

fn bundle_windows_dlls(root: &Path, dist_dir: &Path) -> Result<()> {
    println!("  [3.5/4] Bundling Windows DLLs...");

    let ffmpeg_bin = root.join(".ffmpeg/windows-x64/bin");

    if !ffmpeg_bin.exists() {
        println!("  ⚠ FFmpeg bin directory not found, skipping DLL bundling");
        return Ok(());
    }

    let mut copied = 0;
    let mut dll_names = Vec::new();

    // Copy all DLLs from FFmpeg bin directory
    for entry in fs::read_dir(&ffmpeg_bin)? {
        let entry = entry?;
        let path = entry.path();

        if path.extension().and_then(|s| s.to_str()) == Some("dll") {
            let filename = path.file_name().unwrap();
            let dest = dist_dir.join(filename);
            fs::copy(&path, &dest)
                .with_context(|| format!("Failed to copy DLL: {}", filename.to_string_lossy()))?;
            dll_names.push(filename.to_string_lossy().to_string());
            copied += 1;
        }
    }

    if copied > 0 {
        dll_names.sort();
        println!("  ✓ Copied {} DLLs:", copied);
        for dll in &dll_names {
            println!("    - {}", dll);
        }
    } else {
        println!("  ⚠ No DLLs found in FFmpeg bin directory");
    }

    Ok(())
}

fn create_archive(name: &str, source: &Path, platform: &str) -> Result<()> {
    let parent = source.parent().unwrap();

    if platform == "windows" {
        // Create ZIP for Windows
        let archive_name = format!("{}.zip", name);

        let status = Command::new("zip")
            .args(["-r", archive_name.as_str(), name])
            .current_dir(parent)
            .status()
            .context("Failed to create ZIP archive")?;

        if !status.success() {
            return Err(anyhow::anyhow!("ZIP creation failed"));
        }
    } else {
        // Create tar.gz for Unix
        let archive_name = format!("{}.tar.gz", name);

        let status = Command::new("tar")
            .args(["-czf", archive_name.as_str(), name])
            .current_dir(parent)
            .status()
            .context("Failed to create tar.gz archive")?;

        if !status.success() {
            return Err(anyhow::anyhow!("tar.gz creation failed"));
        }
    }

    Ok(())
}

fn project_root() -> PathBuf {
    Path::new(&env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(1)
        .unwrap()
        .to_path_buf()
}
