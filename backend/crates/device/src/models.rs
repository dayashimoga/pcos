use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// Database model for the devices table.
#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct Device {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub device_type: String,
    pub os: String,
    pub os_version: String,
    pub agent_version: String,
    pub is_online: bool,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Request DTO for registering a new device.
#[derive(Debug, Deserialize, Validate)]
pub struct RegisterDeviceRequest {
    #[validate(length(
        min = 1,
        max = 100,
        message = "Device name is required (max 100 chars)"
    ))]
    pub name: String,

    #[validate(length(min = 1, max = 50, message = "Device type is required"))]
    pub device_type: String,

    #[validate(length(min = 1, max = 50))]
    pub os: String,

    #[validate(length(max = 50))]
    pub os_version: String,

    #[validate(length(max = 50))]
    pub agent_version: String,
}

/// Response DTO for device data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceResponse {

    pub id: Uuid,
    pub name: String,
    pub device_type: String,
    pub os: String,
    pub os_version: String,
    pub agent_version: String,
    pub is_online: bool,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

impl From<Device> for DeviceResponse {
    fn from(d: Device) -> Self {
        Self {
            id: d.id,
            name: d.name,
            device_type: d.device_type,
            os: d.os,
            os_version: d.os_version,
            agent_version: d.agent_version,
            is_online: d.is_online,
            last_seen_at: d.last_seen_at,
            created_at: d.created_at,
        }
    }
}

/// Response DTO for device list.
#[derive(Debug, Serialize)]
pub struct DeviceListResponse {
    pub devices: Vec<DeviceResponse>,
    pub total: i64,
}

/// Request to create a new one-time device pairing/enrollment session.
#[derive(Debug, Deserialize, Default)]
pub struct CreatePairingRequest {
    pub expires_in_seconds: Option<u64>,
}

/// Response containing OTP pairing code and complete provisioning payload.
#[derive(Debug, Serialize)]
pub struct PairingSessionResponse {
    pub pairing_code: String,
    pub enrollment_token: String,
    pub expires_at: DateTime<Utc>,
    pub qr_payload: String,
}

/// Request from a device to redeem a pairing session.
#[derive(Debug, Deserialize, Validate)]
pub struct RedeemPairingRequest {
    pub pairing_code: Option<String>,
    pub enrollment_token: Option<String>,
    #[validate(length(min = 1, max = 100))]
    pub device_name: String,
    #[validate(length(min = 1, max = 50))]
    pub device_type: String,
    #[validate(length(min = 1, max = 50))]
    pub os: String,
    pub os_version: Option<String>,
    pub agent_version: Option<String>,
    pub client_fingerprint: Option<String>,
}

/// Candidate device requesting connection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateDevice {
    pub device_name: String,
    pub device_type: String,
    pub os: String,
    pub os_version: String,
    pub agent_version: String,
    pub client_fingerprint: Option<String>,
    pub requested_at: DateTime<Utc>,
}

/// Request to claim a pairing code from mobile device
#[derive(Debug, Deserialize, Validate)]
pub struct ClaimPairingRequest {
    pub pairing_code: Option<String>,
    pub enrollment_token: Option<String>,
    #[validate(length(min = 1, max = 100))]
    pub device_name: String,
    #[validate(length(min = 1, max = 50))]
    pub device_type: String,
    #[validate(length(min = 1, max = 50))]
    pub os: String,
    pub os_version: Option<String>,
    pub agent_version: Option<String>,
    pub client_fingerprint: Option<String>,
}

/// Request to approve or reject a pending pairing session
#[derive(Debug, Deserialize)]
pub struct ApprovePairingRequest {
    pub pairing_code: Option<String>,
    pub enrollment_token: Option<String>,
    pub approved: bool,
}

/// Real-time status of a pairing session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingStatusResponse {
    pub pairing_code: String,
    pub enrollment_token: String,
    pub status: String, // "pending_redeem", "pending_approval", "approved", "rejected", "expired"
    pub expires_at: DateTime<Utc>,
    pub candidate_device: Option<CandidateDevice>,
    pub redeem_result: Option<RedeemPairingResponse>,
}

/// Provisioning response with minted tokens for device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RedeemPairingResponse {
    pub device: DeviceResponse,
    pub access_token: String,
    pub refresh_token: String,
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_register_device_validation() {
        let valid = RegisterDeviceRequest {
            name: "My Laptop".into(),
            device_type: "desktop".into(),
            os: "Windows".into(),
            os_version: "11".into(),
            agent_version: "0.1.0".into(),
        };
        assert!(valid.validate().is_ok());

        let invalid = RegisterDeviceRequest {
            name: "".into(),
            device_type: "desktop".into(),
            os: "Windows".into(),
            os_version: "11".into(),
            agent_version: "0.1.0".into(),
        };
        assert!(invalid.validate().is_err());
    }
}
