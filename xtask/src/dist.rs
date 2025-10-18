use anyhow::{Context, Result, bail};
use colored::*;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::fs;
use std::io::Write;
use std::env;
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

    // For macOS, inherit environment variables from the workflow and add FFmpeg-specific ones
    if platform == "macos" {
        // Check if FFMPEG_DIR is already set in the environment (from GitHub Actions)
        if let Ok(ffmpeg_dir) = std::env::var("FFMPEG_DIR") {
            println!("    Using FFMPEG_DIR from environment: {}", ffmpeg_dir);
            cmd.env("FFMPEG_DIR", &ffmpeg_dir);
            cmd.env("FFMPEG_INCLUDE_DIR", format!("{}/include", ffmpeg_dir));
            cmd.env("FFMPEG_LIBRARY_DIR", format!("{}/lib", ffmpeg_dir));
            cmd.env("PKG_CONFIG_PATH", format!("{}/lib/pkgconfig", ffmpeg_dir));

            // Set bindgen-specific environment variables
            cmd.env("BINDGEN_EXTRA_CLANG_ARGS", format!("-I{}/include", ffmpeg_dir));

            // Also set standard paths
            if let Ok(cpath) = std::env::var("CPATH") {
                cmd.env("CPATH", cpath);
            }
            if let Ok(library_path) = std::env::var("LIBRARY_PATH") {
                cmd.env("LIBRARY_PATH", library_path);
            }
        } else {
            // Try to detect from Homebrew
            for (key, value) in ffmpeg::get_env_for_platform(platform, &libs) {
                cmd.env(key, value);
            }
        }
    } else {
        // For other platforms, use the get_env_for_platform function
        for (key, value) in ffmpeg::get_env_for_platform(platform, &libs) {
            cmd.env(key, value);
        }
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
        "linux" => bundle_linux_libs(target_triple, dist_dir)?,
        "macos" => bundle_macos_dylibs(target_triple, dist_dir)?,
        _ => {}
    }

    Ok(())
}

fn bundle_linux_libs(_target_triple: &str, dist_dir: &Path) -> Result<()> {
    println!("    Bundling Linux FFmpeg libraries...");

    // For Linux, we'll bundle FFmpeg .so files
    let ffmpeg_lib_patterns = vec![
        "libavutil.so*",
        "libavcodec.so*",
        "libavformat.so*",
        "libswscale.so*",
        "libswresample.so*",
    ];

    let lib_search_paths = vec![
        "/usr/lib/x86_64-linux-gnu",
        "/usr/lib64",
        "/usr/lib",
    ];

    let mut bundled_count = 0;

    for pattern in &ffmpeg_lib_patterns {
        let mut found = false;
        for search_path in &lib_search_paths {
            let search_pattern = format!("{}/{}", search_path, pattern);
            if let Ok(entries) = glob::glob(&search_pattern) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name() {
                        let dest = dist_dir.join(filename);
                        if let Ok(_) = fs::copy(&entry, &dest) {
                            println!("      {} {}", "✓".green(), filename.to_string_lossy().dimmed());
                            bundled_count += 1;
                            found = true;
                        }
                    }
                }
            }
            if found {
                break;
            }
        }
    }

    if bundled_count > 0 {
        println!("    {} Bundled {} FFmpeg libraries", "✓".green(), bundled_count);

        // Create a launcher script to set LD_LIBRARY_PATH
        let launcher_script = r#"#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$DIR:$LD_LIBRARY_PATH"
exec "$DIR/summit_hip_numbers" "$@"
"#;

        let launcher_path = dist_dir.join("run.sh");
        fs::write(&launcher_path, launcher_script)?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&launcher_path)?.permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&launcher_path, perms)?;
        }

        println!("    {} Created launcher script: run.sh", "✓".green());
    } else {
        println!("    {} No FFmpeg libraries found, will use system libraries", "ℹ".cyan());
    }

    Ok(())
}

fn bundle_macos_dylibs(_target_triple: &str, dist_dir: &Path) -> Result<()> {
    println!("    Bundling macOS FFmpeg dylibs...");

    let homebrew_paths = vec![
        "/opt/homebrew/lib",      // ARM64
        "/usr/local/lib",          // x86_64
    ];

    let dylib_patterns = vec![
        "libavutil.*.dylib",
        "libavcodec.*.dylib",
        "libavformat.*.dylib",
        "libswscale.*.dylib",
        "libswresample.*.dylib",
    ];

    let mut bundled_count = 0;
    let mut bundled_dylibs = Vec::new();

    for homebrew_path in &homebrew_paths {
        if !PathBuf::from(homebrew_path).exists() {
            continue;
        }

        for pattern in &dylib_patterns {
            let search_pattern = format!("{}/{}", homebrew_path, pattern);
            if let Ok(entries) = glob::glob(&search_pattern) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name() {
                        let dest = dist_dir.join(filename);
                        if let Ok(_) = fs::copy(&entry, &dest) {
                            println!("      {} {}", "✓".green(), filename.to_string_lossy().dimmed());
                            bundled_dylibs.push(filename.to_string_lossy().to_string());
                            bundled_count += 1;
                        }
                    }
                }
            }
        }

        if bundled_count > 0 {
            break; // Found libraries, no need to check other paths
        }
    }

    if bundled_count > 0 {
        println!("    {} Bundled {} FFmpeg dylibs", "✓".green(), bundled_count);
    } else {
        println!("    {} No Homebrew FFmpeg dylibs found", "!".yellow());
        println!("      Install with: brew install ffmpeg");
        anyhow::bail!("FFmpeg dylibs not found. Please install with: brew install ffmpeg");
    }

    Ok(())
}

fn bundle_windows_dlls(_target_triple: &str, dist_dir: &Path) -> Result<()> {
    println!("    Bundling Windows DLLs...");

    // Check for FFmpeg DLLs in .ffmpeg/windows-x64/bin
    let ffmpeg_dlls_dir = PathBuf::from(".ffmpeg/windows-x64/bin");

    let mut required_dlls_found = Vec::new();
    let mut required_dlls_missing = Vec::new();

    // Required FFmpeg DLLs for video playback
    let required_dll_patterns = vec![
        ("avutil", "avutil-*.dll"),
        ("avcodec", "avcodec-*.dll"),
        ("avformat", "avformat-*.dll"),
        ("swscale", "swscale-*.dll"),
        ("swresample", "swresample-*.dll"),
    ];

    // Optional FFmpeg DLLs
    let optional_dll_patterns = vec![
        "avdevice-*.dll",
        "avfilter-*.dll",
    ];

    if ffmpeg_dlls_dir.exists() {
        println!("    {} Found FFmpeg directory: {}", "✓".green(), ffmpeg_dlls_dir.display());

        // Copy required FFmpeg DLLs
        for (name, pattern) in &required_dll_patterns {
            let mut found = false;
            if let Ok(entries) = glob::glob(&format!("{}/{}", ffmpeg_dlls_dir.display(), pattern)) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name() {
                        let dest = dist_dir.join(filename);
                        fs::copy(&entry, &dest)
                            .with_context(|| format!("Failed to copy {:?}", entry))?;
                        println!("      {} {}", "✓".green(), filename.to_string_lossy().dimmed());
                        required_dlls_found.push(name.to_string());
                        found = true;
                    }
                }
            }
            if !found {
                required_dlls_missing.push(name.to_string());
            }
        }

        // Copy optional FFmpeg DLLs
        for pattern in &optional_dll_patterns {
            if let Ok(entries) = glob::glob(&format!("{}/{}", ffmpeg_dlls_dir.display(), pattern)) {
                for entry in entries.flatten() {
                    if let Some(filename) = entry.file_name() {
                        let dest = dist_dir.join(filename);
                        fs::copy(&entry, &dest)
                            .with_context(|| format!("Failed to copy {:?}", entry))?;
                        println!("      {} {} (optional)", "✓".green(), filename.to_string_lossy().dimmed());
                    }
                }
            }
        }

        if !required_dlls_missing.is_empty() {
            println!("    {} Missing required DLLs: {}", "✗".red(), required_dlls_missing.join(", "));
            anyhow::bail!("Missing required FFmpeg DLLs: {}", required_dlls_missing.join(", "));
        } else {
            println!("    {} All required FFmpeg DLLs bundled ({} DLLs)", "✓".green(), required_dlls_found.len());
        }
    } else {
        println!("    {} FFmpeg DLLs directory not found: {}", "✗".red(), ffmpeg_dlls_dir.display());
        println!("      Run: cargo build --package xtask --release && ./target/release/xtask dist --platform windows");
        anyhow::bail!("FFmpeg DLLs not found. Please ensure FFmpeg is downloaded.");
    }

    // Also check for runtime DLLs (libgcc, libstdc++, etc.)
    let runtime_dlls = vec![
        "libgcc_s_seh-1.dll",
        "libstdc++-6.dll",
        "libwinpthread-1.dll",
    ];

    println!("    Bundling runtime DLLs...");

    // These typically come from MinGW, check common locations
    let mingw_bin_paths = vec![
        PathBuf::from("/mingw64/bin"),
        PathBuf::from("C:/msys64/mingw64/bin"),
        PathBuf::from(".ffmpeg/windows-x64/bin"),
    ];

    let mut runtime_count = 0;
    for dll_name in &runtime_dlls {
        let mut found = false;
        for mingw_path in &mingw_bin_paths {
            let dll_path = mingw_path.join(dll_name);
            if dll_path.exists() {
                let dest = dist_dir.join(dll_name);
                if !dest.exists() {
                    fs::copy(&dll_path, &dest)
                        .with_context(|| format!("Failed to copy {:?}", dll_path))?;
                    println!("      {} {}", "✓".green(), dll_name.dimmed());
                    runtime_count += 1;
                }
                found = true;
                break;
            }
        }
        if !found {
            println!("      {} {} (not found, may not be needed)", "!".yellow(), dll_name.dimmed());
        }
    }

    if runtime_count > 0 {
        println!("    {} Bundled {} runtime DLLs", "✓".green(), runtime_count);
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
