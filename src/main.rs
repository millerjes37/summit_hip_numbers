mod file_scanner;
mod video_player;

use clap::Parser;
use eframe::egui;
use dunce;
use gstreamer::glib;

#[derive(Parser)]
struct Args {
    #[arg(long)]
    config: bool,
}
use file_scanner::{VideoFile, scan_video_files};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use tokio::sync::watch;
use video_player::VideoPlayer;

use log::{info, error, warn};
use fern;
use chrono;

#[derive(Debug, Deserialize, serde::Serialize)]
struct Config {
    video: VideoConfig,
    splash: SplashConfig,
    logging: LoggingConfig,
    ui: UiConfig,
}

#[derive(Debug, Deserialize, serde::Serialize)]
struct VideoConfig {
    directory: String,
}

#[derive(Debug, Deserialize, serde::Serialize)]
struct SplashConfig {
    enabled: bool,
    duration_seconds: f64,
    text: String,
    background_color: String,
    text_color: String,
    interval: String,
    directory: String,
}

#[derive(Debug, Deserialize, serde::Serialize)]
struct LoggingConfig {
    file: String,
    max_lines: usize,
}

#[derive(Debug, Deserialize, serde::Serialize)]
struct UiConfig {
    input_label: String,
    now_playing_label: String,
    company_label: String,
    input_text_color: String,
    input_stroke_color: String,
    label_color: String,
    background_color: String,
}

struct ConfigApp {
    config: Config,
    video_dir_input: String,
    splash_enabled: bool,
    splash_duration: String,
    splash_text: String,
    splash_bg_color: String,
    splash_text_color: String,
    splash_interval: String,
    splash_dir_input: String,
    input_label: String,
    now_playing_label: String,
    company_label: String,
    input_text_color: String,
    input_stroke_color: String,
    label_color: String,
    background_color: String,
    message: Option<String>,
}

impl ConfigApp {
    fn new() -> Self {
        let mut app = Self::load_config();
        app.video_dir_input = app.config.video.directory.clone();
        app.splash_enabled = app.config.splash.enabled;
        app.splash_duration = app.config.splash.duration_seconds.to_string();
        app.splash_text = app.config.splash.text.clone();
        app.splash_bg_color = app.config.splash.background_color.clone();
        app.splash_text_color = app.config.splash.text_color.clone();
        app.splash_interval = app.config.splash.interval.clone();
        app.splash_dir_input = app.config.splash.directory.clone();
        app.input_label = app.config.ui.input_label.clone();
        app.now_playing_label = app.config.ui.now_playing_label.clone();
        app.company_label = app.config.ui.company_label.clone();
        app.input_text_color = app.config.ui.input_text_color.clone();
        app.input_stroke_color = app.config.ui.input_stroke_color.clone();
        app.label_color = app.config.ui.label_color.clone();
        app.background_color = app.config.ui.background_color.clone();
        app
    }

    fn load_config() -> Self {
        let exe_dir = std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
        let config_path = exe_dir.join("config.toml");
        let mut config = Config {
            video: VideoConfig {
                directory: "./videos".to_string(),
            },
            splash: SplashConfig {
                enabled: true,
                duration_seconds: 3.0,
                text: "Summit Professional Services".to_string(),
                background_color: "#000000".to_string(),
                text_color: "#FFFFFF".to_string(),
                interval: "once".to_string(),
                directory: "./splash".to_string(),
            },
            logging: LoggingConfig {
                file: "summit_hip_numbers.log".to_string(),
                max_lines: 10000,
            },
            ui: UiConfig {
                input_label: "3-digit hip number:".to_string(),
                now_playing_label: "now playing".to_string(),
                company_label: "SUMMIT PROFESSIONAL Solutions".to_string(),
                input_text_color: "#FFFFFF".to_string(),
                input_stroke_color: "#FFFFFF".to_string(),
                label_color: "#FFFFFF".to_string(),
                background_color: "#000000".to_string(),
            },
        };
        if let Ok(config_str) = fs::read_to_string(config_path) {
            if let Ok(loaded_config) = toml::from_str(&config_str) {
                config = loaded_config;
            }
        }
        Self {
            config,
            video_dir_input: String::new(),
            splash_enabled: false,
            splash_duration: String::new(),
            splash_text: String::new(),
            splash_bg_color: String::new(),
            splash_text_color: String::new(),
            splash_interval: String::new(),
            splash_dir_input: String::new(),
            input_label: String::new(),
            now_playing_label: String::new(),
            company_label: String::new(),
            input_text_color: String::new(),
            input_stroke_color: String::new(),
            label_color: String::new(),
            background_color: String::new(),
            message: None,
        }
    }

    fn save_config(&mut self) {
        self.config.video.directory = self.video_dir_input.clone();
        self.config.splash.enabled = self.splash_enabled;
        if let Ok(duration) = self.splash_duration.parse::<f64>() {
            self.config.splash.duration_seconds = duration;
        }
        self.config.splash.text = self.splash_text.clone();
        self.config.splash.background_color = self.splash_bg_color.clone();
        self.config.splash.text_color = self.splash_text_color.clone();
        self.config.splash.interval = self.splash_interval.clone();
        self.config.splash.directory = self.splash_dir_input.clone();
        self.config.ui.input_label = self.input_label.clone();
        self.config.ui.now_playing_label = self.now_playing_label.clone();
        self.config.ui.company_label = self.company_label.clone();
        self.config.ui.input_text_color = self.input_text_color.clone();
        self.config.ui.input_stroke_color = self.input_stroke_color.clone();
        self.config.ui.label_color = self.label_color.clone();
        self.config.ui.background_color = self.background_color.clone();

        let exe_dir = std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
        let config_path = exe_dir.join("config.toml");
        if let Ok(toml_str) = toml::to_string(&self.config) {
            if fs::write(&config_path, toml_str).is_ok() {
                self.message = Some("Configuration saved successfully!".to_string());
            } else {
                self.message = Some("Failed to save configuration.".to_string());
            }
        } else {
            self.message = Some("Failed to serialize configuration.".to_string());
        }
    }
}

impl eframe::App for ConfigApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("Summit Hip Numbers Configuration");

            ui.separator();

            ui.label("Video Directory:");
            ui.text_edit_singleline(&mut self.video_dir_input);

            ui.separator();

            ui.checkbox(&mut self.splash_enabled, "Enable Splash Screen");

            if self.splash_enabled {
                ui.label("Splash Duration (seconds):");
                ui.text_edit_singleline(&mut self.splash_duration);

                ui.label("Splash Text:");
                ui.text_edit_singleline(&mut self.splash_text);

                ui.label("Background Color (hex, e.g., #000000):");
                ui.text_edit_singleline(&mut self.splash_bg_color);

                ui.label("Text Color (hex, e.g., #FFFFFF):");
                ui.text_edit_singleline(&mut self.splash_text_color);

                ui.label("Splash Interval:");
                egui::ComboBox::from_label("Select interval")
                    .selected_text(&self.splash_interval)
                    .show_ui(ui, |ui| {
                        ui.selectable_value(&mut self.splash_interval, "once".to_string(), "Once at start");
                        ui.selectable_value(&mut self.splash_interval, "every".to_string(), "Every video");
                        ui.selectable_value(&mut self.splash_interval, "every_other".to_string(), "Every other video");
                        ui.selectable_value(&mut self.splash_interval, "every_third".to_string(), "Every third video");
                    });

                ui.label("Splash Directory:");
                ui.text_edit_singleline(&mut self.splash_dir_input);
            }

            ui.separator();

            ui.label("UI Labels:");
            ui.label("Input Label:");
            ui.text_edit_singleline(&mut self.input_label);
            ui.label("Now Playing Label:");
            ui.text_edit_singleline(&mut self.now_playing_label);
            ui.label("Company Label:");
            ui.text_edit_singleline(&mut self.company_label);

            ui.label("UI Colors (hex):");
            ui.label("Input Text Color:");
            ui.text_edit_singleline(&mut self.input_text_color);
            ui.label("Input Stroke Color:");
            ui.text_edit_singleline(&mut self.input_stroke_color);
            ui.label("Label Color:");
            ui.text_edit_singleline(&mut self.label_color);
            ui.label("Background Color:");
            ui.text_edit_singleline(&mut self.background_color);

            ui.separator();

            if ui.button("Save Configuration").clicked() {
                self.save_config();
            }

            if ui.button("Launch Player").clicked() {
                self.save_config();
                std::process::Command::new(std::env::current_exe().unwrap())
                    .spawn()
                    .ok();
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            }

            if let Some(msg) = &self.message {
                ui.separator();
                ui.label(msg);
            }
        });
    }
}

struct MediaPlayerApp {
    config: Config,
    video_files: Vec<VideoFile>,
    hip_to_index: HashMap<String, usize>,
    current_index: usize,
    input_buffer: String,
    current_file_name: String,
    splash_timer: f64,
    show_splash: bool,
    video_player: Option<VideoPlayer>,
    load_video_index: Option<usize>,
    invalid_input_timer: f64,
    texture_sender: watch::Sender<Option<egui::ColorImage>>,
    texture_receiver: watch::Receiver<Option<egui::ColorImage>>,
    current_texture: Option<egui::TextureHandle>,
    show_no_video_popup: bool,
    no_video_popup_timer: f64,
    no_video_hip: String,
    splash_images: Vec<PathBuf>,
    current_splash_index: usize,
    videos_played: usize,
    splash_texture: Option<egui::TextureHandle>,
}

impl Default for MediaPlayerApp {
    fn default() -> Self {
        let (tx, rx) = watch::channel(None);
        Self {
            config: Config {
                video: VideoConfig {
                    directory: "./videos".to_string(),
                },
                splash: SplashConfig {
                    enabled: true,
                    duration_seconds: 3.0,
                    text: "Summit Professional Services".to_string(),
                    background_color: "#000000".to_string(),
                    text_color: "#FFFFFF".to_string(),
                    interval: "once".to_string(),
                    directory: "./splash".to_string(),
                },
                logging: LoggingConfig {
                    file: "summit_hip_numbers.log".to_string(),
                    max_lines: 10000,
                },
                ui: UiConfig {
                    input_label: "3-digit hip number:".to_string(),
                    now_playing_label: "now playing".to_string(),
                    company_label: "SUMMIT PROFESSIONAL Solutions".to_string(),
                    input_text_color: "#FFFFFF".to_string(),
                    input_stroke_color: "#FFFFFF".to_string(),
                    label_color: "#FFFFFF".to_string(),
                    background_color: "#000000".to_string(),
                },
            },
            video_files: Vec::new(),
            hip_to_index: HashMap::new(),
            current_index: 0,
            input_buffer: String::new(),
            current_file_name: "No file loaded".to_string(),
            splash_timer: 0.0,
            show_splash: true,
            video_player: None,
            load_video_index: None,
            invalid_input_timer: 0.0,
            texture_sender: tx,
            texture_receiver: rx,
            current_texture: None,
            show_no_video_popup: false,
            no_video_popup_timer: 0.0,
            no_video_hip: String::new(),
            splash_images: Vec::new(),
            current_splash_index: 0,
            videos_played: 0,
            splash_texture: None,
        }
    }
}

impl MediaPlayerApp {
    fn new() -> Self {
        let mut app = Self::load_config();
        app.load_video_files();
        if !app.video_files.is_empty() {
            app.load_video_index = Some(0);
        }
        app
    }

    fn load_config() -> Self {
        let mut app = Self::default();
        let exe_dir = std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
        let config_path = exe_dir.join("config.toml");
        info!("Loading config from {}", config_path.display());
        if let Ok(config_str) = fs::read_to_string(&config_path) {
            match toml::from_str(&config_str) {
                Ok(config) => {
                    app.config = config;
                    app.show_splash = app.config.splash.enabled;
                    info!("Config loaded successfully");
                }
                Err(e) => {
                    error!("Failed to parse config: {}", e);
                }
            }
        } else {
            warn!("Config file not found, using defaults");
        }
        // Set default video directory relative to exe
        if app.config.video.directory == "./videos" {
            app.config.video.directory = exe_dir.join("videos").to_string_lossy().to_string();
        }
        app
    }

    fn load_video_files(&mut self) {
        let video_dir = self.config.video.directory.clone();
        info!("Loading video files from {}", video_dir);

        match scan_video_files(&video_dir) {
            Ok(files) => {
                self.video_files = files;
                info!("Scanned {} video files", self.video_files.len());

                // Create lookup map for fast hip number access
                self.hip_to_index.clear();
                for (index, video) in self.video_files.iter().enumerate() {
                    self.hip_to_index.insert(video.hip_number.clone(), index);
                }

                if !self.video_files.is_empty() {
                    self.current_index = 0;
                }
            }
            Err(e) => {
                error!("Failed to scan video files: {}", e);
            }
        }

        // Load splash images
        self.load_splash_images();

        // Trim log file
        self.trim_log();
    }

    fn load_splash_images(&mut self) {
        self.splash_images.clear();
        let splash_dir = PathBuf::from(&self.config.splash.directory);
        if splash_dir.exists() {
            if let Ok(entries) = fs::read_dir(&splash_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        if let Some(ext) = path.extension() {
                            if matches!(ext.to_str(), Some("png") | Some("jpg") | Some("jpeg") | Some("bmp")) {
                                self.splash_images.push(path);
                            }
                        }
                    }
                }
            }
            info!("Loaded {} splash images from {}", self.splash_images.len(), splash_dir.display());
        } else {
            warn!("Splash directory {} does not exist", splash_dir.display());
        }
    }

    fn should_show_splash(&self) -> bool {
        if !self.config.splash.enabled {
            return false;
        }
        match self.config.splash.interval.as_str() {
            "once" => self.videos_played == 0,
            "every" => self.videos_played > 0,
            "every_other" => self.videos_played > 0 && self.videos_played % 2 == 1,
            "every_third" => self.videos_played > 0 && self.videos_played % 3 == 1,
            _ => false,
        }
    }

    fn trim_log(&self) {
        let log_path = PathBuf::from(&self.config.logging.file);
        if let Ok(content) = fs::read_to_string(&log_path) {
            let lines: Vec<&str> = content.lines().collect();
            if lines.len() > self.config.logging.max_lines {
                let start = lines.len() - self.config.logging.max_lines;
                let trimmed = lines[start..].join("\n");
                if fs::write(&log_path, trimmed + "\n").is_ok() {
                    info!("Trimmed log file to {} lines", self.config.logging.max_lines);
                } else {
                    error!("Failed to trim log file");
                }
            }
        } else {
            warn!("Log file not found for trimming");
        }
    }

    fn load_video(&mut self, index: usize) {
        // Stop and drop the current player
        if let Some(player) = self.video_player.take() {
            if let Err(e) = player.stop() {
                eprintln!("Error stopping player: {}", e);
            }
            // Give GStreamer a moment to clean up
            std::thread::sleep(std::time::Duration::from_millis(100));
        }

        if let Some(video_file) = self.video_files.get(index) {
            self.current_index = index;
            self.current_file_name = video_file.name.clone();
            info!("Loading video: {}", std::path::Path::new(&video_file.path).display());

            let abs_path = match dunce::canonicalize(&video_file.path) {
                Ok(path) => path,
                Err(e) => {
                    error!("Failed to canonicalize path {}: {}", video_file.path, e);
                    self.current_file_name = format!("Error: {}", e);
                    return;
                }
            };
            let uri = match glib::filename_to_uri(&abs_path, None) {
                Ok(uri) => uri.to_string(),
                Err(e) => {
                    error!("Failed to convert path to URI {}: {}", abs_path.display(), e);
                    self.current_file_name = format!("Error: {}", e);
                    return;
                }
            };

            match VideoPlayer::new(&uri, self.texture_sender.clone()) {
                Ok(player) => {
                    if let Err(e) = player.play() {
                        error!("Failed to play video: {}", e);
                        self.current_file_name = format!("Error: {}", e);
                    } else {
                        self.video_player = Some(player);
                        info!("Video player started for {}", uri);
                    }
                }
                Err(e) => {
                    error!("Failed to create player: {}", e);
                    self.current_file_name = format!("Error: {}", e);
                }
            }
        } else {
            error!("Invalid video index {}", index);
        }

        // Trim log after loading video
        self.trim_log();
    }

    fn validate_and_switch(&mut self, input: &str) -> bool {
        if input.len() == 3 && input.chars().all(|c| c.is_ascii_digit()) {
            if let Some(&index) = self.hip_to_index.get(input) {
                self.load_video_index = Some(index);
                self.videos_played += 1;
                info!("Switching to video index {} for hip {}", index, input);
                return true;
            } else {
                // No video found
                self.show_no_video_popup = true;
                self.no_video_popup_timer = 3.0;
                self.no_video_hip = input.to_string();
            }
        }
        false
    }

    fn next_video(&mut self) {
        if !self.video_files.is_empty() {
            let next_index = (self.current_index + 1) % self.video_files.len();
            self.load_video_index = Some(next_index);
        }
    }

    fn hex_to_color(hex: &str) -> egui::Color32 {
        let hex = hex.trim_start_matches('#');
        if hex.len() == 6 {
            if let (Ok(r), Ok(g), Ok(b)) = (
                u8::from_str_radix(&hex[0..2], 16),
                u8::from_str_radix(&hex[2..4], 16),
                u8::from_str_radix(&hex[4..6], 16),
            ) {
                return egui::Color32::from_rgb(r, g, b);
            }
        }
        egui::Color32::WHITE
    }

    fn update_playback(&mut self, _current_time: f64) {
        if let Some(player) = &self.video_player {
            // Check for errors first
            if let Some(error) = player.get_error() {
                error!("Playback error detected: {}", error);
                self.next_video();
                return;
            }

            // Check for end of stream
            if player.is_eos() {
                info!("EOS detected, loading next video");
                self.next_video();
            }
        }
    }
}

impl eframe::App for MediaPlayerApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        let current_time = ctx.input(|i| i.time);

        if self.show_splash {
            self.splash_timer += ctx.input(|i| i.unstable_dt) as f64;
            if self.splash_timer >= self.config.splash.duration_seconds {
                self.show_splash = false;
                self.splash_texture = None;
            } else {
                // Load splash texture if not loaded
                if self.splash_texture.is_none() {
                    if let Some(path) = self.splash_images.get(self.current_splash_index) {
                        match image::open(path) {
                            Ok(img) => {
                                let rgba = img.to_rgba8();
                                let size = [rgba.width() as usize, rgba.height() as usize];
                                let pixels = rgba.into_raw();
                                let color_image = egui::ColorImage::from_rgba_unmultiplied(size, &pixels);
                                self.splash_texture = Some(ctx.load_texture("splash", color_image, Default::default()));
                                info!("Loaded splash image {}", path.display());
                            }
                            Err(e) => {
                                error!("Failed to load splash image {}: {}", path.display(), e);
                            }
                        }
                    }
                }

                egui::CentralPanel::default().show(ctx, |ui| {
                    let bg_color = Self::hex_to_color(&self.config.splash.background_color);
                    ui.painter().rect_filled(ui.max_rect(), 0.0, bg_color);
                    if let Some(texture) = &self.splash_texture {
                        ui.centered_and_justified(|ui| {
                            ui.image((texture.id(), ui.available_size()));
                        });
                    } else {
                        let text_color = Self::hex_to_color(&self.config.splash.text_color);
                        ui.centered_and_justified(|ui| {
                            ui.label(
                                egui::RichText::new(&self.config.splash.text)
                                    .size(48.0)
                                    .color(text_color),
                            );
                        });
                    }
                });
                ctx.request_repaint();
                return;
            }
        }

        if self.invalid_input_timer > 0.0 {
            self.invalid_input_timer -= ctx.input(|i| i.unstable_dt) as f64;
        }

        if self.show_no_video_popup {
            self.no_video_popup_timer -= ctx.input(|i| i.unstable_dt) as f64;
            if self.no_video_popup_timer <= 0.0 {
                self.show_no_video_popup = false;
            }
        }

        // Check if we should show splash
        if self.should_show_splash() && !self.show_splash {
            self.show_splash = true;
            self.splash_timer = 0.0;
            self.current_splash_index = (self.current_splash_index + 1) % self.splash_images.len().max(1);
            self.splash_texture = None; // Reset to load new
            info!("Showing splash screen, index {}", self.current_splash_index);
        }

        ctx.input_mut(|i| {
            for event in &i.events {
                if let egui::Event::Text(text) = event {
                    if self.input_buffer.len() < 3 && text.chars().all(|c| c.is_ascii_digit()) {
                        self.input_buffer.push_str(text);
                    }
                }
            }
        });

        if ctx.input(|i| i.key_pressed(egui::Key::Enter)) {
            if !self.input_buffer.is_empty() {
                let input = self.input_buffer.clone();
                if !self.validate_and_switch(&input) {
                    self.invalid_input_timer = 0.5;
                }
                self.input_buffer.clear();
            }
        }

        if let Some(index) = self.load_video_index.take() {
            self.load_video(index);
        }

        self.update_playback(current_time);

        if self.texture_receiver.has_changed().unwrap_or(false) {
            if let Some(image) = self.texture_receiver.borrow().clone() {
                self.current_texture =
                    Some(ctx.load_texture("video_frame", image, Default::default()));
            }
        }

        ctx.request_repaint();

        egui::CentralPanel::default().show(ctx, |ui| {
            let available_rect = ui.max_rect();
            let video_height = available_rect.height() * 0.92;
            let video_rect = egui::Rect::from_min_size(
                available_rect.min,
                egui::vec2(available_rect.width(), video_height),
            );

            ui.allocate_new_ui(egui::UiBuilder::new().max_rect(video_rect), |ui| {
                ui.painter()
                    .rect_filled(ui.max_rect(), 0.0, Self::hex_to_color(&self.config.ui.background_color));
                if let Some(texture) = &self.current_texture {
                    ui.image((texture.id(), ui.available_size()));
                } else {
                    ui.centered_and_justified(|ui| {
                        ui.label(
                            egui::RichText::new("🎬 VIDEO DISPLAY AREA")
                                .size(48.0)
                                .color(Self::hex_to_color(&self.config.ui.label_color)),
                        );
                    });
                }
            });

            let bar_height = available_rect.height() * 0.08;
            let bar_rect = egui::Rect::from_min_size(
                egui::pos2(available_rect.min.x, available_rect.min.y + video_height),
                egui::vec2(available_rect.width(), bar_height),
            );

            ui.painter()
                .rect_filled(bar_rect, 0.0, Self::hex_to_color(&self.config.ui.background_color));

            ui.allocate_new_ui(egui::UiBuilder::new().max_rect(bar_rect), |ui| {
                ui.horizontal_centered(|ui| {
                    ui.with_layout(egui::Layout::left_to_right(egui::Align::Center), |ui| {
                        ui.label(
                            egui::RichText::new(&self.config.ui.input_label).color(Self::hex_to_color(&self.config.ui.label_color)),
                        );
                        ui.add_space(10.0);

                        let text_color = if self.invalid_input_timer > 0.0 {
                            egui::Color32::RED
                        } else {
                            Self::hex_to_color(&self.config.ui.input_text_color)
                        };

                        let response = ui.add(
                            egui::TextEdit::singleline(&mut self.input_buffer)
                                .char_limit(3)
                                .desired_width(45.0)
                                .text_color(text_color)
                                .frame(false),
                        );

                        let stroke_color = if self.invalid_input_timer > 0.0 {
                            egui::Color32::RED
                        } else {
                            Self::hex_to_color(&self.config.ui.input_stroke_color)
                        };

                        ui.painter().rect_stroke(
                            response.rect,
                            1.0,
                            egui::Stroke::new(1.0, stroke_color),
                        );
                    });

                    ui.with_layout(
                        egui::Layout::centered_and_justified(egui::Direction::TopDown),
                        |ui| {
                            ui.label(
                                egui::RichText::new(format!(
                                    "{} {}",
                                    self.config.ui.now_playing_label,
                                    self.current_file_name
                                ))
                                .color(Self::hex_to_color(&self.config.ui.label_color)),
                            );
                        },
                    );

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.label(
                            egui::RichText::new(&self.config.ui.company_label)
                                .color(Self::hex_to_color(&self.config.ui.label_color)),
                        );
                    });
                });
            });
        });

        if self.show_no_video_popup {
            egui::Window::new("No Video Available")
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, egui::Vec2::ZERO)
                .show(ctx, |ui| {
                    ui.label(format!("No video available for hip number {}.", self.no_video_hip));
                    ui.label("Please try another number.");
                });
        }
    }
}

fn load_config_for_logging() -> LoggingConfig {
    let exe_dir = std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
    let config_path = exe_dir.join("config.toml");
    if let Ok(config_str) = fs::read_to_string(&config_path) {
        if let Ok(config) = toml::from_str::<Config>(&config_str) {
            return config.logging;
        }
    }
    LoggingConfig {
        file: "summit_hip_numbers.log".to_string(),
        max_lines: 10000,
    }
}

fn main() -> eframe::Result<()> {
    let logging_config = load_config_for_logging();

    // Set up logging
    let logger = fern::Dispatch::new()
        .format(|out, message, record| {
            out.finish(format_args!(
                "{}[{}][{}] {}",
                chrono::Local::now().format("%Y-%m-%d %H:%M:%S"),
                record.target(),
                record.level(),
                message
            ))
        })
        .level(log::LevelFilter::Debug)
        .chain(std::io::stdout())
        .chain(fern::log_file(&logging_config.file).unwrap());
    logger.apply().unwrap();

    info!("Starting Summit Hip Numbers Media Player");

    let args = Args::parse();

    if args.config {
        // Launch config app
        let options = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default().with_inner_size([800.0, 600.0]),
            ..Default::default()
        };
        eframe::run_native(
            "Summit Hip Numbers Config",
            options,
            Box::new(|_cc| Ok(Box::new(ConfigApp::new()))),
        )
    } else {
        // Set GStreamer plugin path for bundled plugins
        if let Ok(exe_path) = std::env::current_exe() {
            if let Some(exe_dir) = exe_path.parent() {
                 // For portable distribution, check for gstreamer directory
                let gstreamer_plugin_path = exe_dir.join("lib").join("gstreamer-1.0");
                 if gstreamer_plugin_path.exists() {
                    info!("Found bundled GStreamer plugins at: {}", gstreamer_plugin_path.display());
                    std::env::set_var("GST_PLUGIN_PATH", gstreamer_plugin_path);
                 } else {
                    warn!("Bundled GStreamer plugin directory not found. Relying on system-wide installation.");
                 }
            }
        }

        gstreamer::init().expect("Failed to initialize GStreamer");

        let options = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default().with_inner_size([1920.0, 1080.0]),
            ..Default::default()
        };

        eframe::run_native(
            "Summit Hip Numbers Media Player",
            options,
            Box::new(|_cc| Ok(Box::new(MediaPlayerApp::new()))),
        )
    }
}
