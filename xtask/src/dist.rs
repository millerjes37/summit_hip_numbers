use anyhow::{Context, Result, bail};
use colored::*;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::fs;
use std::io::Write;
use walkdir::WalkDir;

use crate::ffmpeg;
use crate::cross;

pub fn build_platform(platform: &str, variant: &str) -> Result<()> {
    println!("\n{}", format!("  [1/4] Building {} binary...", platform).cyan());

    let target_triple = cross::get_target_triple(platform, "x64");
    let use_cross = cross::should_use_cross(platform);

    // Set up build command
    let mut cmd = if use_cross {
        println!("    Using cross for {}", platform);
        Command::new("cross")
    } else {
        println!("    Using cargo for {}", platform);
        Command::new("cargo")
    };

    cmd.arg("build")
        .arg("--release")
        .arg("--target")
        .arg(target_triple)
        .arg("--package")
        .arg("summit_hip_numbers");

    // Add features for variant
    if variant == "demo" {
        cmd.arg("--features").arg("demo");
    }

    // Set FFmpeg environment variables
    let libs = ffmpeg::ensure_ffmpeg_libs(false)?;
    for (key, value) in ffmpeg::get_env_for_platform(platform, &libs) {
        cmd.env(key, value);
    }

    // Execute build
    let status = cmd.status().context("Failed to execute build")?;
    if !status.success() {
        bail!("Build failed for {} {}", platform, variant);
    }

    println!("    {} Binary built successfully", "✓".green());

    // Create distribution
    println!("\n{}", format!("  [2/4] Creating distribution for {}...", platform).cyan());

    let dist_dir = create_dist_structure(platform, variant, target_triple)?;

    println!("\n{}", format!("  [3/4] Bundling dependencies for {}...", platform).cyan());

    bundle_dependencies(platform, variant, target_triple, &dist_dir)?;

    println!("\n{}", format!("  [4/4] Creating archive for {}...", platform).cyan());

    create_archive(platform, variant, &dist_dir)?;

    println!("    {} Distribution complete: {}", "✓".green(), dist_dir.display().to_string().cyan());

    Ok(())
}

fn create_dist_structure(platform: &str, variant: &str, target_triple: &str) -> Result<PathBuf> {
    let dist_dir = PathBuf::from("dist")
        .join(format!("{}-{}", platform, variant));

    // Clean and create dist directory
    if dist_dir.exists() {
        fs::remove_dir_all(&dist_dir)?;
    }
    fs::create_dir_all(&dist_dir)?;

    // Copy binary
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

    let source_binary = PathBuf::from("target")
        .join(target_triple)
        .join("release")
        .join(if platform == "windows" { "summit_hip_numbers.exe" } else { "summit_hip_numbers" });

    let dest_binary = dist_dir.join(binary_name);

    fs::copy(&source_binary, &dest_binary)
        .with_context(|| format!("Failed to copy binary from {:?} to {:?}", source_binary, dest_binary))?;

    // Make executable on Unix
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&dest_binary)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&dest_binary, perms)?;
    }

    println!("    {} Copied binary: {}", "✓".green(), binary_name.dimmed());

    // Copy assets
    copy_assets(&dist_dir)?;

    // Copy config
    let config_source = if Path::new("config.dist.toml").exists() {
        "config.dist.toml"
    } else {
        "config.toml"
    };

    if Path::new(config_source).exists() {
        fs::copy(config_source, dist_dir.join("config.toml"))?;
        println!("    {} Copied config.toml", "✓".green());
    }

    // Create VERSION file
    create_version_file(&dist_dir, variant)?;

    Ok(dist_dir)
}

fn copy_assets(dist_dir: &Path) -> Result<()> {
    let asset_dirs = ["videos", "splash", "logo"];

    for dir in &asset_dirs {
        let source = PathBuf::from("assets").join(dir);
        if source.exists() {
            let dest = dist_dir.join(dir);
            copy_dir_recursive(&source, &dest)?;
            println!("    {} Copied {}/", "✓".green(), dir.dimmed());
        }
    }

    Ok(())
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    fs::create_dir_all(dst)?;

    for entry in WalkDir::new(src).min_depth(1) {
        let entry = entry?;
        let path = entry.path();
        let relative = path.strip_prefix(src)?;
        let dest_path = dst.join(relative);

        if entry.file_type().is_dir() {
            fs::create_dir_all(&dest_path)?;
        } else {
            if let Some(parent) = dest_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(path, &dest_path)?;
        }
    }

    Ok(())
}

fn create_version_file(dist_dir: &Path, variant: &str) -> Result<()> {
    let git_commit = Command::new("git")
        .args(&["rev-parse", "HEAD"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "unknown".to_string());

    let git_tag = Command::new("git")
        .args(&["describe", "--tags", "--exact-match"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| format!("dev-{}", &git_commit[..7]));

    let version_content = format!(
        "Version: {}\nVariant: {}\nCommit: {}\nBuild Date: {}\n",
        git_tag,
        variant,
        git_commit,
        chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC")
    );

    fs::write(dist_dir.join("VERSION.txt"), version_content)?;
    println!("    {} Created VERSION.txt", "✓".green());

    Ok(())
}

fn bundle_dependencies(platform: &str, _variant: &str, target_triple: &str, dist_dir: &Path) -> Result<()> {
    match platform {
        "windows" => bundle_windows_dlls(target_triple, dist_dir)?,
        "linux" => {
            println!("    {} Linux binary is dynamically linked (system libs)", "ℹ".cyan());
        }
        "macos" => {
            println!("    {} macOS app bundle will be created separately", "ℹ".cyan());
        }
        _ => {}
    }

    Ok(())
}

fn bundle_windows_dlls(_target_triple: &str, dist_dir: &Path) -> Result<()> {
    println!("    Bundling Windows DLLs...");

    // Check for FFmpeg DLLs in .ffmpeg/windows-x64/bin
    let ffmpeg_dlls_dir = PathBuf::from(".ffmpeg/windows-x64/bin");

    if ffmpeg_dlls_dir.exists() {
        // Copy FFmpeg DLLs
        let dll_patterns = vec![
            "avutil-*.dll",
            "avcodec-*.dll",
            "avformat-*.dll",
            "swscale-*.dll",
            "swresample-*.dll",
            "avdevice-*.dll",
            "avfilter-*.dll",
        ];

        let mut copied_count = 0;
        for pattern in &dll_patterns {
            if let Ok(entries) = glob::glob(&format!("{}/**/{}", ffmpeg_dlls_dir.display(), pattern)) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name() {
                        let dest = dist_dir.join(filename);
                        fs::copy(&entry, &dest)
                            .with_context(|| format!("Failed to copy {:?}", entry))?;
                        copied_count += 1;
                        println!("      {} {}", "✓".green(), filename.to_string_lossy().dimmed());
                    }
                }
            }
        }

        if copied_count > 0 {
            println!("    {} Copied {} FFmpeg DLLs", "✓".green(), copied_count);
        } else {
            println!("    {} No FFmpeg DLLs found in {}", "!".yellow(), ffmpeg_dlls_dir.display());
        }
    } else {
        println!("    {} FFmpeg DLLs directory not found: {}", "!".yellow(), ffmpeg_dlls_dir.display());
        println!("      For Windows builds, you need FFmpeg DLLs in: .ffmpeg/windows-x64/bin/");
        println!("      Options:");
        println!("        1. Download from: https://github.com/GyanD/codexffmpeg/releases");
        println!("        2. Or build with MSYS2 which auto-bundles DLLs");
    }

    // Also check for runtime DLLs (libgcc, libstdc++, etc.)
    let runtime_dlls = vec![
        "libgcc_s_seh-1.dll",
        "libstdc++-6.dll",
        "libwinpthread-1.dll",
    ];

    // These typically come from MinGW, check common locations
    let mingw_bin_paths = vec![
        PathBuf::from("/mingw64/bin"),
        PathBuf::from("C:/msys64/mingw64/bin"),
        PathBuf::from(".ffmpeg/windows-x64/bin"),
    ];

    for dll_name in &runtime_dlls {
        for mingw_path in &mingw_bin_paths {
            let dll_path = mingw_path.join(dll_name);
            if dll_path.exists() {
                let dest = dist_dir.join(dll_name);
                if !dest.exists() {
                    fs::copy(&dll_path, &dest)
                        .with_context(|| format!("Failed to copy {:?}", dll_path))?;
                    println!("      {} {}", "✓".green(), dll_name.dimmed());
                }
                break;
            }
        }
    }

    Ok(())
}

fn create_archive(platform: &str, variant: &str, dist_dir: &Path) -> Result<()> {
    let git_commit = Command::new("git")
        .args(&["rev-parse", "--short", "HEAD"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "unknown".to_string());

    let archive_name = format!("summit_hip_numbers_{}_{}_{}", platform, variant, git_commit);

    match platform {
        "windows" | "macos" => {
            // Create ZIP
            let zip_path = PathBuf::from("dist").join(format!("{}.zip", archive_name));
            create_zip(dist_dir, &zip_path)?;
            println!("    {} Created: {}", "✓".green(), zip_path.display().to_string().cyan());
        }
        "linux" => {
            // Create tar.gz
            let tar_path = PathBuf::from("dist").join(format!("{}.tar.gz", archive_name));
            create_tar_gz(dist_dir, &tar_path)?;
            println!("    {} Created: {}", "✓".green(), tar_path.display().to_string().cyan());
        }
        _ => {}
    }

    Ok(())
}

fn create_zip(source_dir: &Path, output_path: &Path) -> Result<()> {
    let file = fs::File::create(output_path)?;
    let mut zip = zip::ZipWriter::new(file);

    let options = zip::write::FileOptions::<()>::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o755);

    let base_name = source_dir.file_name().unwrap().to_string_lossy();

    for entry in WalkDir::new(source_dir) {
        let entry = entry?;
        let path = entry.path();
        let relative = path.strip_prefix(source_dir)?;

        if relative.as_os_str().is_empty() {
            continue;
        }

        let zip_path = PathBuf::from(&*base_name).join(relative);
        let zip_path_str = zip_path.to_string_lossy().replace("\\", "/");

        if entry.file_type().is_dir() {
            zip.add_directory(&zip_path_str, options)?;
        } else {
            zip.start_file(&zip_path_str, options)?;
            let contents = fs::read(path)?;
            zip.write_all(&contents)?;
        }
    }

    zip.finish()?;
    Ok(())
}

fn create_tar_gz(source_dir: &Path, output_path: &Path) -> Result<()> {
    let tar_gz = fs::File::create(output_path)?;
    let enc = flate2::write::GzEncoder::new(tar_gz, flate2::Compression::default());
    let mut tar = tar::Builder::new(enc);

    let base_name = source_dir.file_name().unwrap();

    for entry in WalkDir::new(source_dir) {
        let entry = entry?;
        let path = entry.path();
        let relative = path.strip_prefix(source_dir)?;

        if relative.as_os_str().is_empty() {
            continue;
        }

        let tar_path = PathBuf::from(base_name).join(relative);

        if entry.file_type().is_dir() {
            tar.append_dir(&tar_path, path)?;
        } else {
            tar.append_path_with_name(path, &tar_path)?;
        }
    }

    tar.finish()?;
    Ok(())
}
