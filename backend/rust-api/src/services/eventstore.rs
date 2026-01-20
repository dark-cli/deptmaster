use anyhow::{Context, Result};
use base64::{Engine as _, engine::general_purpose};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct EventStoreClient {
    client: Client,
    base_url: String,
    username: String,
    password: String,
}

#[derive(Debug, Serialize)]
struct EventStoreEvent {
    #[serde(rename = "eventId")]
    event_id: String,
    #[serde(rename = "eventType")]
    event_type: String,
    #[serde(serialize_with = "serialize_data")]
    data: Value,
    #[serde(skip_serializing_if = "Option::is_none", serialize_with = "serialize_metadata_opt")]
    metadata: Option<Value>,
}

fn serialize_data<S>(data: &Value, serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    // EventStore expects data as base64-encoded JSON string
    let json_str = serde_json::to_string(data).map_err(serde::ser::Error::custom)?;
    let base64_str = general_purpose::STANDARD.encode(json_str.as_bytes());
    serializer.serialize_str(&base64_str)
}

fn serialize_metadata_opt<S>(metadata: &Option<Value>, serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    match metadata {
        Some(m) => {
            let json_str = serde_json::to_string(m).map_err(serde::ser::Error::custom)?;
            let base64_str = general_purpose::STANDARD.encode(json_str.as_bytes());
            serializer.serialize_some(&base64_str)
        }
        None => serializer.serialize_none(),
    }
}

#[derive(Debug, Deserialize)]
struct EventStoreReadResponse {
    #[allow(dead_code)]
    entries: Vec<EventStoreEntry>,
}

#[derive(Debug, Deserialize)]
pub struct EventStoreEntry {
    #[serde(rename = "eventId")]
    pub event_id: String,
    #[serde(rename = "eventType")]
    pub event_type: String,
    pub data: String,
    pub metadata: Option<String>,
}

impl EventStoreClient {
    pub fn new(base_url: String, username: String, password: String) -> Self {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            client,
            base_url,
            username,
            password,
        }
    }

    /// Write an event to a stream
    /// 
    /// # Arguments
    /// * `stream_name` - The name of the stream (e.g., "contact-{id}")
    /// * `event_type` - The type of event (e.g., "ContactCreated")
    /// * `event_id` - Unique event ID (for idempotency)
    /// * `data` - Event data as JSON
    /// * `expected_version` - Expected stream version (-1 for new stream, or specific version for updates)
    /// 
    /// Returns the stream version after write
    pub async fn write_event(
        &self,
        stream_name: &str,
        event_type: &str,
        event_id: Uuid,
        data: Value,
        expected_version: i64,
    ) -> Result<i64> {
        let url = format!("{}/streams/{}", self.base_url, stream_name);

        let event = EventStoreEvent {
            event_id: event_id.to_string(),
            event_type: event_type.to_string(),
            data,
            metadata: None,
        };

        // EventStore expects a JSON array directly, not wrapped in an object
        let events_array = vec![event];

        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::CONTENT_TYPE,
            "application/vnd.eventstore.events+json".parse().unwrap(),
        );
        headers.insert(
            "ES-ExpectedVersion",
            expected_version.to_string().parse().unwrap(),
        );

        let response = self
            .client
            .post(&url)
            .basic_auth(&self.username, Some(&self.password))
            .headers(headers)
            .json(&events_array)  // Send array directly
            .send()
            .await
            .context("Failed to send request to EventStore")?;

        if response.status().is_success() {
            // Extract version from Location header
            let location = response
                .headers()
                .get("Location")
                .and_then(|h| h.to_str().ok())
                .context("Missing Location header")?;

            // Location format: /streams/{stream}/{version}
            let version_str = location
                .split('/')
                .last()
                .context("Invalid Location header format")?;
            let version = version_str
                .parse::<i64>()
                .context("Failed to parse version from Location header")?;

            Ok(version)
        } else {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            anyhow::bail!(
                "EventStore write failed: {} - {}",
                status,
                body
            );
        }
    }

    /// Read events from a stream
    /// 
    /// # Arguments
    /// * `stream_name` - The name of the stream
    /// * `from_version` - Start reading from this version (0 for beginning)
    /// * `max_count` - Maximum number of events to read
    pub async fn read_events(
        &self,
        stream_name: &str,
        from_version: i64,
        max_count: Option<u64>,
    ) -> Result<Vec<EventStoreEntry>> {
        let count = max_count.unwrap_or(100);
        let url = format!(
            "{}/streams/{}/{}",
            self.base_url, stream_name, from_version
        );

        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::ACCEPT,
            "application/vnd.eventstore.atom+json".parse().unwrap(),
        );

        let response = self
            .client
            .get(&url)
            .basic_auth(&self.username, Some(&self.password))
            .headers(headers)
            .query(&[("embed", "body")])
            .query(&[("maxCount", &count.to_string())])
            .send()
            .await
            .context(format!("Failed to connect to EventStore at {} - is EventStore running?", self.base_url))?;

        if response.status().is_success() {
            // EventStore returns Atom feed format, parse it
            let body: Value = response
                .json()
                .await
                .context("Failed to parse EventStore response")?;
            
            // Extract entries from the feed
            let empty_vec = Vec::new();
            let entries = body
                .get("entries")
                .and_then(|e| e.as_array())
                .unwrap_or(&empty_vec);
            
            let mut result = Vec::new();
            for entry in entries {
                // EventStore Atom feed format: eventId and eventType are in the content field
                // or we need to extract from the entry structure
                // Try to get eventId from the entry ID (format: http://.../streams/{stream}/{version})
                let event_id = entry
                    .get("id")
                    .and_then(|id| id.as_str())
                    .and_then(|id_str| id_str.split('/').last())
                    .unwrap_or_else(|| {
                        // Fallback: try to get from eventId field if present
                        entry.get("eventId").and_then(|e| e.as_str()).unwrap_or("unknown")
                    });
                
                // Event type is in the summary field
                let event_type = entry
                    .get("summary")
                    .and_then(|s| s.as_str())
                    .unwrap_or("Unknown");
                
                // Try to get data from content field (if embed=body was used)
                let data = if let Some(content) = entry.get("content") {
                    if let Some(content_obj) = content.as_object() {
                        // Content might have data field
                        if let Some(data_val) = content_obj.get("data") {
                            serde_json::to_string(data_val).unwrap_or_default()
                        } else {
                            // Try to decode base64 if present
                            content_obj.get("data")
                                .and_then(|d| d.as_str())
                                .and_then(|s| {
                                    base64::engine::general_purpose::STANDARD.decode(s).ok()
                                })
                                .and_then(|bytes| String::from_utf8(bytes).ok())
                                .unwrap_or_default()
                        }
                    } else {
                        String::new()
                    }
                } else {
                    String::new()
                };
                        
                        result.push(EventStoreEntry {
                            event_id: event_id.to_string(),
                            event_type: event_type.to_string(),
                            data,
                    metadata: None,
                        });
            }
            
            Ok(result)
        } else if response.status() == reqwest::StatusCode::NOT_FOUND {
            // Stream doesn't exist yet, return empty
            Ok(vec![])
        } else {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            anyhow::bail!(
                "EventStore read failed: {} - {}",
                status,
                body
            );
        }
    }

    /// Read all events for an aggregate
    /// 
    /// # Arguments
    /// * `aggregate_type` - Type of aggregate (e.g., "contact", "transaction")
    /// * `aggregate_id` - ID of the aggregate
    pub async fn read_aggregate_events(
        &self,
        aggregate_type: &str,
        aggregate_id: &Uuid,
    ) -> Result<Vec<EventStoreEntry>> {
        let stream_name = format!("{}-{}", aggregate_type, aggregate_id);
        self.read_events(&stream_name, 0, None).await
    }

    /// Check if an event with given ID already exists (idempotency check)
    /// 
    /// # Arguments
    /// * `stream_name` - The name of the stream
    /// * `event_id` - The event ID to check
    pub async fn check_event_exists(
        &self,
        stream_name: &str,
        event_id: &Uuid,
    ) -> Result<bool> {
        // Read events (limit to reasonable number for idempotency check)
        let events = self.read_events(stream_name, 0, Some(100)).await?;
        Ok(events.iter().any(|e| e.event_id == event_id.to_string()))
    }

    /// Get stream version (for optimistic locking)
    /// 
    /// # Arguments
    /// * `stream_name` - The name of the stream
    pub async fn get_stream_version(&self, stream_name: &str) -> Result<Option<i64>> {
        // Try to read stream metadata to get the actual version
        // EventStore returns stream metadata in the Atom feed
        let url = format!("{}/streams/{}", self.base_url, stream_name);
        
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::ACCEPT,
            "application/vnd.eventstore.atom+json".parse().unwrap(),
        );

        let response = self
            .client
            .get(&url)
            .basic_auth(&self.username, Some(&self.password))
            .headers(headers)
            .send()
            .await
            .context("Failed to get stream metadata")?;

        if response.status() == reqwest::StatusCode::NOT_FOUND {
            Ok(None) // Stream doesn't exist
        } else if response.status().is_success() {
            let body: Value = response.json().await.context("Failed to parse stream metadata")?;
            
            // Try to get the last event number from the feed
            // EventStore Atom feed has a "headOfStream" link that contains the version
            if let Some(links) = body.get("links").and_then(|l| l.as_array()) {
                for link in links {
                    if let Some(relation) = link.get("relation").and_then(|r| r.as_str()) {
                        if relation == "last" {
                            // Extract version from the href: /streams/{stream}/{version}
                            if let Some(href) = link.get("uri").and_then(|u| u.as_str()) {
                                if let Some(version_str) = href.split('/').last() {
                                    if let Ok(version) = version_str.parse::<i64>() {
                                        return Ok(Some(version));
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Fallback: count events if we can't get version from metadata
            let events = self.read_events(stream_name, 0, None).await?;
            if events.is_empty() {
                Ok(None) // Stream exists but is empty
            } else {
                Ok(Some(events.len() as i64 - 1))
            }
        } else {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            anyhow::bail!("Failed to get stream version: {} - {}", status, body)
        }
    }
}
