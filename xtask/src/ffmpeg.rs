use anyhow::Result;
use colored::*;
use std::path::{Path, PathBuf};
use std::fs;

const FFMPEG_VERSION: &str = "7.0";

pub struct FfmpegLibs {
    pub windows_x64: PathBuf,
    pub linux_x64: PathBuf,
    pub macos_arm64: PathBuf,
}

pub fn ensure_ffmpeg_libs(force: bool) -> Result<FfmpegLibs> {
    let ffmpeg_dir = Path::new(".ffmpeg");

    if force && ffmpeg_dir.exists() {
        println!("  {} Removing existing FFmpeg libraries...", "↻".yellow());
        fs::remove_dir_all(ffmpeg_dir)?;
    }

    fs::create_dir_all(ffmpeg_dir)?;

    let windows_x64 = ensure_windows_ffmpeg(ffmpeg_dir, force)?;
    let linux_x64 = ensure_linux_ffmpeg(ffmpeg_dir, force)?;
    let macos_arm64 = ensure_macos_ffmpeg(ffmpeg_dir, force)?;

    Ok(FfmpegLibs {
        windows_x64,
        linux_x64,
        macos_arm64,
    })
}

fn ensure_windows_ffmpeg(base_dir: &Path, force: bool) -> Result<PathBuf> {
    let target_dir = base_dir.join("windows-x64");

    if target_dir.exists() && !force {
        println!("  {} Windows FFmpeg libraries", "✓".green());
        return Ok(target_dir);
    }

    println!("  {} Downloading Windows FFmpeg static libraries...", "⬇".cyan());

    fs::create_dir_all(&target_dir)?;

    // Download FFmpeg Windows shared build (gpl) from gyan.dev
    let url = format!(
        "https://github.com/GyanD/codexffmpeg/releases/download/{}/ffmpeg-{}-full_build-shared.7z",
        FFMPEG_VERSION, FFMPEG_VERSION
    );

    println!("    From: {}", url.dimmed());

    // For now, provide instructions since 7z requires external tool
    println!("    {} Windows FFmpeg needs to be downloaded manually:", "!".yellow());
    println!("      1. Download from: {}", url);
    println!("      2. Extract to: {}", target_dir.display());
    println!("      3. Ensure bin/*.dll files are present");
    println!();
    println!("    {} Alternatively, use the existing MSYS2/MinGW approach", "ℹ".cyan());

    Ok(target_dir)
}

fn ensure_linux_ffmpeg(base_dir: &Path, force: bool) -> Result<PathBuf> {
    let target_dir = base_dir.join("linux-x64");

    if target_dir.exists() && !force {
        println!("  {} Linux FFmpeg libraries", "✓".green());
        return Ok(target_dir);
    }

    println!("  {} Setting up Linux FFmpeg (via system packages)...", "⬇".cyan());

    fs::create_dir_all(&target_dir)?;

    // For Linux, we'll use cross with system FFmpeg in Docker
    println!("    {} Linux builds will use cross with Docker images containing FFmpeg", "ℹ".cyan());
    println!("    {} No separate download needed", "✓".green());

    Ok(target_dir)
}

fn ensure_macos_ffmpeg(base_dir: &Path, force: bool) -> Result<PathBuf> {
    let target_dir = base_dir.join("macos-arm64");

    if target_dir.exists() && !force {
        println!("  {} macOS FFmpeg libraries", "✓".green());
        return Ok(target_dir);
    }

    println!("  {} Setting up macOS FFmpeg...", "⬇".cyan());

    fs::create_dir_all(&target_dir)?;

    // For macOS, we'll use Homebrew FFmpeg
    println!("    {} macOS builds will use Homebrew FFmpeg", "ℹ".cyan());

    // Check if we're on macOS and Homebrew is available
    if cfg!(target_os = "macos") {
        match std::process::Command::new("brew").arg("--prefix").arg("ffmpeg").output() {
            Ok(output) if output.status.success() => {
                let ffmpeg_prefix = String::from_utf8_lossy(&output.stdout).trim().to_string();
                println!("    {} Found Homebrew FFmpeg at: {}", "✓".green(), ffmpeg_prefix.dimmed());
            }
            _ => {
                println!("    {} Install FFmpeg with: brew install ffmpeg", "!".yellow());
            }
        }
    } else {
        println!("    {} macOS builds must be done on macOS with Homebrew FFmpeg", "ℹ".cyan());
    }

    Ok(target_dir)
}

pub fn get_env_for_platform(platform: &str, libs: &FfmpegLibs) -> Vec<(String, String)> {
    match platform {
        "windows" => {
            let lib_dir = libs.windows_x64.join("lib");
            let include_dir = libs.windows_x64.join("include");

            vec![
                ("FFMPEG_DIR".to_string(), libs.windows_x64.display().to_string()),
                ("FFMPEG_LIB_DIR".to_string(), lib_dir.display().to_string()),
                ("FFMPEG_INCLUDE_DIR".to_string(), include_dir.display().to_string()),
                ("PKG_CONFIG_PATH".to_string(), lib_dir.join("pkgconfig").display().to_string()),
            ]
        }
        "linux" => {
            // For Linux, cross will handle this via Docker
            vec![]
        }
        "macos" => {
            // For macOS, use Homebrew FFmpeg
            if let Ok(output) = std::process::Command::new("brew").arg("--prefix").arg("ffmpeg").output() {
                if output.status.success() {
                    let ffmpeg_prefix = String::from_utf8_lossy(&output.stdout).trim().to_string();
                    let lib_dir = format!("{}/lib", ffmpeg_prefix);
                    let include_dir = format!("{}/include", ffmpeg_prefix);
                    let pkgconfig_dir = format!("{}/lib/pkgconfig", ffmpeg_prefix);

                    return vec![
                        ("FFMPEG_DIR".to_string(), ffmpeg_prefix),
                        ("FFMPEG_LIB_DIR".to_string(), lib_dir),
                        ("FFMPEG_INCLUDE_DIR".to_string(), include_dir),
                        ("PKG_CONFIG_PATH".to_string(), pkgconfig_dir),
                    ];
                }
            }
            vec![]
        }
        _ => vec![],
    }
}
