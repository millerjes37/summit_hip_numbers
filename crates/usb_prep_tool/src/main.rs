use anyhow::{Context, Result};
use eframe::egui;
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use walkdir::WalkDir;
use rfd;

#[derive(Default)]
struct UsbPrepApp {
    drives: Arc<Mutex<HashSet<PathBuf>>>,  // Detected USB drives
    selected_drive: Option<PathBuf>,
    source_folder: Option<PathBuf>,  // dist folder
    status: String,  // "Ready", "Copying...", errors
    watcher: Option<RecommendedWatcher>,  // For drive detection
    is_copying: bool,
    total_files: usize,
    copied_files: usize,
}

impl UsbPrepApp {
    fn new() -> Self {
        let mut app = Self::default();
        app.scan_drives();  // Initial scan
        app.start_watcher();  // Watch for changes
        app.status = "Ready - Select source folder and USB drive".to_string();
        app
    }

    fn scan_drives(&mut self) {
        let volumes = Path::new("/Volumes/");
        let mut drives = HashSet::new();
        if let Ok(entries) = std::fs::read_dir(volumes) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() && Self::is_usb_drive(&path).unwrap_or(false) {
                    drives.insert(path);
                }
            }
        }
        *self.drives.lock().unwrap() = drives;
    }

    fn is_usb_drive(path: &Path) -> Result<bool> {
        // Check if it's not the main system drive
        if let Some(name) = path.file_name() {
            let name_str = name.to_string_lossy();
            // Skip system drives
            if name_str == "Macintosh HD" || name_str.starts_with("com.apple") {
                return Ok(false);
            }
        }

        // Check if it's writable (USB drives should be)
        match std::fs::metadata(path) {
            Ok(metadata) => Ok(metadata.permissions().readonly() == false),
            Err(_) => Ok(false),
        }
    }

    fn start_watcher(&mut self) {
        let drives = self.drives.clone();
        let mut watcher = notify::recommended_watcher(move |res: Result<notify::Event, _>| {
            if let Ok(event) = res {
                if matches!(event.kind, notify::EventKind::Create(_) | notify::EventKind::Remove(_)) {
                    // Rescan drives on any change
                    let mut current = drives.lock().unwrap();
                    current.clear();
                    if let Ok(entries) = std::fs::read_dir("/Volumes/") {
                        for entry in entries.flatten() {
                            let path = entry.path();
                            if path.is_dir() && Self::is_usb_drive(&path).unwrap_or(false) {
                                current.insert(path);
                            }
                        }
                    }
                }
            }
        }).unwrap();

        if let Err(e) = watcher.watch(Path::new("/Volumes/"), RecursiveMode::NonRecursive) {
            eprintln!("Failed to watch /Volumes/: {}", e);
        }
        self.watcher = Some(watcher);
    }

    fn copy_to_drive(&mut self, ctx: &egui::Context) -> Result<()> {
        let source = self.source_folder.as_ref().context("No source folder selected")?;
        let dest = self.selected_drive.as_ref().context("No drive selected")?;

        // Check if destination is writable
        if !Self::is_usb_drive(dest)? {
            anyhow::bail!("Selected drive is not writable or not a valid USB drive");
        }

        self.is_copying = true;
        self.status = "Preparing to copy...".to_string();
        self.copied_files = 0;

        // Count total files first
        self.total_files = WalkDir::new(source)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file())
            .count();

        ctx.request_repaint();

        // Create destination subdirectory
        let dest_subdir = dest.join("SummitHipNumbers");
        std::fs::create_dir_all(&dest_subdir)?;

        // Copy files
        for entry in WalkDir::new(source) {
            let entry = entry?;
            if !entry.file_type().is_file() {
                continue;
            }

            let rel_path = entry.path().strip_prefix(source)?;
            let dest_path = dest_subdir.join(rel_path);

            // Ensure parent directory exists
            if let Some(parent) = dest_path.parent() {
                std::fs::create_dir_all(parent)?;
            }

            std::fs::copy(entry.path(), &dest_path)?;
            self.copied_files += 1;

            // Update progress
            self.status = format!("Copying... {}/{} files", self.copied_files, self.total_files);
            ctx.request_repaint();
        }

        self.status = format!("Copy complete! {} files copied to {}", self.total_files, dest_subdir.display());
        self.is_copying = false;

        Ok(())
    }
}

impl eframe::App for UsbPrepApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("🏗️ Summit USB Prep Tool");
            ui.label("Prepare USB drives for Summit kiosk deployment");
            ui.separator();

            // Source folder selection
            ui.horizontal(|ui| {
                ui.label("📁 Source dist folder:");
                if ui.button("Select Folder").clicked() {
                    if let Some(path) = rfd::FileDialog::new().pick_folder() {
                        self.source_folder = Some(path);
                        self.status = "Source folder selected".to_string();
                    }
                }
            });

            if let Some(path) = &self.source_folder {
                ui.label(format!("Selected: {}", path.display()));
            }

            ui.separator();

            // Drive selection
            ui.label("💾 Detected USB Drives:");
            {
                let drives = self.drives.lock().unwrap();
                if drives.is_empty() {
                    ui.label("No USB drives detected. Please insert a USB drive.");
                } else {
                    for drive in drives.iter() {
                        let drive_name = drive.file_name()
                            .map(|n| n.to_string_lossy().to_string())
                            .unwrap_or_else(|| "Unknown".to_string());

                        let selected = self.selected_drive.as_ref() == Some(drive);
                        if ui.radio(selected, format!("{} ({})", drive_name, drive.display())).clicked() {
                            self.selected_drive = Some(drive.clone());
                            self.status = format!("Selected drive: {}", drive_name);
                        }
                    }
                }
            }

            ui.separator();

            // Copy button
            let can_copy = !self.is_copying &&
                           self.source_folder.is_some() &&
                           self.selected_drive.is_some();

            if ui.add_enabled(can_copy, egui::Button::new("🚀 Copy to Selected Drive")).clicked() {
                if let Err(e) = self.copy_to_drive(ctx) {
                    self.status = format!("❌ Error: {}", e);
                    self.is_copying = false;
                }
            }

            ui.separator();

            // Status
            ui.label(&self.status);

            // Progress bar during copying
            if self.is_copying && self.total_files > 0 {
                let progress = self.copied_files as f32 / self.total_files as f32;
                ui.add(egui::ProgressBar::new(progress).show_percentage());
            }
        });
    }
}

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([400.0, 300.0]),
        ..Default::default()
    };
    eframe::run_native(
        "Summit USB Prep",
        options,
        Box::new(|_cc| Ok(Box::new(UsbPrepApp::new()))),
    )
}