use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use colored::*;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::fs;

mod ffmpeg;
mod dist;
mod cross;

#[derive(Parser)]
#[command(name = "xtask")]
#[command(about = "Build automation for Summit HIP Numbers", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Build for all platforms and create distributions
    Dist {
        /// Build only for specific platform (windows, linux, macos)
        #[arg(long)]
        platform: Option<String>,

        /// Build variant (full or demo)
        #[arg(long, default_value = "full")]
        variant: String,

        /// Build all variants
        #[arg(long)]
        all: bool,
    },

    /// Download and set up FFmpeg static libraries
    FfmpegSetup {
        /// Force re-download even if libraries exist
        #[arg(long)]
        force: bool,
    },

    /// Set up cross-compilation tools
    CrossSetup,

    /// Clean build artifacts
    Clean {
        /// Also clean downloaded FFmpeg libraries
        #[arg(long)]
        all: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    // Ensure we're in the project root
    let project_root = project_root()?;
    std::env::set_current_dir(&project_root)?;

    match cli.command {
        Commands::Dist { platform, variant, all } => {
            println!("{}", "=== Summit HIP Numbers - Unified Build System ===".cyan().bold());

            // Set up FFmpeg if not already done
            println!("\n{}", "Checking FFmpeg static libraries...".yellow());
            ffmpeg::ensure_ffmpeg_libs(false)?;

            // Set up cross if building for Linux/Windows
            if platform.is_none() || platform.as_deref() == Some("linux") || platform.as_deref() == Some("windows") {
                println!("\n{}", "Checking cross-compilation tools...".yellow());
                cross::ensure_cross()?;
            }

            // Build distributions
            let variants = if all {
                vec!["full".to_string(), "demo".to_string()]
            } else {
                vec![variant]
            };

            let platforms = if let Some(p) = platform {
                vec![p]
            } else {
                vec!["windows".to_string(), "linux".to_string(), "macos".to_string()]
            };

            for platform in &platforms {
                for variant in &variants {
                    println!("\n{}", format!("Building {} - {} variant", platform, variant).green().bold());
                    dist::build_platform(platform, variant)?;
                }
            }

            println!("\n{}", "✓ All builds completed successfully!".green().bold());
            println!("Distributions available in: {}", "dist/".cyan());
        }

        Commands::FfmpegSetup { force } => {
            println!("{}", "=== FFmpeg Static Library Setup ===".cyan().bold());
            ffmpeg::ensure_ffmpeg_libs(force)?;
            println!("\n{}", "✓ FFmpeg libraries ready!".green().bold());
        }

        Commands::CrossSetup => {
            println!("{}", "=== Cross-Compilation Setup ===".cyan().bold());
            cross::ensure_cross()?;
            println!("\n{}", "✓ Cross-compilation tools ready!".green().bold());
        }

        Commands::Clean { all } => {
            println!("{}", "=== Cleaning Build Artifacts ===".yellow());

            // Clean cargo build artifacts
            run_cmd("cargo", &["clean"])?;

            // Clean dist directory
            if Path::new("dist").exists() {
                fs::remove_dir_all("dist")?;
                println!("  ✓ Removed dist/");
            }

            // Clean FFmpeg if requested
            if all {
                if Path::new(".ffmpeg").exists() {
                    fs::remove_dir_all(".ffmpeg")?;
                    println!("  ✓ Removed .ffmpeg/");
                }
            }

            println!("\n{}", "✓ Cleanup complete!".green().bold());
        }
    }

    Ok(())
}

fn project_root() -> Result<PathBuf> {
    let dir = std::env::current_dir()?;
    let mut current = dir.as_path();

    loop {
        if current.join("Cargo.toml").exists() && current.join("crates").exists() {
            return Ok(current.to_path_buf());
        }

        match current.parent() {
            Some(parent) => current = parent,
            None => bail!("Could not find project root"),
        }
    }
}

fn run_cmd(program: &str, args: &[&str]) -> Result<()> {
    let status = Command::new(program)
        .args(args)
        .status()
        .with_context(|| format!("Failed to execute: {} {:?}", program, args))?;

    if !status.success() {
        bail!("Command failed: {} {:?}", program, args);
    }

    Ok(())
}
