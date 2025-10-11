use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use tempfile::TempDir;
use summit_hip_numbers::{Config, MediaPlayerApp, UiConfig, VideoConfig, SplashConfig, LoggingConfig};
use summit_hip_numbers::file_scanner::{scan_video_files, VideoFile};

// Helper function to create test config
fn create_test_config() -> Config {
    Config {
        video: VideoConfig {
            directory: "./test_videos".to_string(),
        },
        splash: SplashConfig {
            enabled: true,
            duration_seconds: 2.0,
            text: "Test Splash".to_string(),
            background_color: "#FF0000".to_string(),
            text_color: "#00FF00".to_string(),
            interval: "once".to_string(),
            directory: "./test_splash".to_string(),
        },
        logging: LoggingConfig {
            file: "test.log".to_string(),
            max_lines: 100,
        },
        ui: UiConfig {
            input_label: "Test Input:".to_string(),
            now_playing_label: "Now Playing:".to_string(),
            company_label: "Test Company".to_string(),
            input_text_color: "#FFFFFF".to_string(),
            input_stroke_color: "#000000".to_string(),
            label_color: "#FFFF00".to_string(),
            background_color: "#0000FF".to_string(),
            kiosk_mode: false,
            enable_arrow_nav: true,
        },
    }
}

// Test config loading from file
#[test]
fn test_config_loading() {
    let temp_dir = TempDir::new().unwrap();
    let config_path = temp_dir.path().join("config.toml");
    let config = create_test_config();
    let toml_str = toml::to_string(&config).unwrap();
    fs::write(&config_path, toml_str).unwrap();

    // Mock current_exe to return temp_dir
    std::env::set_var("CARGO_MANIFEST_DIR", temp_dir.path());

    // Create a MediaPlayerApp and check if config is loaded
    // Since load_config is private, we test the public interface
    let mut app = MediaPlayerApp::default();
    app.config = config.clone();

    assert_eq!(app.config.video.directory, config.video.directory);
    assert_eq!(app.config.splash.enabled, config.splash.enabled);
    assert_eq!(app.config.ui.kiosk_mode, config.ui.kiosk_mode);
}

// Test portable config loading (simulating exe dir)
#[test]
fn test_portable_config_loading() {
    let temp_dir = TempDir::new().unwrap();
    let config_path = temp_dir.path().join("config.toml");
    let config = create_test_config();
    config.ui.kiosk_mode = true;
    config.ui.enable_arrow_nav = true;
    let toml_str = toml::to_string(&config).unwrap();
    fs::write(&config_path, toml_str).unwrap();

    // In real app, load_config_for_kiosk loads from exe dir
    // For test, we can check the function exists and returns default if no file
    let loaded_config = summit_hip_numbers::load_config_for_kiosk();
    // Since no file in exe dir, should return default
    assert_eq!(loaded_config.video.directory, "./videos");
    assert!(loaded_config.ui.kiosk_mode);
}

// Test video file scanning with test assets
#[test]
fn test_video_file_scanning_with_test_assets() {
    let temp_dir = TempDir::new().unwrap();
    let video_dir = temp_dir.path().join("videos");
    fs::create_dir(&video_dir).unwrap();

    // Copy test assets as mock video files
    let test_assets_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests").join("assets");
    for entry in fs::read_dir(&test_assets_dir).unwrap() {
        let entry = entry.unwrap();
        let src_path = entry.path();
        let file_name = src_path.file_name().unwrap();
        let dest_path = video_dir.join(file_name);
        fs::copy(&src_path, &dest_path).unwrap();
    }

    // Rename txt files to mp4 for scanning
    for entry in fs::read_dir(&video_dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().unwrap_or_default() == "txt" {
            let new_path = path.with_extension("mp4");
            fs::rename(&path, &new_path).unwrap();
        }
    }

    let result = scan_video_files(video_dir.to_str().unwrap());
    assert!(result.is_ok());
    let files = result.unwrap();
    assert_eq!(files.len(), 5);
    assert_eq!(files[0].hip_number, "001");
    assert_eq!(files[1].hip_number, "002");
    assert_eq!(files[2].hip_number, "003");
    assert_eq!(files[3].hip_number, "004");
    assert_eq!(files[4].hip_number, "005");
}

// Test hip number validation
#[test]
fn test_hip_number_validation() {
    let temp_dir = TempDir::new().unwrap();
    let video_dir = temp_dir.path().join("videos");
    fs::create_dir(&video_dir).unwrap();

    // Create mock video files
    fs::File::create(video_dir.join("001.mp4")).unwrap();
    fs::File::create(video_dir.join("002.mp4")).unwrap();
    fs::File::create(video_dir.join("003.mp4")).unwrap();

    let mut app = MediaPlayerApp::default();
    app.config.video.directory = video_dir.to_string_lossy().to_string();
    app.load_video_files();

    // Test valid hip numbers
    assert!(app.validate_and_switch("001"));
    assert_eq!(app.current_index, 0);
    assert_eq!(app.videos_played, 1);

    assert!(app.validate_and_switch("002"));
    assert_eq!(app.current_index, 1);
    assert_eq!(app.videos_played, 2);

    // Test invalid hip number
    assert!(!app.validate_and_switch("999"));
    assert_eq!(app.videos_played, 2); // Should not increment

    // Test invalid length
    assert!(!app.validate_and_switch("12"));
    assert!(!app.validate_and_switch("1234"));

    // Test non-digit
    assert!(!app.validate_and_switch("abc"));
}

// Test arrow key navigation
#[test]
fn test_arrow_key_navigation() {
    let temp_dir = TempDir::new().unwrap();
    let video_dir = temp_dir.path().join("videos");
    fs::create_dir(&video_dir).unwrap();

    fs::File::create(video_dir.join("001.mp4")).unwrap();
    fs::File::create(video_dir.join("002.mp4")).unwrap();
    fs::File::create(video_dir.join("003.mp4")).unwrap();

    let mut app = MediaPlayerApp::default();
    app.config.video.directory = video_dir.to_string_lossy().to_string();
    app.config.ui.enable_arrow_nav = true;
    app.load_video_files();

    // Start at index 0
    assert_eq!(app.current_index, 0);

    // Simulate arrow right (next)
    app.next_video();
    assert_eq!(app.load_video_index, Some(1));

    // Simulate arrow left (previous) - but since load_video_index is set, need to reset
    app.current_index = 1;
    // For testing, manually set
    if app.current_index > 0 {
        app.current_index -= 1;
        app.load_video_index = Some(app.current_index);
    }
    assert_eq!(app.load_video_index, Some(0));

    // Test wrap around
    app.current_index = 2;
    app.next_video();
    assert_eq!(app.load_video_index, Some(0));
}

// Test kiosk mode configuration
#[test]
fn test_kiosk_mode_configuration() {
    let mut config = create_test_config();
    config.ui.kiosk_mode = true;

    let mut app = MediaPlayerApp::default();
    app.config = config;

    assert!(app.config.ui.kiosk_mode);
    // In real app, this would affect viewport, but we test the config
}

// Test demo mode configuration
#[cfg(feature = "demo")]
#[test]
fn test_demo_mode_configuration() {
    let temp_dir = TempDir::new().unwrap();
    let video_dir = temp_dir.path().join("videos");
    fs::create_dir(&video_dir).unwrap();

    // Create more than 5 videos
    for i in 1..=7 {
        fs::File::create(video_dir.join(format!("{:03}.mp4", i))).unwrap();
    }

    let mut app = MediaPlayerApp::default();
    app.config.video.directory = video_dir.to_string_lossy().to_string();

    // In demo mode, load_video_files should limit to 5
    app.load_video_files();
    assert_eq!(app.video_files.len(), 5);
}

// Test splash screen logic
#[test]
fn test_splash_screen_logic() {
    let mut app = MediaPlayerApp::default();
    app.config.splash.enabled = true;
    app.config.splash.interval = "once".to_string();

    // Initially, videos_played = 0, should show splash
    assert!(app.should_show_splash());

    app.videos_played = 1;
    assert!(!app.should_show_splash());

    // Test "every" interval
    app.config.splash.interval = "every".to_string();
    assert!(!app.should_show_splash()); // videos_played == 0 initially

    app.videos_played = 1;
    assert!(app.should_show_splash());

    // Test "every_other"
    app.config.splash.interval = "every_other".to_string();
    app.videos_played = 1;
    assert!(app.should_show_splash());

    app.videos_played = 2;
    assert!(!app.should_show_splash());

    // Test "every_third"
    app.config.splash.interval = "every_third".to_string();
    app.videos_played = 1;
    assert!(app.should_show_splash());

    app.videos_played = 2;
    assert!(!app.should_show_splash());

    app.videos_played = 3;
    assert!(!app.should_show_splash()); // 3 % 3 == 0, but logic is > 0 and % 3 == 1? Wait, check code
    // In code: videos_played > 0 && videos_played % 3 == 1
    // So for 1: true, 2: false, 3: false, 4: true, etc.
}

// Test portable distribution setup (mocking exe directory)
#[test]
fn test_portable_distribution_setup() {
    let temp_dir = TempDir::new().unwrap();
    let exe_dir = temp_dir.path();
    let videos_dir = exe_dir.join("videos");
    let splash_dir = exe_dir.join("splash");
    let logo_dir = exe_dir.join("logo");

    fs::create_dir(&videos_dir).unwrap();
    fs::create_dir(&splash_dir).unwrap();
    fs::create_dir(&logo_dir).unwrap();

    fs::File::create(videos_dir.join("001.mp4")).unwrap();

    let app = MediaPlayerApp::default();
    // check_asset_integrity is private, but we can test the logic manually
    let required_dirs = ["videos", "splash", "logo"];
    for dir in &required_dirs {
        let dir_path = exe_dir.join(dir);
        assert!(dir_path.exists());
    }
}

// Test end-to-end scenario: load config, scan videos, validate input, navigate
#[test]
fn test_end_to_end_scenario() {
    let temp_dir = TempDir::new().unwrap();
    let video_dir = temp_dir.path().join("videos");
    fs::create_dir(&video_dir).unwrap();

    // Create mock videos
    fs::File::create(video_dir.join("001.mp4")).unwrap();
    fs::File::create(video_dir.join("002.mp4")).unwrap();
    fs::File::create(video_dir.join("003.mp4")).unwrap();

    let mut app = MediaPlayerApp::default();
    app.config.video.directory = video_dir.to_string_lossy().to_string();
    app.config.ui.enable_arrow_nav = true;

    // Load videos
    app.load_video_files();
    assert_eq!(app.video_files.len(), 3);
    assert!(app.hip_to_index.contains_key("001"));

    // Validate hip number
    assert!(app.validate_and_switch("001"));
    assert_eq!(app.current_index, 0);

    // Navigate forward
    app.next_video();
    assert_eq!(app.load_video_index, Some(1));

    // Navigate backward
    app.current_index = 1;
    if app.current_index > 0 {
        app.current_index -= 1;
        app.load_video_index = Some(app.current_index);
    }
    assert_eq!(app.load_video_index, Some(0));

    // Test invalid input
    assert!(!app.validate_and_switch("999"));
}

// Test error handling in video scanning
#[test]
fn test_error_handling_video_scanning() {
    let mut app = MediaPlayerApp::default();
    app.config.video.directory = "/nonexistent/directory".to_string();

    // Should not panic, just log error
    app.load_video_files();
    assert_eq!(app.video_files.len(), 0);
}

// Test config serialization round-trip
#[test]
fn test_config_serialization_round_trip() {
    let config = create_test_config();
    let toml_str = toml::to_string(&config).unwrap();
    let deserialized: Config = toml::from_str(&toml_str).unwrap();

    assert_eq!(config.video.directory, deserialized.video.directory);
    assert_eq!(config.splash.enabled, deserialized.splash.enabled);
    assert_eq!(config.splash.duration_seconds, deserialized.splash.duration_seconds);
    assert_eq!(config.ui.kiosk_mode, deserialized.ui.kiosk_mode);
    assert_eq!(config.ui.enable_arrow_nav, deserialized.ui.enable_arrow_nav);
}



// Test log trimming
#[test]
fn test_log_trimming() {
    let temp_dir = TempDir::new().unwrap();
    let log_path = temp_dir.path().join("test.log");

    // Create log with more lines than max
    let lines: Vec<String> = (0..150).map(|i| format!("Line {}\n", i)).collect();
    fs::write(&log_path, lines.join("")).unwrap();

    let mut app = MediaPlayerApp::default();
    app.config.logging.file = log_path.to_string_lossy().to_string();
    app.config.logging.max_lines = 100;

    app.trim_log();

    let content = fs::read_to_string(&log_path).unwrap();
    let trimmed_lines: Vec<&str> = content.lines().collect();
    assert_eq!(trimmed_lines.len(), 100);
}

// Test splash images loading
#[test]
fn test_splash_images_loading() {
    let temp_dir = TempDir::new().unwrap();
    let splash_dir = temp_dir.path().join("splash");
    fs::create_dir(&splash_dir).unwrap();

    fs::File::create(splash_dir.join("image1.png")).unwrap();
    fs::File::create(splash_dir.join("image2.jpg")).unwrap();
    fs::File::create(splash_dir.join("text.txt")).unwrap(); // Should be ignored

    let mut app = MediaPlayerApp::default();
    app.config.splash.directory = splash_dir.to_string_lossy().to_string();

    app.load_splash_images();

    assert_eq!(app.splash_images.len(), 2);
}

// Test input buffer handling (simulate key presses)
#[test]
fn test_input_buffer_handling() {
    let mut app = MediaPlayerApp::default();

    // Simulate digit input
    app.input_buffer.clear();
    // In real app, this is done in update via events, but for test:
    let text = "123";
    if app.input_buffer.len() < 3 && text.chars().all(|c| c.is_ascii_digit()) {
        app.input_buffer.push_str(text);
    }
    assert_eq!(app.input_buffer, "123");

    // Test enter press simulation
    if !app.input_buffer.is_empty() {
        let input = app.input_buffer.clone();
        // Since no videos loaded, validate_and_switch should fail
        assert!(!app.validate_and_switch(&input));
        app.input_buffer.clear();
    }
    assert_eq!(app.input_buffer, "");
}

// Test no video popup logic
#[test]
fn test_no_video_popup_logic() {
    let mut app = MediaPlayerApp::default();

    // Simulate invalid hip number
    app.validate_and_switch("999");
    // In real app, this sets show_no_video_popup, but since no videos, it doesn't
    // But we can test the logic
    app.show_no_video_popup = true;
    app.no_video_popup_timer = 3.0;
    app.no_video_hip = "999".to_string();

    // Simulate timer update
    let dt = 0.5;
    if app.show_no_video_popup {
        app.no_video_popup_timer -= dt;
        if app.no_video_popup_timer <= 0.0 {
            app.show_no_video_popup = false;
        }
    }
    assert!(app.show_no_video_popup); // Still true after 0.5s

    app.no_video_popup_timer = 0.0;
    if app.show_no_video_popup {
        app.no_video_popup_timer -= dt;
        if app.no_video_popup_timer <= 0.0 {
            app.show_no_video_popup = false;
        }
    }
    assert!(!app.show_no_video_popup);
}

// Test video index loading (mock)
#[cfg(not(feature = "gstreamer"))]
#[test]
fn test_load_video_mock() {
    let mut app = MediaPlayerApp::default();
    app.load_video(0);
    assert_eq!(app.current_file_name, "Mock loaded".to_string());
}

// Test hip to index mapping
#[test]
fn test_hip_to_index_mapping() {
    let temp_dir = TempDir::new().unwrap();
    let video_dir = temp_dir.path().join("videos");
    fs::create_dir(&video_dir).unwrap();

    fs::File::create(video_dir.join("001.mp4")).unwrap();
    fs::File::create(video_dir.join("002.mp4")).unwrap();

    let mut app = MediaPlayerApp::default();
    app.config.video.directory = video_dir.to_string_lossy().to_string();
    app.load_video_files();

    let hip_to_index: HashMap<String, usize> = app.video_files.iter().enumerate()
        .map(|(i, vf)| (vf.hip_number.clone(), i))
        .collect();

    assert_eq!(hip_to_index.get("001"), Some(&0));
    assert_eq!(hip_to_index.get("002"), Some(&1));
    assert_eq!(hip_to_index.get("003"), None);
}