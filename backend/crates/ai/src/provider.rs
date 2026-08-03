use pcos_common::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};

/// Configurable AI provider supporting local Ollama and compatible APIs.
#[derive(Debug, Clone)]
pub struct AiProvider {
    pub base_url: String,
    pub model: String,
    client: reqwest::Client,
}

#[derive(Debug, Serialize)]
struct OllamaRequest {
    model: String,
    prompt: String,
    stream: bool,
}

#[derive(Debug, Deserialize)]
struct OllamaResponse {
    response: String,
}

impl AiProvider {
    pub fn new(base_url: &str, model: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            model: model.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Create from environment variables (PCOS_AI__URL, PCOS_AI__MODEL).
    pub fn from_env() -> Option<Self> {
        let url =
            std::env::var("PCOS_AI__URL").unwrap_or_else(|_| "http://ollama:11434".to_string());
        let model = std::env::var("PCOS_AI__MODEL").unwrap_or_else(|_| "llama3.1".to_string());
        Some(Self::new(&url, &model))
    }

    /// Send a prompt to the AI model and get a response.
    pub async fn generate(&self, prompt: &str) -> AppResult<String> {
        let req = OllamaRequest {
            model: self.model.clone(),
            prompt: prompt.to_string(),
            stream: false,
        };

        let response = self
            .client
            .post(format!("{}/api/generate", self.base_url))
            .json(&req)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("AI request failed: {e}")))?;

        if !response.status().is_success() {
            return Err(AppError::Internal(format!(
                "AI returned status {}",
                response.status()
            )));
        }

        let body: OllamaResponse = response
            .json()
            .await
            .map_err(|e| AppError::Internal(format!("AI response parse failed: {e}")))?;

        Ok(body.response)
    }

    /// Check if the AI service is available.
    pub async fn health_check(&self) -> bool {
        self.client.get(&self.base_url).send().await.is_ok()
    }

    /// Generate tags for a filename and optional content snippet.
    pub async fn suggest_tags(&self, filename: &str, mime_type: &str) -> AppResult<Vec<String>> {
        let prompt = format!(
            "Given a file named '{}' with MIME type '{}', suggest 3-5 relevant tags as a JSON array of strings. Only output the JSON array, nothing else.",
            filename, mime_type
        );

        let response = self.generate(&prompt).await?;

        // Parse JSON array from response
        serde_json::from_str::<Vec<String>>(&response)
            .or_else(|_| {
                // Try to extract JSON array from response text
                if let Some(start) = response.find('[') {
                    if let Some(end) = response.rfind(']') {
                        return serde_json::from_str(&response[start..=end]);
                    }
                }
                Ok(vec![])
            })
            .map_err(|e| AppError::Internal(format!("Tag parse failed: {e}")))
    }
}
