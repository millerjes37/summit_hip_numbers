use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::Stream;
use eframe::epaint::ColorImage;
use ffmpeg_next as ffmpeg;
use std::path::Path;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc::{channel, Receiver, Sender},
    Arc, Mutex,
};
use std::thread;
use std::time::{Duration, Instant};
use tokio::sync::watch;

pub struct VideoPlayer {
    eos: Arc<AtomicBool>,
    error: Arc<Mutex<Option<String>>>,
    video_path: String,
    texture_sender: watch::Sender<Option<ColorImage>>,
    _video_thread: Option<thread::JoinHandle<()>>,
    _audio_thread: Option<thread::JoinHandle<()>>,
    _audio_stream: Option<Stream>,
}

impl VideoPlayer {
    pub fn new(uri: &str, texture_sender: watch::Sender<Option<ColorImage>>) -> Result<Self> {
        ffmpeg::init().map_err(|e| anyhow!("Failed to initialize FFmpeg: {}", e))?;

        let video_path = if uri.starts_with("file://") {
            uri.trim_start_matches("file://").to_string()
        } else {
            uri.to_string()
        };

        if !Path::new(&video_path).exists() {
            return Err(anyhow!("Video file not found: {}", video_path));
        }

        log::info!("Creating FFmpeg player for: {}", video_path);

        let eos = Arc::new(AtomicBool::new(false));
        let error = Arc::new(Mutex::new(None));

        let player = VideoPlayer {
            eos,
            error,
            video_path,
            texture_sender,
            _video_thread: None,
            _audio_thread: None,
            _audio_stream: None,
        };

        Ok(player)
    }

    pub fn play(&mut self) -> Result<()> {
        log::info!("Starting FFmpeg playback");

        let video_path = self.video_path.clone();
        let eos = self.eos.clone();
        let error = self.error.clone();
        let texture_sender = self.texture_sender.clone();

        let ictx = ffmpeg::format::input(&video_path)?;

        let video_stream = ictx
            .streams()
            .best(ffmpeg::media::Type::Video)
            .ok_or_else(|| anyhow!("No video stream found"))?;
        let video_stream_index = video_stream.index();

        let audio_stream_opt = ictx.streams().best(ffmpeg::media::Type::Audio);
        let audio_stream_index = audio_stream_opt.as_ref().map(|s| s.index());

        let (audio_tx, audio_rx): (Sender<Vec<f32>>, Receiver<Vec<f32>>) = channel();
        let audio_stream = if let Some(_stream) = audio_stream_opt {
            log::info!("Audio stream found, initializing audio output");
            match Self::setup_audio_output(audio_rx) {
                Ok(stream) => Some(stream),
                Err(e) => {
                    log::warn!(
                        "Failed to setup audio output: {}, continuing without audio",
                        e
                    );
                    None
                }
            }
        } else {
            log::info!("No audio stream found in video");
            None
        };

        let video_path_clone = video_path.clone();
        let eos_clone = eos.clone();
        let error_clone = error.clone();

        let video_handle = thread::spawn(move || {
            if let Err(e) = Self::video_playback_loop(
                &video_path_clone,
                video_stream_index,
                texture_sender,
                eos_clone.clone(),
                error_clone.clone(),
            ) {
                log::error!("Video playback error: {}", e);
                *error_clone.lock().unwrap() = Some(e.to_string());
                eos_clone.store(true, Ordering::SeqCst);
            } else {
                log::info!("Video playback completed normally");
                eos_clone.store(true, Ordering::SeqCst);
            }
        });

        let audio_handle = if let Some(audio_idx) = audio_stream_index {
            let video_path_clone = video_path.clone();
            let eos_clone = eos.clone();
            let error_clone = error.clone();

            Some(thread::spawn(move || {
                if let Err(e) = Self::audio_playback_loop(
                    &video_path_clone,
                    audio_idx,
                    audio_tx,
                    eos_clone.clone(),
                    error_clone.clone(),
                ) {
                    log::error!("Audio playback error: {}", e);
                }
            }))
        } else {
            None
        };

        self._video_thread = Some(video_handle);
        self._audio_thread = audio_handle;
        self._audio_stream = audio_stream;

        Ok(())
    }

    fn setup_audio_output(audio_rx: Receiver<Vec<f32>>) -> Result<Stream> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow!("No audio output device found"))?;

        let config = device.default_output_config()?;
        log::info!("Audio output config: {:?}", config);

        let audio_buffer = Arc::new(Mutex::new(Vec::<f32>::new()));
        let audio_buffer_clone = audio_buffer.clone();

        thread::spawn(move || {
            while let Ok(samples) = audio_rx.recv() {
                let mut buffer = audio_buffer_clone.lock().unwrap();
                buffer.extend_from_slice(&samples);
            }
        });

        let stream = device.build_output_stream(
            &config.into(),
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                let mut buffer = audio_buffer.lock().unwrap();
                let len = data.len().min(buffer.len());
                if len > 0 {
                    data[..len].copy_from_slice(&buffer[..len]);
                    buffer.drain(..len);
                    if len < data.len() {
                        data[len..].fill(0.0);
                    }
                } else {
                    data.fill(0.0);
                }
            },
            |err| eprintln!("Audio stream error: {}", err),
            None,
        )?;

        stream.play()?;
        log::info!("Audio stream started");
        Ok(stream)
    }

    fn video_playback_loop(
        video_path: &str,
        video_stream_index: usize,
        texture_sender: watch::Sender<Option<ColorImage>>,
        eos: Arc<AtomicBool>,
        error: Arc<Mutex<Option<String>>>,
    ) -> Result<()> {
        let mut ictx = ffmpeg::format::input(video_path)?;
        let video_stream = ictx.streams().nth(video_stream_index).unwrap();

        let context_decoder =
            ffmpeg::codec::context::Context::from_parameters(video_stream.parameters())?;
        let mut decoder = context_decoder.decoder().video()?;

        let mut scaler = ffmpeg::software::scaling::context::Context::get(
            decoder.format(),
            decoder.width(),
            decoder.height(),
            ffmpeg::format::Pixel::RGBA,
            decoder.width(),
            decoder.height(),
            ffmpeg::software::scaling::flag::Flags::BILINEAR,
        )?;

        let frame_rate = video_stream.avg_frame_rate();
        let frame_duration = if frame_rate.numerator() > 0 {
            Duration::from_secs_f64(frame_rate.denominator() as f64 / frame_rate.numerator() as f64)
        } else {
            Duration::from_millis(33)
        };

        let start_time = Instant::now();
        let mut frame_count = 0u64;

        for (stream, packet) in ictx.packets() {
            if eos.load(Ordering::SeqCst) {
                log::info!("Video playback stopped by user");
                return Ok(());
            }

            if stream.index() == video_stream_index {
                if let Err(e) = decoder.send_packet(&packet) {
                    *error.lock().unwrap() = Some(format!("Failed to send packet: {}", e));
                    return Err(anyhow!("Failed to send packet: {}", e));
                }

                let mut decoded = ffmpeg::util::frame::video::Video::empty();
                while decoder.receive_frame(&mut decoded).is_ok() {
                    if eos.load(Ordering::SeqCst) {
                        log::info!("Video playback stopped during frame decode");
                        return Ok(());
                    }

                    let mut rgb_frame = ffmpeg::util::frame::video::Video::empty();
                    scaler.run(&decoded, &mut rgb_frame)?;

                    let width = rgb_frame.width() as usize;
                    let height = rgb_frame.height() as usize;
                    let data = rgb_frame.data(0);

                    let color_image = ColorImage::from_rgba_unmultiplied([width, height], data);

                    if texture_sender.send(Some(color_image)).is_err() {
                        log::warn!("Failed to send frame to texture channel");
                        return Ok(());
                    }

                    frame_count += 1;
                    let expected_time = start_time + frame_duration * frame_count as u32;
                    let now = Instant::now();
                    if expected_time > now {
                        thread::sleep(expected_time - now);
                    }
                }
            }
        }

        if !eos.load(Ordering::SeqCst) {
            decoder.send_eof().ok();
            let mut decoded = ffmpeg::util::frame::video::Video::empty();
            while decoder.receive_frame(&mut decoded).is_ok() {
                if eos.load(Ordering::SeqCst) {
                    break;
                }

                let mut rgb_frame = ffmpeg::util::frame::video::Video::empty();
                scaler.run(&decoded, &mut rgb_frame).ok();

                let width = rgb_frame.width() as usize;
                let height = rgb_frame.height() as usize;
                let data = rgb_frame.data(0);

                let color_image = ColorImage::from_rgba_unmultiplied([width, height], data);
                texture_sender.send(Some(color_image)).ok();

                frame_count += 1;
                let expected_time = start_time + frame_duration * frame_count as u32;
                let now = Instant::now();
                if expected_time > now {
                    thread::sleep(expected_time - now);
                }
            }
        }

        Ok(())
    }

    fn audio_playback_loop(
        video_path: &str,
        audio_stream_index: usize,
        audio_tx: Sender<Vec<f32>>,
        eos: Arc<AtomicBool>,
        _error: Arc<Mutex<Option<String>>>,
    ) -> Result<()> {
        let mut ictx = ffmpeg::format::input(video_path)?;
        let audio_stream = ictx.streams().nth(audio_stream_index).unwrap();

        let context_decoder =
            ffmpeg::codec::context::Context::from_parameters(audio_stream.parameters())?;
        let mut decoder = context_decoder.decoder().audio()?;

        for (stream, packet) in ictx.packets() {
            if eos.load(Ordering::SeqCst) {
                log::info!("Audio playback stopped by user");
                return Ok(());
            }

            if stream.index() == audio_stream_index {
                decoder.send_packet(&packet)?;

                let mut decoded = ffmpeg::util::frame::audio::Audio::empty();
                while decoder.receive_frame(&mut decoded).is_ok() {
                    if eos.load(Ordering::SeqCst) {
                        return Ok(());
                    }

                    let samples = Self::convert_audio_frame(&decoded)?;
                    if audio_tx.send(samples).is_err() {
                        return Ok(());
                    }
                }
            }
        }

        decoder.send_eof().ok();
        let mut decoded = ffmpeg::util::frame::audio::Audio::empty();
        while decoder.receive_frame(&mut decoded).is_ok() {
            if eos.load(Ordering::SeqCst) {
                break;
            }
            let samples = Self::convert_audio_frame(&decoded)?;
            audio_tx.send(samples).ok();
        }

        Ok(())
    }

    fn convert_audio_frame(frame: &ffmpeg::util::frame::audio::Audio) -> Result<Vec<f32>> {
        let format = frame.format();
        let channels = frame.channels() as usize;
        let samples = frame.samples();

        let mut output = Vec::new();

        match format {
            ffmpeg::format::Sample::F32(sample_type) => {
                let data = frame.data(0);
                let float_data = unsafe {
                    std::slice::from_raw_parts(data.as_ptr() as *const f32, samples * channels)
                };

                if sample_type == ffmpeg::format::sample::Type::Packed {
                    output.extend_from_slice(float_data);
                } else {
                    for i in 0..samples {
                        for ch in 0..channels {
                            let ch_data = frame.data(ch);
                            let ch_float = unsafe {
                                std::slice::from_raw_parts(ch_data.as_ptr() as *const f32, samples)
                            };
                            output.push(ch_float[i]);
                        }
                    }
                }
            }
            ffmpeg::format::Sample::I16(sample_type) => {
                let data = frame.data(0);
                let i16_data = unsafe {
                    std::slice::from_raw_parts(data.as_ptr() as *const i16, samples * channels)
                };

                if sample_type == ffmpeg::format::sample::Type::Packed {
                    for &sample in i16_data {
                        output.push(sample as f32 / 32768.0);
                    }
                } else {
                    for i in 0..samples {
                        for ch in 0..channels {
                            let ch_data = frame.data(ch);
                            let ch_i16 = unsafe {
                                std::slice::from_raw_parts(ch_data.as_ptr() as *const i16, samples)
                            };
                            output.push(ch_i16[i] as f32 / 32768.0);
                        }
                    }
                }
            }
            _ => {
                return Err(anyhow!("Unsupported audio format: {:?}", format));
            }
        }

        Ok(output)
    }

    pub fn stop(&self) -> Result<()> {
        log::info!("Stopping FFmpeg player");
        self.eos.store(true, Ordering::SeqCst);
        Ok(())
    }

    pub fn is_eos(&self) -> bool {
        self.eos.load(Ordering::SeqCst)
    }

    pub fn get_error(&self) -> Option<String> {
        self.error.lock().unwrap().clone()
    }
}

impl Drop for VideoPlayer {
    fn drop(&mut self) {
        log::info!("Dropping VideoPlayer");
        self.eos.store(true, Ordering::SeqCst);
    }
}
