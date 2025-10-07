use anyhow::{anyhow, Result};
use eframe::epaint::ColorImage;
use gstreamer::prelude::*;
use gstreamer::{Bin, Element, ElementFactory, MessageView, State};
use gstreamer_app::AppSink;
use gstreamer_video::{VideoFrame, VideoInfo};
use std::sync::{Arc, Mutex};
use tokio::sync::watch;

pub struct VideoPlayer {
    pipeline: Element,
    appsink: AppSink,
    eos: Arc<Mutex<bool>>,
    error: Arc<Mutex<Option<String>>>,
}

impl VideoPlayer {
    pub fn new(uri: &str, texture_sender: watch::Sender<Option<ColorImage>>) -> Result<Self> {
        println!("Creating custom pipeline for URI: {}", uri);

        // Create pipeline
        let pipeline = ElementFactory::make("playbin")
            .name("playbin")
            .build()
            .map_err(|e| anyhow!("Failed to create playbin: {:?}", e))?;

        // Set the URI
        pipeline.set_property("uri", uri);

        // Create video processing bin
        let video_bin = Bin::new();

        // Create videoconvert to convert to RGBA
        let videoconvert = ElementFactory::make("videoconvert")
            .build()
            .map_err(|e| anyhow!("Failed to create videoconvert: {:?}", e))?;

        // Create videoscale if needed
        let videoscale = ElementFactory::make("videoscale")
            .build()
            .map_err(|e| anyhow!("Failed to create videoscale: {:?}", e))?;

        // Create capsfilter to force RGBA
        let capsfilter = ElementFactory::make("capsfilter")
            .build()
            .map_err(|e| anyhow!("Failed to create capsfilter: {:?}", e))?;
        capsfilter.set_property("caps", &gstreamer::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .build());

        // Create appsink for video
        let appsink = gstreamer_app::AppSink::builder().build();
        appsink.set_max_buffers(1);
        appsink.set_drop(true);

        // Add elements to bin
        video_bin.add(&videoconvert).map_err(|e| anyhow!("Failed to add videoconvert: {:?}", e))?;
        video_bin.add(&videoscale).map_err(|e| anyhow!("Failed to add videoscale: {:?}", e))?;
        video_bin.add(&capsfilter).map_err(|e| anyhow!("Failed to add capsfilter: {:?}", e))?;
        video_bin.add(&appsink.clone().upcast::<Element>()).map_err(|e| anyhow!("Failed to add appsink: {:?}", e))?;

        // Link elements
        videoconvert.link(&videoscale).map_err(|e| anyhow!("Failed to link videoconvert to videoscale: {:?}", e))?;
        videoscale.link(&capsfilter).map_err(|e| anyhow!("Failed to link videoscale to capsfilter: {:?}", e))?;
        capsfilter.link(&appsink.clone().upcast::<Element>()).map_err(|e| anyhow!("Failed to link capsfilter to appsink: {:?}", e))?;

        // Set ghost pad
        let pad = videoconvert.static_pad("sink").ok_or_else(|| anyhow!("Failed to get sink pad"))?;
        video_bin.add_pad(&gstreamer::GhostPad::with_target(&pad).map_err(|e| anyhow!("Failed to add ghost pad: {:?}", e))?).map_err(|e| anyhow!("Failed to add ghost pad: {:?}", e))?;

        // Set video sink
        pipeline.set_property("video-sink", &video_bin);

        // Create audio sink (autoaudiosink for system default)
        let audiosink = ElementFactory::make("autoaudiosink")
            .build()
            .map_err(|e| anyhow!("Failed to create audio sink: {:?}", e))?;
        pipeline.set_property("audio-sink", &audiosink);

        let eos = Arc::new(Mutex::new(false));
        let error = Arc::new(Mutex::new(None));

        let player = VideoPlayer {
            pipeline: pipeline.clone(),
            appsink: appsink.clone(),
            eos: eos.clone(),
            error: error.clone(),
        };

        // Start bus watching
        player.start_bus_watching(eos.clone(), error.clone());

        // Start frame extraction
        player.start_frame_extraction(appsink, texture_sender);

        Ok(player)
    }

    fn start_bus_watching(&self, eos: Arc<Mutex<bool>>, error: Arc<Mutex<Option<String>>>) {
        let bus = self.pipeline.bus().expect("Pipeline should have a bus");

        std::thread::spawn(move || {
            for msg in bus.iter_timed(gstreamer::ClockTime::NONE) {
                match msg.view() {
                    MessageView::Eos(_) => {
                        println!("End of stream reached");
                        *eos.lock().unwrap() = true;
                    }
                    MessageView::Error(err) => {
                        let error_msg = format!(
                            "Error from {:?}: {} ({:?})",
                            err.src().map(|s| s.path_string()),
                            err.error(),
                            err.debug()
                        );
                        eprintln!("GStreamer Error: {}", error_msg);
                        *error.lock().unwrap() = Some(error_msg);
                        *eos.lock().unwrap() = true; // Treat errors as EOS
                    }
                    MessageView::Warning(warn) => {
                        eprintln!(
                            "Warning from {:?}: {} ({:?})",
                            warn.src().map(|s| s.path_string()),
                            warn.error(),
                            warn.debug()
                        );
                    }
                    MessageView::StateChanged(state_changed) => {
                        if let Some(element) = msg.src() {
                            if element.type_().name() == "GstPipeline" {
                                println!(
                                    "Pipeline state changed from {:?} to {:?}",
                                    state_changed.old(),
                                    state_changed.current()
                                );
                            }
                        }
                    }
                    MessageView::AsyncDone(_) => {
                        println!("Pipeline is prerolled and ready to play");
                    }
                    _ => {}
                }
            }
        });
    }

    fn start_frame_extraction(
        &self,
        appsink: AppSink,
        sender: watch::Sender<Option<ColorImage>>,
    ) {
        appsink.set_callbacks(
            gstreamer_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink| {
                    match Self::pull_frame(appsink) {
                        Some(frame) => {
                            if let Err(e) = sender.send(Some(frame)) {
                                eprintln!("Failed to send frame: {}", e);
                            }
                        }
                        None => {
                            eprintln!("Failed to pull frame");
                        }
                    }
                    Ok(gstreamer::FlowSuccess::Ok)
                })
                .build(),
        );
    }

    fn pull_frame(appsink: &AppSink) -> Option<ColorImage> {
        let sample = appsink.pull_sample().ok()?;
        let buffer = sample.buffer()?;
        let caps = sample.caps()?;
        let video_info = VideoInfo::from_caps(caps).ok()?;

        // Create a readable video frame
        let frame = VideoFrame::from_buffer_readable(buffer.copy(), &video_info).ok()?;

        let width = video_info.width() as usize;
        let height = video_info.height() as usize;

        // Get the frame data
        let plane_data = frame.plane_data(0).ok()?;

        Some(ColorImage::from_rgba_unmultiplied(
            [width, height],
            plane_data,
        ))
    }

    pub fn play(&self) -> Result<()> {
        println!("Setting pipeline to PLAYING state");
        self.pipeline
            .set_state(State::Playing)
            .map_err(|e| anyhow!("Failed to set pipeline to PLAYING: {:?}", e))?;
        Ok(())
    }

    pub fn pause(&self) -> Result<()> {
        println!("Setting pipeline to PAUSED state");
        self.pipeline
            .set_state(State::Paused)
            .map_err(|e| anyhow!("Failed to set pipeline to PAUSED: {:?}", e))?;
        Ok(())
    }

    pub fn stop(&self) -> Result<()> {
        println!("Stopping pipeline");

        // First pause
        let _ = self.pipeline.set_state(State::Paused);

        // Then set to NULL
        self.pipeline
            .set_state(State::Null)
            .map_err(|e| anyhow!("Failed to set pipeline to NULL: {:?}", e))?;

        Ok(())
    }

    pub fn is_eos(&self) -> bool {
        *self.eos.lock().unwrap()
    }

    pub fn reset_eos(&self) {
        *self.eos.lock().unwrap() = false;
    }

    pub fn get_error(&self) -> Option<String> {
        self.error.lock().unwrap().clone()
    }

    pub fn seek_to_start(&self) -> Result<()> {
        println!("Seeking to start");
        self.pipeline
            .seek_simple(
                gstreamer::SeekFlags::FLUSH | gstreamer::SeekFlags::KEY_UNIT,
                gstreamer::ClockTime::ZERO,
            )
            .map_err(|e| anyhow!("Failed to seek: {:?}", e))?;
        self.reset_eos();
        Ok(())
    }
}

impl Drop for VideoPlayer {
    fn drop(&mut self) {
        println!("Dropping VideoPlayer, cleaning up pipeline");
        // Ensure pipeline is stopped before drop
        let _ = self.stop();
    }
}