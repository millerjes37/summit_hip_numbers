mod file_scanner;
mod video_player;

use eframe::egui;
use file_scanner::{VideoFile, scan_video_files};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;

use tokio::sync::watch;
use video_player::VideoPlayer;

#[derive(Debug, Deserialize)]
struct Config {
    video: VideoConfig,
    splash: SplashConfig,
}

#[derive(Debug, Deserialize)]
struct VideoConfig {
    directory: String,
}

#[derive(Debug, Deserialize)]
struct SplashConfig {
    enabled: bool,
    duration_seconds: f64,
    text: String,
    background_color: String,
    text_color: String,
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
        if let Ok(config_str) = fs::read_to_string("config.toml") {
            if let Ok(config) = toml::from_str(&config_str) {
                app.config = config;
                app.show_splash = app.config.splash.enabled;
            }
        }
        app
    }

    fn load_video_files(&mut self) {
        let video_dir = self.config.video.directory.clone();

        if let Ok(files) = scan_video_files(&video_dir) {
            self.video_files = files;

            // Create lookup map for fast hip number access
            self.hip_to_index.clear();
            for (index, video) in self.video_files.iter().enumerate() {
                self.hip_to_index.insert(video.hip_number.clone(), index);
            }

            if !self.video_files.is_empty() {
                self.current_index = 0;
            }
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

            let abs_path = match std::fs::canonicalize(&video_file.path) {
                Ok(path) => path,
                Err(e) => {
                    eprintln!("Failed to canonicalize path {}: {}", video_file.path, e);
                    self.current_file_name = format!("Error: {}", e);
                    return;
                }
            };
            let uri = format!("file://{}", abs_path.display());
            println!("Loading video: {}", uri);

            match VideoPlayer::new(&uri, self.texture_sender.clone()) {
                Ok(player) => {
                    if let Err(e) = player.play() {
                        eprintln!("Failed to play video: {}", e);
                        self.current_file_name = format!("Error: {}", e);
                    } else {
                        self.video_player = Some(player);
                    }
                }
                Err(e) => {
                    eprintln!("Failed to create player: {}", e);
                    self.current_file_name = format!("Error: {}", e);
                }
            }
        }
    }

    fn validate_and_switch(&mut self, input: &str) -> bool {
        if input.len() == 3 && input.chars().all(|c| c.is_ascii_digit()) {
            if let Some(&index) = self.hip_to_index.get(input) {
                self.load_video_index = Some(index);
                return true;
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
                eprintln!("Playback error detected: {}", error);
                self.next_video();
                return;
            }

            // Check for end of stream
            if player.is_eos() {
                println!("EOS detected, loading next video");
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
            } else {
                egui::CentralPanel::default().show(ctx, |ui| {
                    let bg_color = Self::hex_to_color(&self.config.splash.background_color);
                    let text_color = Self::hex_to_color(&self.config.splash.text_color);
                    ui.painter().rect_filled(ui.max_rect(), 0.0, bg_color);
                    ui.centered_and_justified(|ui| {
                        ui.label(
                            egui::RichText::new(&self.config.splash.text)
                                .size(48.0)
                                .color(text_color),
                        );
                    });
                });
                ctx.request_repaint();
                return;
            }
        }

        if self.invalid_input_timer > 0.0 {
            self.invalid_input_timer -= ctx.input(|i| i.unstable_dt) as f64;
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

            ui.allocate_ui_at_rect(video_rect, |ui| {
                ui.painter()
                    .rect_filled(ui.max_rect(), 0.0, egui::Color32::BLACK);
                if let Some(texture) = &self.current_texture {
                    ui.image((texture.id(), ui.available_size()));
                } else {
                    ui.centered_and_justified(|ui| {
                        ui.label(
                            egui::RichText::new("🎬 VIDEO DISPLAY AREA")
                                .size(48.0)
                                .color(egui::Color32::WHITE),
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
                .rect_filled(bar_rect, 0.0, egui::Color32::BLACK);

            ui.allocate_ui_at_rect(bar_rect, |ui| {
                ui.horizontal_centered(|ui| {
                    ui.with_layout(egui::Layout::left_to_right(egui::Align::Center), |ui| {
                        ui.label(
                            egui::RichText::new("3-digit hip number:").color(egui::Color32::WHITE),
                        );
                        ui.add_space(10.0);

                        let text_color = if self.invalid_input_timer > 0.0 {
                            egui::Color32::RED
                        } else {
                            egui::Color32::WHITE
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
                            egui::Color32::WHITE
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
                                    "now playing {}",
                                    self.current_file_name
                                ))
                                .color(egui::Color32::WHITE),
                            );
                        },
                    );

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.label(
                            egui::RichText::new("SUMMIT PROFESSIONAL Solutions")
                                .color(egui::Color32::WHITE),
                        );
                    });
                });
            });
        });
    }
}

fn main() -> eframe::Result<()> {
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
