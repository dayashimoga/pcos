//! OCR and text extraction service.
//!
//! Extracts searchable text from images (via Tesseract) and PDFs (via built-in parser).
//! Indexes extracted content into Tantivy for full-text search.

use pcos_common::error::{AppError, AppResult};
use std::path::Path;

/// Extracted text result from a file.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ExtractionResult {
    pub file_id: uuid::Uuid,
    pub text: String,
    pub method: String,
    pub confidence: f32,
    pub page_count: Option<u32>,
}

/// Extract text from a file based on its MIME type.
pub async fn extract_text(file_path: &Path, mime_type: &str) -> AppResult<ExtractionResult> {
    match mime_type {
        "application/pdf" => extract_pdf(file_path).await,
        "text/plain" | "text/markdown" | "text/csv" | "text/html" | "application/json"
        | "application/xml" | "text/xml" => extract_plaintext(file_path).await,
        m if m.starts_with("image/") => extract_ocr(file_path).await,
        _ => Err(AppError::Validation(format!(
            "Unsupported MIME type for extraction: {}",
            mime_type
        ))),
    }
}

/// Extract text from plain text files (direct read).
async fn extract_plaintext(path: &Path) -> AppResult<ExtractionResult> {
    let text = tokio::fs::read_to_string(path)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to read file: {e}")))?;

    // Limit to first 1MB of text for indexing
    let truncated = if text.len() > 1_048_576 {
        text[..1_048_576].to_string()
    } else {
        text
    };

    Ok(ExtractionResult {
        file_id: uuid::Uuid::nil(),
        text: truncated,
        method: "plaintext".to_string(),
        confidence: 1.0,
        page_count: None,
    })
}

/// Extract text from PDF files using basic text stream parsing.
/// For production, integrate with `poppler` or `pdf-extract` crate.
async fn extract_pdf(path: &Path) -> AppResult<ExtractionResult> {
    let data = tokio::fs::read(path)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to read PDF: {e}")))?;

    // Simple PDF text extraction — find text between BT/ET markers
    let content = String::from_utf8_lossy(&data);
    let mut text = String::new();
    let mut in_text = false;
    let mut page_count = 0u32;

    for line in content.lines() {
        if line.contains("/Type /Page") {
            page_count += 1;
        }
        if line.contains("BT") {
            in_text = true;
        }
        if line.contains("ET") {
            in_text = false;
        }
        if in_text {
            // Extract text from Tj and TJ operators
            if let Some(start) = line.find('(') {
                if let Some(end) = line.rfind(')') {
                    if start < end {
                        text.push_str(&line[start + 1..end]);
                        text.push(' ');
                    }
                }
            }
        }
    }

    if text.trim().is_empty() {
        // Fallback: try Tesseract OCR on the PDF
        return extract_ocr(path).await;
    }

    Ok(ExtractionResult {
        file_id: uuid::Uuid::nil(),
        text: text.trim().to_string(),
        method: "pdf-parse".to_string(),
        confidence: 0.7,
        page_count: Some(page_count.max(1)),
    })
}

/// Extract text from images using Tesseract OCR (external binary).
async fn extract_ocr(path: &Path) -> AppResult<ExtractionResult> {
    let output = tokio::process::Command::new("tesseract")
        .arg(path.to_string_lossy().as_ref())
        .arg("stdout")
        .arg("--psm")
        .arg("3") // Fully automatic page segmentation
        .arg("-l")
        .arg("eng") // English language
        .output()
        .await
        .map_err(|e| {
            AppError::Internal(format!(
                "Tesseract not available: {e}. Install with: apt-get install tesseract-ocr"
            ))
        })?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(AppError::Internal(format!("Tesseract failed: {err}")));
    }

    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();

    Ok(ExtractionResult {
        file_id: uuid::Uuid::nil(),
        text,
        method: "tesseract-ocr".to_string(),
        confidence: 0.6,
        page_count: Some(1),
    })
}

/// Extract EXIF/metadata from image files.
pub async fn extract_metadata(path: &Path) -> AppResult<serde_json::Value> {
    let output = tokio::process::Command::new("exiftool")
        .arg("-json")
        .arg(path.to_string_lossy().as_ref())
        .output()
        .await;

    match output {
        Ok(out) if out.status.success() => {
            let json_str = String::from_utf8_lossy(&out.stdout);
            serde_json::from_str(&json_str)
                .map_err(|e| AppError::Internal(format!("EXIF parse error: {e}")))
        }
        _ => {
            // Fallback: return basic file metadata
            let meta = tokio::fs::metadata(path)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;
            Ok(serde_json::json!({
                "size_bytes": meta.len(),
                "modified": meta.modified().ok().map(|t| format!("{:?}", t)),
            }))
        }
    }
}
