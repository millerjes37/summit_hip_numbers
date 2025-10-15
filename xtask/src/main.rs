use anyhow::{Context, Result, bail};
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
            // macOS uses system FFmpeg via Homebrew or system libraries
            println!("  ℹ macOS will use system FFmpeg libraries");
            return Ok(ffmpeg_dir); // Return dummy path
        },
        "linux" => {
            // Linux uses system libraries
            println!("  ℹ Linux will use system FFmpeg libraries");
            return Ok(ffmpeg_dir); // Return dummy path
        },
        _ => bail!("Unsupported platform: {}", platform),
    }

    println!("  ✓ FFmpeg downloaded to: {}", ffmpeg_dir.display());
    Ok(ffmpeg_dir)
}

fn download_ffmpeg_windows(ffmpeg_dir: &Path) -> Result<()> {
    // Download FFmpeg shared build from gyan.dev
    let url = "https://github.com/GyanD/codexffmpeg/releases/download/7.1/ffmpeg-7.1-essentials_build.zip";

    println!("    Downloading from: {}", url);
    let response = reqwest::blocking::get(url)
        .context("Failed to download FFmpeg")?;

    if !response.status().is_success() {
        bail!("Failed to download FFmpeg: HTTP {}", response.status());
    }

    let bytes = response.bytes().context("Failed to read response")?;

    println!("    Extracting FFmpeg archive...");
    let cursor = std::io::Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(cursor)?;

    fs::create_dir_all(&ffmpeg_dir)?;

    // Extract files we need (bin/ and lib/)
    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let outpath = match file.enclosed_name() {
            Some(path) => path,
            None => continue,
        };

        // Only extract bin/ and lib/ directories
        if !outpath.starts_with("bin") && !outpath.starts_with("lib") && !outpath.starts_with("include") {
            continue;
        }

        let outpath = ffmpeg_dir.join(outpath);

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

fn ensure_cross_installed() -> Result<()> {
    // Check if cross is installed
    if Command::new("cross").arg("--version").output().is_ok() {
        println!("  ✓ cross is already installed");
        return Ok(());
    }

    println!("  ⬇ Installing cross for cross-compilation...");
    let status = Command::new("cargo")
        .args(&["install", "cross", "--git", "https://github.com/cross-rs/cross"])
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

    // Add target for cross-compilation if needed
    let (target, use_cross) = match (current_os, platform) {
        // Native builds
        ("linux", "linux") => ("x86_64-unknown-linux-gnu", false),
        ("macos", "macos") => ("x86_64-apple-darwin", false),
        ("windows", "windows") => ("x86_64-pc-windows-gnu", false),

        // Cross-compilation (requires `cross` tool)
        (_, "linux") => ("x86_64-unknown-linux-gnu", true),
        (_, "windows") => ("x86_64-pc-windows-gnu", true),

        // Can't cross-compile to macOS (requires actual macOS)
        (_, "macos") if current_os != "macos" => {
            println!("  ⚠ Skipping macOS build (requires macOS runner)");
            return Ok(());
        }

        _ => return Err(anyhow::anyhow!("Unsupported platform combination")),
    };

    build_cmd.arg("--target").arg(target);

    // Set FFmpeg environment variables for Windows builds
    if platform == "windows" && ffmpeg_dir.exists() {
        let bin_dir = ffmpeg_dir.join("bin");
        let lib_dir = ffmpeg_dir.join("lib");
        let include_dir = ffmpeg_dir.join("include");

        if bin_dir.exists() {
            build_cmd.env("FFMPEG_DIR", &ffmpeg_dir);
            build_cmd.env("FFMPEG_LIB_DIR", &lib_dir);
            build_cmd.env("FFMPEG_INCLUDE_DIR", &include_dir);
        }
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
        return Err(anyhow::anyhow!("Build failed for {} - {}", platform, variant));
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
    } else {
        if variant == "demo" {
            "summit_hip_numbers_demo"
        } else {
            "summit_hip_numbers"
        }
    };

    let binary_src = root
        .join("target")
        .join(target)
        .join("release")
        .join(binary_name);

    if !binary_src.exists() {
        return Err(anyhow::anyhow!(
            "Binary not found at: {}",
            binary_src.display()
        ));
    }

    let binary_dest = platform_dist.join(binary_name);
    fs::copy(&binary_src, &binary_dest)
        .context(format!("Failed to copy binary to {}", binary_dest.display()))?;

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

    // Create archive
    println!("  [4/4] Creating archive...");
    create_archive(&dist_name, &platform_dist, platform)?;

    println!("  ✓ {} - {} complete", platform, variant);

    Ok(())
}

fn copy_assets(root: &Path, dist: &Path) -> Result<()> {
    let assets = root.join("assets");

    // Copy config
    if let Ok(config) = fs::read(assets.join("config.toml")) {
        fs::write(dist.join("config.toml"), config)?;
    }

    // Copy asset directories
    for dir in &["videos", "splash", "logo"] {
        let src = assets.join(dir);
        if src.exists() {
            let dest = dist.join(dir);
            copy_dir_recursive(&src, &dest)?;
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

fn bundle_windows_dlls(root: &Path, dist_dir: &Path) -> Result<()> {
    println!("  [3.5/4] Bundling Windows DLLs...");

    let ffmpeg_bin = root.join(".ffmpeg/windows-x64/bin");

    if !ffmpeg_bin.exists() {
        println!("  ⚠ FFmpeg bin directory not found, skipping DLL bundling");
        return Ok(());
    }

    let mut copied = 0;

    // Copy all DLLs from FFmpeg bin directory
    for entry in fs::read_dir(&ffmpeg_bin)? {
        let entry = entry?;
        let path = entry.path();

        if path.extension().and_then(|s| s.to_str()) == Some("dll") {
            let filename = path.file_name().unwrap();
            let dest = dist_dir.join(filename);
            fs::copy(&path, &dest)
                .with_context(|| format!("Failed to copy DLL: {}", filename.to_string_lossy()))?;
            copied += 1;
        }
    }

    println!("  ✓ Copied {} DLLs", copied);
    Ok(())
}

fn create_archive(name: &str, source: &Path, platform: &str) -> Result<()> {
    let parent = source.parent().unwrap();

    if platform == "windows" {
        // Create ZIP for Windows
        let archive_name = format!("{}.zip", name);

        let status = Command::new("zip")
            .args(&["-r", archive_name.as_str(), name])
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
            .args(&["-czf", archive_name.as_str(), name])
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
