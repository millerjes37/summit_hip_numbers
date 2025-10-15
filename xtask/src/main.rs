use anyhow::{Context, Result};
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

fn build_platform(root: &Path, dist_dir: &Path, platform: &str, variant: &str) -> Result<()> {
    // Detect current platform
    let current_os = env::consts::OS;

    // Build the application
    println!("  [1/4] Building application...");
    let mut build_cmd = Command::new("cargo");
    build_cmd
        .arg("build")
        .arg("--release")
        .arg("--package")
        .arg("summit_hip_numbers");

    if variant == &"demo" {
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

    let status = if use_cross {
        println!("  Using cross for {} target", target);
        Command::new("cross")
            .args(&build_cmd.get_args().collect::<Vec<_>>())
            .status()
            .context("Failed to run cross")?
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

fn create_archive(name: &str, source: &Path, platform: &str) -> Result<()> {
    let parent = source.parent().unwrap();

    if platform == "windows" {
        // Create ZIP for Windows
        let archive_name = format!("{}.zip", name);
        let archive_path = parent.join(&archive_name);

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
        let archive_path = parent.join(&archive_name);

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
