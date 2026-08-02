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
    #[validate(length(min = 1, max = 100, message = "Device name is required (max 100 chars)"))]
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
#[derive(Debug, Serialize)]
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
