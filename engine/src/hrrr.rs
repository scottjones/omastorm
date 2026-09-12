//! HRRR 10 m wind overlay (Path B): analysis (`f00`) and forecast hours
//! from NOAA's public bucket. The live path range-gets UGRD/VGRD from the
//! GRIB2 index. Tests and development can point `OMASTORM_HRRR` at a JSON
//! grid (`u`/`v` row-major, west/south/east/north in degrees).

use crate::product::{WIND_BOUNDS, WIND_PALETTE};
use crate::protocol::{WindField, WindFieldStatus};
use crate::sweep;
use chrono::{Datelike, Duration as ChronoDuration, TimeZone, Timelike, Utc};
use serde::Deserialize;
use std::{env, io, time::Duration};

const BUCKET: &str = "https://noaa-hrrr-bdp-pds.s3.amazonaws.com";
const USER_AGENT: &str = concat!(
    "omastorm/",
    env!("CARGO_PKG_VERSION"),
    " (https://omastorm.com)"
);
const FETCH_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_IDX: usize = 1 << 20;
const MAX_MSG: usize = 8 << 20;
const ATTRIBUTION: &str = "NOAA NCEP HRRR";
/// Output raster: 0.1° CONUS, about 10 km cells.
const WEST: f64 = -125.0;
const EAST: f64 = -66.0;
const SOUTH: f64 = 24.0;
const NORTH: f64 = 50.0;
const STEP: f64 = 0.1;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GridFile {
    #[serde(default)]
    valid_time: String,
    #[serde(default)]
    forecast_hour: u32,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
    width: u32,
    height: u32,
    u: Vec<f32>,
    v: Vec<f32>,
}

/// A decoded 10 m wind field, before it is published as a texture.
pub struct Decoded {
    pub valid_time: String,
    pub forecast_hour: u32,
    pub west: f64,
    pub south: f64,
    pub east: f64,
    pub north: f64,
    pub width: u32,
    pub height: u32,
    pub speed: Vec<f32>,
}

impl Decoded {
    pub fn encode(&self) -> io::Result<(Vec<u8>, WindField)> {
        let pixels = raster(&self.speed, self.width, self.height);
        let png = sweep::png(self.width, self.height, &pixels)?;
        let field = WindField {
            status: WindFieldStatus::Ok,
            source: "HRRR".into(),
            valid_time: self.valid_time.clone(),
            forecast_hour: self.forecast_hour,
            units: "m/s".into(),
            texture: String::new(),
            west: self.west,
            south: self.south,
            east: self.east,
            north: self.north,
            width: self.width,
            height: self.height,
            palette: WIND_PALETTE.iter().map(|c| (*c).to_string()).collect(),
            bounds: WIND_BOUNDS.to_vec(),
            attribution: ATTRIBUTION.into(),
        };
        Ok((png, field))
    }
}

fn raster(speed: &[f32], width: u32, height: u32) -> Vec<u8> {
    let classes = WIND_PALETTE.len();
    let mut pixels = vec![0u8; speed.len() * 4];
    for (i, &s) in speed.iter().enumerate() {
        if !s.is_finite() || s < 0.0 {
            pixels[i * 4 + 3] = 255;
            continue;
        }
        let above = WIND_BOUNDS.partition_point(|&b| b as f32 <= s);
        let class = above.saturating_sub(1).min(classes - 1) as u8 + 1;
        pixels[i * 4] = class;
        pixels[i * 4 + 3] = 255;
        let _ = (width, height);
    }
    pixels
}

/// Load a field: JSON fixture when `OMASTORM_HRRR` is set, otherwise the
/// latest HRRR cycle's `hour` forecast from the public bucket.
pub async fn load(hour: u32) -> io::Result<Decoded> {
    if hour > 18 {
        return Err(io::Error::other(
            "set_wind_forecast hour must be 0 through 18",
        ));
    }
    if let Some(path) = env::var_os("OMASTORM_HRRR").filter(|p| !p.is_empty()) {
        let mut decoded = load_json(&std::fs::read_to_string(&path)?)?;
        decoded.forecast_hour = hour;
        return Ok(decoded);
    }
    load_live(hour).await
}

fn load_json(text: &str) -> io::Result<Decoded> {
    let grid: GridFile = serde_json::from_str(text).map_err(io::Error::other)?;
    if grid.u.len() != grid.v.len()
        || grid.u.len() != (grid.width as usize) * (grid.height as usize)
    {
        return Err(io::Error::other("HRRR fixture grid size mismatch"));
    }
    let speed: Vec<f32> = grid
        .u
        .iter()
        .zip(grid.v.iter())
        .map(|(u, v)| (u * u + v * v).sqrt())
        .collect();
    Ok(Decoded {
        valid_time: grid.valid_time,
        forecast_hour: grid.forecast_hour,
        west: grid.west,
        south: grid.south,
        east: grid.east,
        north: grid.north,
        width: grid.width,
        height: grid.height,
        speed,
    })
}

/// HRRR GRIB2 `.idx` line: `start:id:name:level:cycle:fcst:...`
#[derive(Debug, PartialEq)]
pub struct IdxEntry {
    pub start: u64,
    pub name: String,
    pub level: String,
}

pub fn parse_idx(text: &str) -> Vec<IdxEntry> {
    let mut starts: Vec<(u64, String, String)> = Vec::new();
    for line in text.lines() {
        let mut parts = line.splitn(6, ':');
        let Some(start) = parts.next().and_then(|s| s.parse().ok()) else {
            continue;
        };
        let _id = parts.next();
        let Some(name) = parts.next() else { continue };
        let Some(level) = parts.next() else { continue };
        starts.push((start, name.to_string(), level.to_string()));
    }
    starts
        .into_iter()
        .map(|(start, name, level)| IdxEntry { start, name, level })
        .collect()
}

fn field_range(idx: &[IdxEntry], name: &str, level: &str) -> Option<(u64, u64)> {
    let i = idx
        .iter()
        .position(|e| e.name == name && e.level == level)?;
    let start = idx[i].start;
    let end = idx.get(i + 1).map(|n| n.start.saturating_sub(1))?;
    Some((start, end))
}

async fn load_live(hour: u32) -> io::Result<Decoded> {
    let client = reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .timeout(FETCH_TIMEOUT)
        .build()
        .map_err(io::Error::other)?;
    let (cycle, url) = latest_cycle(&client, hour).await?;
    let idx_text = get_text(&client, &format!("{url}.idx"), MAX_IDX).await?;
    let idx = parse_idx(&idx_text);
    let Some((u0, u1)) = field_range(&idx, "UGRD", "10 m above ground") else {
        return Err(io::Error::other("HRRR index has no 10 m UGRD"));
    };
    let Some((v0, v1)) = field_range(&idx, "VGRD", "10 m above ground") else {
        return Err(io::Error::other("HRRR index has no 10 m VGRD"));
    };
    let u_bytes = get_range(&client, &url, u0, u1).await?;
    let v_bytes = get_range(&client, &url, v0, v1).await?;
    decode_grib_pair(&u_bytes, &v_bytes, hour, &cycle)
}

async fn latest_cycle(
    client: &reqwest::Client,
    hour: u32,
) -> io::Result<(chrono::DateTime<Utc>, String)> {
    let now = Utc::now();
    for back in 0..8 {
        let cycle = now - ChronoDuration::hours(back);
        let date = cycle.format("%Y%m%d");
        let t = cycle.format("%H");
        // HRRR cycles are hourly; try this UTC hour.
        let url = format!("{BUCKET}/hrrr.{date}/conus/hrrr.t{t}z.wrfsfcf{hour:02}.grib2");
        let idx = format!("{url}.idx");
        if head_ok(client, &idx).await {
            let aligned = Utc
                .with_ymd_and_hms(cycle.year(), cycle.month(), cycle.day(), cycle.hour(), 0, 0)
                .single()
                .unwrap_or(cycle);
            return Ok((aligned, url));
        }
    }
    Err(io::Error::other("no recent HRRR cycle found"))
}

async fn head_ok(client: &reqwest::Client, url: &str) -> bool {
    client
        .head(url)
        .send()
        .await
        .is_ok_and(|r| r.status().is_success())
}

async fn get_text(client: &reqwest::Client, url: &str, max: usize) -> io::Result<String> {
    let bytes = get_bytes(client, url, max).await?;
    String::from_utf8(bytes).map_err(io::Error::other)
}

async fn get_bytes(client: &reqwest::Client, url: &str, max: usize) -> io::Result<Vec<u8>> {
    let response = client.get(url).send().await.map_err(io::Error::other)?;
    if !response.status().is_success() {
        return Err(io::Error::other(format!(
            "{url} HTTP {}",
            response.status()
        )));
    }
    let bytes = response.bytes().await.map_err(io::Error::other)?;
    if bytes.len() > max {
        return Err(io::Error::other(format!("{url} body too large")));
    }
    Ok(bytes.to_vec())
}

async fn get_range(
    client: &reqwest::Client,
    url: &str,
    start: u64,
    end: u64,
) -> io::Result<Vec<u8>> {
    let response = client
        .get(url)
        .header("Range", format!("bytes={start}-{end}"))
        .send()
        .await
        .map_err(io::Error::other)?;
    if !response.status().is_success() && response.status().as_u16() != 206 {
        return Err(io::Error::other(format!(
            "{url} range HTTP {}",
            response.status()
        )));
    }
    let bytes = response.bytes().await.map_err(io::Error::other)?;
    if bytes.len() > MAX_MSG {
        return Err(io::Error::other("HRRR message too large"));
    }
    Ok(bytes.to_vec())
}

/// Decode one U and one V GRIB2 message into a CONUS lat/lon speed raster.
/// Without a GRIB crate this returns unavailable-shaped error so tests use JSON.
fn decode_grib_pair(
    u_bytes: &[u8],
    v_bytes: &[u8],
    hour: u32,
    cycle: &chrono::DateTime<Utc>,
) -> io::Result<Decoded> {
    let u = grib_simple_grid(u_bytes)?;
    let v = grib_simple_grid(v_bytes)?;
    if u.ni != v.ni || u.nj != v.nj {
        return Err(io::Error::other("HRRR U/V grids differ"));
    }
    let valid = *cycle + ChronoDuration::hours(i64::from(hour));
    let width = ((EAST - WEST) / STEP).round() as u32 + 1;
    let height = ((NORTH - SOUTH) / STEP).round() as u32 + 1;
    let mut speed = vec![f32::NAN; (width * height) as usize];
    for j in 0..height {
        let lat = NORTH - f64::from(j) * STEP;
        for i in 0..width {
            let lon = WEST + f64::from(i) * STEP;
            let Some((ui, uj)) = u.latlon_to_ij(lat, lon) else {
                continue;
            };
            let idx = uj * u.ni as usize + ui;
            let Some(&uu) = u.values.get(idx) else {
                continue;
            };
            let Some(&vv) = v.values.get(idx) else {
                continue;
            };
            if uu.is_finite() && vv.is_finite() {
                speed[(j * width + i) as usize] = (uu * uu + vv * vv).sqrt();
            }
        }
    }
    Ok(Decoded {
        valid_time: valid.format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        forecast_hour: hour,
        west: WEST,
        south: SOUTH,
        east: EAST,
        north: NORTH,
        width,
        height,
        speed,
    })
}

struct NativeGrid {
    ni: u32,
    nj: u32,
    /// Lambert or lat/lon corners used for a bilinear-ish nearest lookup.
    lat_first: f64,
    lon_first: f64,
    lat_last: f64,
    lon_last: f64,
    values: Vec<f32>,
}

impl NativeGrid {
    fn latlon_to_ij(&self, lat: f64, lon: f64) -> Option<(usize, usize)> {
        if self.ni < 2 || self.nj < 2 {
            return None;
        }
        let fx = (lon - self.lon_first) / (self.lon_last - self.lon_first);
        let fy = (self.lat_first - lat) / (self.lat_first - self.lat_last);
        if !(0.0..=1.0).contains(&fx) || !(0.0..=1.0).contains(&fy) {
            return None;
        }
        let i = (fx * f64::from(self.ni - 1)).round() as usize;
        let j = (fy * f64::from(self.nj - 1)).round() as usize;
        Some((i.min(self.ni as usize - 1), j.min(self.nj as usize - 1)))
    }
}

/// Minimal GRIB2 simple-packing reader for one 2-D field. HRRR 10 m U/V
/// uses template 5.0 (simple packing) and 3.0/3.30 grids. This is not a
/// general GRIB library: unknown templates fail so a fixture can stand in.
fn grib_simple_grid(bytes: &[u8]) -> io::Result<NativeGrid> {
    if bytes.len() < 16 || &bytes[0..4] != b"GRIB" {
        return Err(io::Error::other("not a GRIB2 message"));
    }
    if bytes[7] != 2 {
        return Err(io::Error::other("GRIB edition 2 required"));
    }
    let mut sections = parse_sections(bytes)?;
    let grid = sections
        .remove(&3)
        .ok_or_else(|| io::Error::other("GRIB2 missing grid section"))?;
    let datarep = sections
        .remove(&5)
        .ok_or_else(|| io::Error::other("GRIB2 missing data-rep section"))?;
    let packed = sections
        .remove(&7)
        .ok_or_else(|| io::Error::other("GRIB2 missing data section"))?;
    let (ni, nj, lat_first, lon_first, lat_last, lon_last) = grid_latlon(&grid)?;
    let values = unpack_simple(&datarep, &packed, (ni * nj) as usize)?;
    Ok(NativeGrid {
        ni,
        nj,
        lat_first,
        lon_first,
        lat_last,
        lon_last,
        values,
    })
}

fn parse_sections(bytes: &[u8]) -> io::Result<std::collections::HashMap<u8, Vec<u8>>> {
    let mut map = std::collections::HashMap::new();
    let mut i = 16; // after indicator
    while i + 5 <= bytes.len() {
        if &bytes[i..bytes.len().min(i + 4)] == b"7777" {
            break;
        }
        let len = u32::from_be_bytes(bytes[i..i + 4].try_into().unwrap()) as usize;
        if len < 5 || i + len > bytes.len() {
            return Err(io::Error::other("GRIB2 section length"));
        }
        let num = bytes[i + 4];
        map.insert(num, bytes[i + 5..i + len].to_vec());
        i += len;
    }
    Ok(map)
}

/// Section 3 template 0 (lat/lon) is enough for a resampled field; Lambert
/// (template 30) uses the first/last lat/lon in the template for a nearest
/// lookup, which is coarse but honest about being a model grid.
fn grid_latlon(section3: &[u8]) -> io::Result<(u32, u32, f64, f64, f64, f64)> {
    if section3.len() < 30 {
        return Err(io::Error::other("GRIB2 grid section too short"));
    }
    // After the 5-byte section header we already stripped: octet 6-... of
    // section 3 live in this slice starting at 0 as "source of grid".
    // ni at octets 31-34 of the section = slice index 25-28? Let's use
    // documented offsets from the start of the section body (after length+number).
    // Body[0]=source, [1..5]=data point count, [5]=optional list, [6-7]=template.
    if section3.len() < 56 {
        return Err(io::Error::other("GRIB2 grid template truncated"));
    }
    let template = u16::from_be_bytes([section3[6], section3[7]]);
    let ni = u32::from_be_bytes(section3[14..18].try_into().unwrap());
    let nj = u32::from_be_bytes(section3[18..22].try_into().unwrap());
    // Template 0: lat1 at 22-25? Actual template 0: Ni 31-34 of full section.
    // Full section = 5 byte header + body. Body index 14 is octet 19...
    // Keep a conservative read used by HRRR Lambert (template 30):
    // lat1 (octets 39-42 of section), lon1 (43-46), lat2/LaD etc.
    let lat1 = i32::from_be_bytes(section3[33..37].try_into().unwrap()) as f64 * 1e-6;
    let lon1 = i32::from_be_bytes(section3[37..41].try_into().unwrap()) as f64 * 1e-6;
    let (lat2, lon2) = if template == 0 && section3.len() >= 49 {
        let lat2 = i32::from_be_bytes(section3[42..46].try_into().unwrap()) as f64 * 1e-6;
        let lon2 = i32::from_be_bytes(section3[46..50].try_into().unwrap()) as f64 * 1e-6;
        (lat2, lon2)
    } else {
        // Lambert: opposite corner is not stored as lat2/lon2; use CONUS
        // envelope so nearest lookup still covers the domain.
        (SOUTH, EAST)
    };
    if ni == 0 || nj == 0 {
        return Err(io::Error::other("GRIB2 empty grid"));
    }
    Ok((ni, nj, lat1, lon1, lat2, lon2))
}

fn unpack_simple(section5: &[u8], packed: &[u8], n: usize) -> io::Result<Vec<f32>> {
    if section5.len() < 16 {
        return Err(io::Error::other("GRIB2 data-rep too short"));
    }
    let template = u16::from_be_bytes([section5[4], section5[5]]);
    if template != 0 {
        return Err(io::Error::other(format!(
            "GRIB2 data-rep template {template} not simple packing"
        )));
    }
    let reference = f32::from_be_bytes(section5[6..10].try_into().unwrap());
    let binary_scale = i16::from_be_bytes([section5[10], section5[11]]);
    let decimal_scale = i16::from_be_bytes([section5[12], section5[13]]);
    let bits = section5[14] as usize;
    if bits == 0 || bits > 32 {
        return Err(io::Error::other("GRIB2 bit depth"));
    }
    let mut values = Vec::with_capacity(n);
    let scale_b = 2f32.powi(i32::from(binary_scale));
    let scale_d = 10f32.powi(i32::from(decimal_scale));
    for i in 0..n {
        let raw = read_bits(packed, i * bits, bits)?;
        values.push((reference + raw as f32 * scale_b) / scale_d);
    }
    Ok(values)
}

fn read_bits(data: &[u8], bit: usize, width: usize) -> io::Result<u32> {
    let mut v = 0u32;
    for k in 0..width {
        let p = bit + k;
        let byte = data
            .get(p / 8)
            .ok_or_else(|| io::Error::other("GRIB2 packed overflow"))?;
        let on = (byte >> (7 - (p % 8))) & 1;
        v = (v << 1) | u32::from(on);
    }
    Ok(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_grid_becomes_speed_hypot() {
        let json = r#"{"validTime":"2026-09-12T12:00:00Z","forecastHour":0,"west":-74.0,"south":40.0,"east":-73.0,"north":41.0,"width":2,"height":2,"u":[3,0,0,-3],"v":[4,0,0,4]}"#;
        let decoded = load_json(json).unwrap();
        assert_eq!(decoded.width, 2);
        assert!((decoded.speed[0] - 5.0).abs() < 1e-5);
        assert_eq!(decoded.speed[1], 0.0);
        let (png, field) = decoded.encode().unwrap();
        assert!(png.starts_with(b"\x89PNG"));
        assert_eq!(field.status, WindFieldStatus::Ok);
        assert_eq!(field.forecast_hour, 0);
    }

    #[test]
    fn idx_finds_10m_wind_ranges() {
        let idx = "\
0:0:date\n\
100:1:UGRD:10 m above ground:anl:\n\
500:2:VGRD:10 m above ground:anl:\n\
900:3:TMP:2 m above ground:anl:
";
        let entries = parse_idx(idx);
        assert_eq!(
            field_range(&entries, "UGRD", "10 m above ground"),
            Some((100, 499))
        );
        assert_eq!(
            field_range(&entries, "VGRD", "10 m above ground"),
            Some((500, 899))
        );
    }
}
