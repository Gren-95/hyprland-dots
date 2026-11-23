//! Running programs, and the guards around a run: one run at a time, enough
//! disk, a network, the machine kept awake, sudo kept fresh.

use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

/// What a finished program printed, and its exit code (-1 when killed).
#[derive(Debug, Default)]
pub struct Ran {
    pub code: i32,
    pub out: String,
    pub err: String,
}

impl Ran {
    pub fn ok(&self) -> bool {
        self.code == 0
    }

    /// The last lines of both streams, for an error message.
    pub fn tail(&self, lines: usize) -> String {
        let all: Vec<&str> = self
            .out
            .lines()
            .chain(self.err.lines())
            .filter(|l| !l.trim().is_empty())
            .collect();
        all[all.len().saturating_sub(lines)..].join("\n")
    }
}

/// The run's log file; `Log::none()` writes nowhere (the checks).
pub struct Log(Option<Mutex<File>>);

impl Log {
    pub fn none() -> Log {
        Log(None)
    }

    pub fn create(path: &Path) -> Result<Log, String> {
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir).map_err(|e| format!("could not make {}: {e}", dir.display()))?;
        }
        let file = File::create(path).map_err(|e| format!("could not write {}: {e}", path.display()))?;
        Ok(Log(Some(Mutex::new(file))))
    }

    /// A failed log write must not stop an update, so errors are dropped.
    pub fn write(&self, bytes: &[u8]) {
        if let Some(file) = &self.0
            && let Ok(mut f) = file.lock()
        {
            let _ = f.write_all(bytes);
        }
    }

    pub fn line(&self, text: &str) {
        self.write(format!("{text}\n").as_bytes());
    }
}

/// Run a program to the end with stdin closed, both streams captured and
/// copied to the log as they come.
pub fn run(log: &Log, program: &str, args: &[&str]) -> Result<Ran, String> {
    log.line(&format!("\n$ {program} {}", args.join(" ")));
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("could not run {program}: {e}"))?;
    let (out, err) = (child.stdout.take(), child.stderr.take());
    let (out, err) = thread::scope(|s| {
        let out = s.spawn(|| pump(out, log));
        let err = s.spawn(|| pump(err, log));
        (out.join().unwrap_or_default(), err.join().unwrap_or_default())
    });
    let status = child.wait().map_err(|e| format!("{program}: {e}"))?;
    Ok(Ran {
        code: status.code().unwrap_or(-1),
        out,
        err,
    })
}

fn pump(stream: Option<impl Read>, log: &Log) -> String {
    let Some(mut stream) = stream else { return String::new() };
    let mut all = Vec::new();
    let mut buf = [0; 8192];
    while let Ok(n) = stream.read(&mut buf) {
        if n == 0 {
            break;
        }
        log.write(&buf[..n]);
        all.extend_from_slice(&buf[..n]);
    }
    String::from_utf8_lossy(&all).into_owned()
}

/// `program` is on PATH.
pub fn on_path(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(program).is_file()))
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

/// ~/.local/state/dots, where the run record and logs live.
pub fn state_dir() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/state"))
        .join("dots")
}

/// JSON from a URL, through curl.
pub fn get_json(url: &str) -> Result<serde_json::Value, String> {
    let ran = run(&Log::none(), "curl", &["-fsS", "--max-time", "10", url])?;
    if !ran.ok() {
        return Err(format!("{url}: {}", ran.err.trim()));
    }
    serde_json::from_str(&ran.out).map_err(|e| format!("{url}: {e}"))
}

/// The local time of a unix time, in `date` format (`%H:%M`).
pub fn local_time(unix: i64, format: &str) -> String {
    run(
        &Log::none(),
        "date",
        &["-d", &format!("@{unix}"), &format!("+{format}")],
    )
    .map(|r| r.out.trim().to_string())
    .unwrap_or_default()
}

pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// Held for the whole run: a second `upi` stops at once.
pub fn lock() -> Result<File, String> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let file = File::create(dir.join("upi.lock")).map_err(|e| format!("could not make the lock file: {e}"))?;
    file.try_lock()
        .map_err(|_| "Another upi is already running".to_string())?;
    Ok(file)
}

/// Free space on /, in GiB.
pub fn free_gib() -> Result<u64, String> {
    let ran = run(&Log::none(), "df", &["--output=avail", "--block-size=1", "/"])?;
    ran.out
        .lines()
        .last()
        .and_then(|l| l.trim().parse::<u64>().ok())
        .map(|b| b / 1024u64.pow(3))
        .ok_or_else(|| "could not read the free space on /".into())
}

/// google.com or amazon.com answers. Any HTTP answer counts: a site that
/// refuses the request still proves there is a network.
pub fn online() -> bool {
    ["https://www.google.com", "https://www.amazon.com"].iter().any(|url| {
        run(
            &Log::none(),
            "curl",
            &["-sS", "--head", "--max-time", "5", "-o", "/dev/null", url],
        )
        .is_ok_and(|r| r.ok())
    })
}

/// Keeps the machine awake and out of suspend while it lives, through a
/// logind inhibitor (hypridle honours idle inhibitors; a sleep inhibitor
/// stops a suspend in the middle of a package transaction).
pub struct Awake(Child);

impl Awake {
    pub fn hold() -> Result<Awake, String> {
        Command::new("systemd-inhibit")
            .args([
                "--what=idle:sleep",
                "--who=upi",
                "--why=Updating the system",
                "--mode=block",
                "sleep",
                "infinity",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map(Awake)
            .map_err(|e| format!("could not keep the machine awake: {e}"))
    }
}

impl Drop for Awake {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

/// Asks for the sudo password once (on the terminal), then keeps the
/// credentials fresh while it lives, so steps can run `sudo -n`.
pub struct Sudo {
    stop: std::sync::Arc<AtomicBool>,
    keeper: Option<thread::JoinHandle<()>>,
}

impl Sudo {
    pub fn ask() -> Result<Sudo, String> {
        let status = Command::new("sudo")
            .arg("-v")
            .status()
            .map_err(|e| format!("could not run sudo: {e}"))?;
        if !status.success() {
            return Err("sudo did not get the password".into());
        }
        let stop = std::sync::Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        let keeper = thread::spawn(move || {
            let mut waited = 0;
            while !flag.load(Ordering::Relaxed) {
                thread::sleep(Duration::from_secs(1));
                waited += 1;
                if waited % 60 == 0 {
                    let _ = run(&Log::none(), "sudo", &["-n", "-v"]);
                }
            }
        });
        Ok(Sudo {
            stop,
            keeper: Some(keeper),
        })
    }
}

impl Drop for Sudo {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(k) = self.keeper.take() {
            let _ = k.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runs_programs() {
        let ran = run(&Log::none(), "sh", &["-c", "echo out; echo err >&2; exit 3"]).unwrap();
        assert_eq!((ran.code, ran.out.as_str(), ran.err.as_str()), (3, "out\n", "err\n"));
        assert_eq!(ran.tail(1), "err");
        assert!(run(&Log::none(), "no-such-program-here", &[]).is_err());
        assert!(on_path("sh"));
        assert!(!on_path("no-such-program-here"));
    }
}
