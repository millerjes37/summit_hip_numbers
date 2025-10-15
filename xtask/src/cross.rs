use anyhow::{Context, Result};
use colored::*;
use std::process::Command;

pub fn ensure_cross() -> Result<()> {
    // Check if cross is installed
    match which::which("cross") {
        Ok(cross_path) => {
            println!("  {} cross installed at: {}", "✓".green(), cross_path.display().to_string().dimmed());

            // Verify cross version
            let output = Command::new("cross")
                .arg("--version")
                .output()
                .context("Failed to get cross version")?;

            if output.status.success() {
                let version = String::from_utf8_lossy(&output.stdout);
                println!("    Version: {}", version.trim().dimmed());
            }
        }
        Err(_) => {
            println!("  {} cross not found, installing...", "!".yellow());
            install_cross()?;
        }
    }

    Ok(())
}

fn install_cross() -> Result<()> {
    println!("    Installing cross via cargo...");

    let status = Command::new("cargo")
        .args(&["install", "cross", "--git", "https://github.com/cross-rs/cross"])
        .status()
        .context("Failed to install cross")?;

    if !status.success() {
        anyhow::bail!("Failed to install cross");
    }

    println!("  {} cross installed successfully", "✓".green());

    Ok(())
}

pub fn get_target_triple(platform: &str, arch: &str) -> &'static str {
    match (platform, arch) {
        ("windows", "x64") => "x86_64-pc-windows-gnu",
        ("linux", "x64") => "x86_64-unknown-linux-gnu",
        ("macos", "arm64") => "aarch64-apple-darwin",
        ("macos", "x64") => "x86_64-apple-darwin",
        _ => panic!("Unsupported platform/arch combination: {}/{}", platform, arch),
    }
}

pub fn should_use_cross(platform: &str) -> bool {
    // Use cross for Windows and Linux when not on that platform
    match platform {
        "windows" => !cfg!(target_os = "windows"),
        "linux" => !cfg!(target_os = "linux"),
        "macos" => false, // macOS cross-compilation is more complex, build natively
        _ => false,
    }
}
