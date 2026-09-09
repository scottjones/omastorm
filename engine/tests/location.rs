use serde_json::{Value, json};
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    net::TcpListener,
    os::unix::net::UnixStream,
    process::{Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

// A local HTTP service counts lookups; no external endpoint is used.
struct Service {
    url: String,
    count: Arc<AtomicUsize>,
    stop: Arc<AtomicBool>,
    worker: Option<thread::JoinHandle<()>>,
}
impl Service {
    fn start(status: &str, body: &str) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let url = format!("http://{}/", listener.local_addr().unwrap());
        let count = Arc::new(AtomicUsize::new(0));
        let stop = Arc::new(AtomicBool::new(false));
        let (counted, stopped) = (count.clone(), stop.clone());
        let response = format!(
            "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        let worker = thread::spawn(move || {
            while !stopped.load(Ordering::SeqCst) {
                let Ok((stream, _)) = listener.accept() else {
                    thread::sleep(Duration::from_millis(5));
                    continue;
                };
                stream
                    .set_read_timeout(Some(Duration::from_secs(2)))
                    .unwrap();
                let mut request = BufReader::new(stream);
                loop {
                    let mut line = String::new();
                    if request.read_line(&mut line).unwrap() == 0 || line == "\r\n" {
                        break;
                    }
                }
                counted.fetch_add(1, Ordering::SeqCst);
                request.get_mut().write_all(response.as_bytes()).unwrap();
            }
        });
        Self {
            url,
            count,
            stop,
            worker: Some(worker),
        }
    }
}
impl Drop for Service {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        self.worker.take().unwrap().join().unwrap();
    }
}
fn read(client: &mut BufReader<UnixStream>) -> Value {
    let mut line = String::new();
    client.read_line(&mut line).unwrap();
    serde_json::from_str(&line).unwrap()
}
fn location_reply(client: &mut BufReader<UnixStream>) -> Value {
    // State broadcasts can arrive between the command and its private reply.
    for _ in 0..8 {
        let reply = read(client);
        if reply["type"] != "state" {
            return reply;
        }
        assert_eq!(reply["site"]["id"], "", "lookup selected a station");
    }
    panic!("location reply not received");
}

#[test]
fn location_is_on_demand_shared_cached_and_never_selects_a_station() {
    for (case, status, body, expected) in [
        (
            "success",
            "200 OK",
            r#"{"success":true,"city":"Stamford","latitude":41.0534,"longitude":-73.5387}"#,
            "location",
        ),
        ("failure", "503 Unavailable", "unavailable", "error"),
        ("invalid", "200 OK", r#"{"success":false}"#, "error"),
    ] {
        let service = Service::start(status, body);
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join(format!("../target/location-{}-{case}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let binary = env!("CARGO_BIN_EXE_omastorm-engine");
        let mut daemon = Command::new(binary)
            .env_remove("OMASTORM_ARCHIVE")
            .env("XDG_RUNTIME_DIR", &root)
            .env("XDG_CACHE_HOME", root.join("cache"))
            .env("OMASTORM_LOCATION_URL", &service.url)
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        let socket = root.join("omastorm/engine.sock");
        let deadline = Instant::now() + Duration::from_secs(5);
        while !socket.exists() {
            assert!(daemon.try_wait().unwrap().is_none());
            assert!(Instant::now() < deadline);
            thread::sleep(Duration::from_millis(10));
        }
        let connect = || {
            let stream = UnixStream::connect(&socket).unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(3)))
                .unwrap();
            let mut client = BufReader::new(stream);
            assert_eq!(read(&mut client)["type"], "hello");
            let state = read(&mut client);
            assert_eq!(state["site"]["id"], "");
            client
        };
        let mut first = connect();
        let mut second = connect();
        assert_eq!(
            service.count.load(Ordering::SeqCst),
            0,
            "startup performed a lookup"
        );
        let command = json!({"type":"locate_home"});
        writeln!(first.get_mut(), "{command}").unwrap();
        writeln!(second.get_mut(), "{command}").unwrap();
        for client in [&mut first, &mut second] {
            let reply = location_reply(client);
            assert_eq!(reply["type"], expected, "{reply}");
            if expected == "location" {
                assert_eq!(reply["name"], "Stamford");
                assert_eq!(reply["lat"], 41.0534);
                assert!(reply.get("ip").is_none());
            } else {
                assert_eq!(reply["command"], "locate_home");
                assert!(reply["message"].as_str().unwrap().contains("LOCATION"));
            }
        }
        writeln!(first.get_mut(), "{command}").unwrap();
        assert_eq!(location_reply(&mut first)["type"], expected);
        assert_eq!(
            service.count.load(Ordering::SeqCst),
            1,
            "success/error was not shared and cached"
        );
        // A fresh client still sees no selected station: location is a reply,
        // and does not launch live radar or overwrite a user's selection.
        drop(connect());
        let stopped = Command::new(binary)
            .arg("stop")
            .env("XDG_RUNTIME_DIR", &root)
            .status()
            .unwrap();
        assert!(stopped.success());
        daemon.wait().unwrap();
        fs::remove_dir_all(&root).unwrap();
    }
}
