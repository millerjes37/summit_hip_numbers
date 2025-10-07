use std::fs;
use std::path::Path;

#[derive(Clone)]
pub struct VideoFile {
    pub path: String,
    pub name: String,
    pub hip_number: String,
}

pub fn scan_video_files(video_dir: &str) -> Result<Vec<VideoFile>, String> {
    let path = Path::new(video_dir);

    if !path.exists() {
        return Err(format!("Video directory does not exist: {}", video_dir));
    }

    let mut files = Vec::new();

    for entry in fs::read_dir(path).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path_buf = entry.path();
        if path_buf.is_file() {
            if let Some(file_name) = path_buf.file_name().and_then(|n| n.to_str()) {
                if file_name.ends_with(".png") || file_name.ends_with(".jpg") ||
                   file_name.ends_with(".jpeg") || file_name.ends_with(".mp4") {
                    // Parse hip number from filename prefix
                    let hip_number: String = file_name.chars()
                        .take_while(|c| c.is_ascii_digit())
                        .collect();
                    if hip_number.len() == 3 {
                        let video_file = VideoFile {
                            path: path_buf.to_string_lossy().to_string(),
                            name: file_name.to_string(),
                            hip_number,
                        };
                        files.push(video_file);
                    }
                }
            }
        }
    }

    // Sort files by hip number numerically
    files.sort_by(|a, b| a.hip_number.cmp(&b.hip_number));

    Ok(files)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scan_video_files() {
        let result = scan_video_files("/nonexistent");
        assert!(result.is_err());
    }
}