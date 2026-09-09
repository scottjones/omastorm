//! Approximate IP location, fetched only on a client's `locate_home` request.
//! https://ipwhois.io/documentation documents the keyless HTTPS endpoint.
//! Retain only the city and coordinates, in memory; never store the IP.

use crate::protocol::{Location, VERSION};
use serde::Deserialize;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

const URL: &str = "https://ipwho.is/?fields=success,message,city,region,latitude,longitude";
const MAX_BODY: usize = 16 * 1024;
const TTL: Duration = Duration::from_secs(24 * 60 * 60);
const BACKOFF: Duration = Duration::from_secs(5 * 60);

type Cached = Option<(Instant, Result<Location, String>)>;
pub struct Locator {
    url: String,
    // Serializes concurrent windows/popovers so they share one lookup.
    cached: Mutex<Cached>,
}
impl Locator {
    pub fn new() -> Self {
        Self {
            url: std::env::var("OMASTORM_LOCATION_URL").unwrap_or_else(|_| URL.into()),
            cached: Mutex::new(None),
        }
    }

    pub async fn locate(&self) -> Result<Location, String> {
        let mut cached = self.cached.lock().await;
        if let Some((until, result)) = &*cached
            && Instant::now() < *until
        {
            return result.clone();
        }
        let result = self
            .fetch()
            .await
            .map_err(|_| "IP location unavailable; choose a location with LOCATION.".to_owned());
        let lifetime = if result.is_ok() { TTL } else { BACKOFF };
        *cached = Some((Instant::now() + lifetime, result.clone()));
        result
    }

    async fn fetch(&self) -> Result<Location, Box<dyn std::error::Error + Send + Sync>> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent(concat!(
                "omastorm/",
                env!("CARGO_PKG_VERSION"),
                " (https://omastorm.com)"
            ))
            .build()?;
        let mut response = client.get(&self.url).send().await?.error_for_status()?;
        let mut body = Vec::new();
        while let Some(chunk) = response.chunk().await? {
            if body.len() + chunk.len() > MAX_BODY {
                return Err("location response too large".into());
            }
            body.extend_from_slice(&chunk);
        }
        parse(&body).ok_or_else(|| "invalid location response".into())
    }
}

#[derive(Deserialize)]
struct Response {
    success: bool,
    #[serde(default)]
    city: String,
    #[serde(default)]
    region: String,
    latitude: f64,
    longitude: f64,
}
fn parse(bytes: &[u8]) -> Option<Location> {
    let value: Response = serde_json::from_slice(bytes).ok()?;
    if !value.success
        || !value.latitude.is_finite()
        || !value.longitude.is_finite()
        || value.latitude.abs() > 90.0
        || value.longitude.abs() > 180.0
    {
        return None;
    }
    let name = if value.city.trim().is_empty() {
        value.region
    } else {
        value.city
    };
    Some(Location {
        v: VERSION,
        name: name.chars().filter(|c| !c.is_control()).take(100).collect(),
        lat: value.latitude,
        lon: value.longitude,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_successful_numeric_coordinates() {
        let good = br#"{"success":true,"city":"Stamford","latitude":41.0534,"longitude":-73.5387,"ip":"not retained"}"#;
        let result = parse(good).unwrap();
        assert_eq!(result.name, "Stamford");
        assert_eq!((result.lat, result.lon), (41.0534, -73.5387));
        assert!(!serde_json::to_string(&result).unwrap().contains("retained"));
        for bad in [
            r#"{"success":false,"latitude":0,"longitude":0}"#,
            r#"{"success":true,"latitude":null,"longitude":0}"#,
            r#"{"success":true,"latitude":"41","longitude":0}"#,
            r#"{"success":true,"latitude":91,"longitude":0}"#,
            r#"{"success":true,"latitude":0,"longitude":181}"#,
            r#"{"success":true}"#,
        ] {
            assert!(parse(bad.as_bytes()).is_none(), "{bad}");
        }
    }
}
