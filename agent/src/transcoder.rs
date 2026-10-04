//! PCOS Agent Transcoder Module
//!
//! Integrates with system FFmpeg / ffprobe to provide media metadata extraction,
//! poster thumbnail extraction, faststart MP4 transcoding, and HLS packaging.

use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::process::Command;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MediaProbeResult {
    pub duration_secs: f64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub video_codec: Option<String>,
    pub audio_codec: Option<String>,
    pub bitrate_kbps: Option<u64>,
    pub format_name: String,
}

pub struct Transcoder;

impl Transcoder {
    /// Probe media file metadata using `ffprobe`.
    pub async fn probe(file_path: &Path) -> Result<MediaProbeResult, String> {
        if !file_path.exists() {
            return Err(format!("File does not exist: {}", file_path.display()));
        }

        let output = Command::new("ffprobe")
            .arg("-v")
            .arg("quiet")
            .arg("-print_format")
            .arg("json")
            .arg("-show_format")
            .arg("-show_streams")
            .arg(file_path)
            .output()
            .await
            .map_err(|e| format!("Failed to execute ffprobe: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("ffprobe exited with error: {}", stderr));
        }

        let json: serde_json::Value = serde_json::from_slice(&output.stdout)
            .map_err(|e| format!("Failed to parse ffprobe JSON output: {}", e))?;

        let format = &json["format"];
        let duration_secs = format["duration"]
            .as_str()
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.0);
        let bitrate_kbps = format["bit_rate"]
            .as_str()
            .and_then(|s| s.parse::<u64>().ok())
            .map(|b| b / 1000);
        let format_name = format["format_name"]
            .as_str()
            .unwrap_or("unknown")
            .to_string();

        let mut video_codec = None;
        let mut audio_codec = None;
        let mut width = None;
        let mut height = None;

        if let Some(streams) = json["streams"].as_array() {
            for s in streams {
                let codec_type = s["codec_type"].as_str().unwrap_or("");
                if codec_type == "video" && video_codec.is_none() {
                    video_codec = s["codec_name"].as_str().map(|c| c.to_string());
                    width = s["width"].as_u64().map(|w| w as u32);
                    height = s["height"].as_u64().map(|h| h as u32);
                } else if codec_type == "audio" && audio_codec.is_none() {
                    audio_codec = s["codec_name"].as_str().map(|c| c.to_string());
                }
            }
        }

        Ok(MediaProbeResult {
            duration_secs,
            width,
            height,
            video_codec,
            audio_codec,
            bitrate_kbps,
            format_name,
        })
    }

    /// Extract a poster frame / thumbnail as JPEG using `ffmpeg`.
    pub async fn generate_thumbnail(
        input_file: &Path,
        output_image: &Path,
        time_offset_secs: f64,
    ) -> Result<PathBuf, String> {
        if !input_file.exists() {
            return Err(format!("Input file does not exist: {}", input_file.display()));
        }

        if let Some(parent) = output_image.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| format!("Failed to create thumbnail directory: {}", e))?;
        }

        let time_str = format!("{:.2}", time_offset_secs);

        let output = Command::new("ffmpeg")
            .arg("-ss")
            .arg(&time_str)
            .arg("-i")
            .arg(input_file)
            .arg("-vframes")
            .arg("1")
            .arg("-q:v")
            .arg("2")
            .arg("-y")
            .arg(output_image)
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| format!("Failed to execute ffmpeg for thumbnail: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("ffmpeg thumbnail generation failed: {}", stderr));
        }

        Ok(output_image.to_path_buf())
    }

    /// Transcode input video to web-streamable MP4 (H.264 + AAC + faststart).
    pub async fn transcode_web_mp4(
        input_file: &Path,
        output_file: &Path,
        max_height: Option<u32>,
    ) -> Result<PathBuf, String> {
        if !input_file.exists() {
            return Err(format!("Input file does not exist: {}", input_file.display()));
        }

        if let Some(parent) = output_file.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| format!("Failed to create output directory: {}", e))?;
        }

        let mut cmd = Command::new("ffmpeg");
        cmd.arg("-i").arg(input_file);

        // Scaling filter if specified
        if let Some(h) = max_height {
            cmd.arg("-vf").arg(format!("scale=-2:min({},ih)", h));
        }

        cmd.arg("-c:v")
            .arg("libx264")
            .arg("-preset")
            .arg("veryfast")
            .arg("-crf")
            .arg("23")
            .arg("-c:a")
            .arg("aac")
            .arg("-b:a")
            .arg("128k")
            .arg("-movflags")
            .arg("+faststart")
            .arg("-y")
            .arg(output_file);

        let output = cmd
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| format!("Failed to execute ffmpeg transcode: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("ffmpeg transcoding failed: {}", stderr));
        }

        Ok(output_file.to_path_buf())
    }

    /// Package media file into HLS stream (playlist.m3u8 and numbered .ts segments).
    pub async fn generate_hls(
        input_file: &Path,
        output_dir: &Path,
        segment_duration_secs: u32,
    ) -> Result<PathBuf, String> {
        if !input_file.exists() {
            return Err(format!("Input file does not exist: {}", input_file.display()));
        }

        tokio::fs::create_dir_all(output_dir)
            .await
            .map_err(|e| format!("Failed to create HLS output directory: {}", e))?;

        let playlist_path = output_dir.join("playlist.m3u8");
        let segment_pattern = output_dir.join("segment_%03d.ts");

        let output = Command::new("ffmpeg")
            .arg("-i")
            .arg(input_file)
            .arg("-c:v")
            .arg("libx264")
            .arg("-preset")
            .arg("veryfast")
            .arg("-crf")
            .arg("23")
            .arg("-c:a")
            .arg("aac")
            .arg("-b:a")
            .arg("128k")
            .arg("-hls_time")
            .arg(segment_duration_secs.to_string())
            .arg("-hls_list_size")
            .arg("0")
            .arg("-hls_segment_filename")
            .arg(&segment_pattern)
            .arg("-y")
            .arg(&playlist_path)
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| format!("Failed to execute ffmpeg HLS generation: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("ffmpeg HLS generation failed: {}", stderr));
        }

        Ok(playlist_path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_probe_nonexistent_file_returns_error() {
        let path = Path::new("nonexistent_test_video_12345.mp4");
        let res = Transcoder::probe(path).await;
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("does not exist"));
    }

    #[tokio::test]
    async fn test_thumbnail_nonexistent_file_returns_error() {
        let input = Path::new("nonexistent_test_video_12345.mp4");
        let output = Path::new("thumb.jpg");
        let res = Transcoder::generate_thumbnail(input, output, 1.0).await;
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("does not exist"));
    }
}
