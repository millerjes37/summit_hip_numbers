use std::fs;
use std::path::Path;

#[derive(Clone, Debug)]
pub struct VideoFile {
    pub path: String,
    pub name: String,
    pub hip_number: String,
}

pub fn scan_video_files(video_dir: &std::path::Path) -> Result<Vec<VideoFile>, String> {
    let path = Path::new(video_dir);

    if !path.exists() {
        return Err(format!(
            "Video directory does not exist: {}",
            video_dir.display()
        ));
    }

    let mut files = Vec::new();

    for entry in fs::read_dir(path).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path_buf = entry.path();
        if path_buf.is_file() {
            if let Some(file_name) = path_buf.file_name().and_then(|n| n.to_str()) {
                if file_name.ends_with(".png")
                    || file_name.ends_with(".jpg")
                    || file_name.ends_with(".jpeg")
                    || file_name.ends_with(".mp4")
                {
                    // Parse hip number from filename prefix
                    let hip_number: String = file_name
                        .chars()
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
    use std::fs::File;
    use tempfile::TempDir;

    #[test]
    fn test_scan_video_files_nonexistent_dir() {
        let result = scan_video_files(std::path::Path::new("/nonexistent"));
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .contains("Video directory does not exist"));
    }

    #[test]
    fn test_scan_video_files_empty_dir() {
        let temp_dir = TempDir::new().unwrap();
        let result = scan_video_files(temp_dir.path());
        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }

    #[test]
    fn test_scan_video_files_with_valid_files() {
        let temp_dir = TempDir::new().unwrap();
        let dir_path = temp_dir.path();

        // Create valid files
        File::create(dir_path.join("001.mp4")).unwrap();
        File::create(dir_path.join("002.jpg")).unwrap();
        File::create(dir_path.join("003.png")).unwrap();

        let result = scan_video_files(dir_path);
        assert!(result.is_ok());
        let files = result.unwrap();
        assert_eq!(files.len(), 3);
        assert_eq!(files[0].hip_number, "001");
        assert_eq!(files[1].hip_number, "002");
        assert_eq!(files[2].hip_number, "003");
    }

    #[test]
    fn test_scan_video_files_with_invalid_extensions() {
        let temp_dir = TempDir::new().unwrap();
        let dir_path = temp_dir.path();

        // Create files with invalid extensions
        File::create(dir_path.join("001.txt")).unwrap();
        File::create(dir_path.join("002.mp3")).unwrap();

        let result = scan_video_files(dir_path);
        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }

    #[test]
    fn test_scan_video_files_no_hip_number() {
        let temp_dir = TempDir::new().unwrap();
        let dir_path = temp_dir.path();

        // Create files without hip number prefix
        File::create(dir_path.join("video.mp4")).unwrap();
        File::create(dir_path.join("abc.jpg")).unwrap();

        let result = scan_video_files(dir_path);
        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }

    #[test]
    fn test_scan_video_files_hip_number_too_short() {
        let temp_dir = TempDir::new().unwrap();
        let dir_path = temp_dir.path();

        // Create files with 1 or 2 digit prefixes
        File::create(dir_path.join("1.mp4")).unwrap();
        File::create(dir_path.join("12.jpg")).unwrap();

        let result = scan_video_files(dir_path);
        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }

    #[test]
    fn test_scan_video_files_hip_number_too_long() {
        let temp_dir = TempDir::new().unwrap();
        let dir_path = temp_dir.path();

        // Create files with 4+ digit prefixes
        File::create(dir_path.join("1234.mp4")).unwrap();

        let result = scan_video_files(dir_path);
        assert!(result.is_ok());
        let files = result.unwrap();
        assert_eq!(files.len(), 0);
    }

    #[test]
    fn test_scan_video_files_mixed_valid_invalid() {
        let temp_dir = TempDir::new().unwrap();
        let dir_path = temp_dir.path();

        // Mix of valid and invalid
        File::create(dir_path.join("001.mp4")).unwrap();
        File::create(dir_path.join("invalid.mp4")).unwrap();
        File::create(dir_path.join("002.jpg")).unwrap();
        File::create(dir_path.join("12.png")).unwrap();
        File::create(dir_path.join("003.txt")).unwrap();

        let result = scan_video_files(dir_path);
        assert!(result.is_ok());
        let files = result.unwrap();
        assert_eq!(files.len(), 2);
        assert_eq!(files[0].hip_number, "001");
        assert_eq!(files[1].hip_number, "002");
    }

    #[test]
    fn test_scan_video_files_sorting() {
        let temp_dir = TempDir::new().unwrap();
        let dir_path = temp_dir.path();

        // Create files out of order
        File::create(dir_path.join("003.mp4")).unwrap();
        File::create(dir_path.join("001.mp4")).unwrap();
        File::create(dir_path.join("002.mp4")).unwrap();

        let result = scan_video_files(dir_path);
        assert!(result.is_ok());
        let files = result.unwrap();
        assert_eq!(files.len(), 3);
        assert_eq!(files[0].hip_number, "001");
        assert_eq!(files[1].hip_number, "002");
        assert_eq!(files[2].hip_number, "003");
    }

    #[test]
    fn test_video_file_clone() {
        let vf = VideoFile {
            path: "/path/to/file.mp4".to_string(),
            name: "file.mp4".to_string(),
            hip_number: "001".to_string(),
        };
        let cloned = vf.clone();
        assert_eq!(vf.path, cloned.path);
        assert_eq!(vf.name, cloned.name);
        assert_eq!(vf.hip_number, cloned.hip_number);
    }
}
