//! Running system tools (nmcli, bluetoothctl) without blocking the window:
//! each command runs on its own thread and the result comes back as a future.

use std::io::Write;
use std::process::{Command, Stdio};

use iced::futures::channel::oneshot;

/// Run `program` with `args`, feeding `stdin` when given. Ok is stdout, Err
/// is stderr (or why the program could not run).
pub async fn run(program: &'static str, args: Vec<String>, stdin: Option<String>) -> Result<String, String> {
    let (tx, rx) = oneshot::channel();
    std::thread::spawn(move || {
        let _ = tx.send(run_blocking(program, &args, stdin.as_deref()));
    });
    rx.await
        .unwrap_or_else(|_| Err(format!("{program} stopped unexpectedly")))
}

/// The same, on the calling thread; for code that already runs on its own
/// thread and calls several tools in a row.
pub fn run_blocking(program: &str, args: &[String], stdin: Option<&str>) -> Result<String, String> {
    let mut command = Command::new(program);
    command
        .args(args)
        .env("LC_ALL", "C")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(if stdin.is_some() { Stdio::piped() } else { Stdio::null() });
    let mut child = command.spawn().map_err(|e| format!("could not run {program}: {e}"))?;
    if let (Some(input), Some(mut pipe)) = (stdin, child.stdin.take()) {
        // Errors surface through the exit status below.
        let _ = pipe.write_all(input.as_bytes());
    }
    let output = child.wait_with_output().map_err(|e| format!("{program}: {e}"))?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        Err(if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("{program} failed ({})", output.status)
        })
    }
}

/// Run on a background thread, for a sequence of blocking calls.
pub async fn spawn<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> Option<T> {
    let (tx, rx) = oneshot::channel();
    std::thread::spawn(move || {
        let _ = tx.send(work());
    });
    rx.await.ok()
}

/// Settings a running program has to be told about: (file prefix, script
/// and argument under ~/.config/scripts).
const AFTER_WRITE: &[(&str, &str, &str)] = &[("night-", "night.sh", "apply")];

/// Run what a written setting needs, on its own thread (which also reaps it).
pub fn after_write(file: &str) {
    for (prefix, script, arg) in AFTER_WRITE {
        if file.starts_with(prefix) {
            let path = crate::store::home()
                .join(".config/scripts")
                .join(script)
                .to_string_lossy()
                .into_owned();
            std::thread::spawn(move || {
                let _ = run_blocking("bash", &[path, arg.to_string()], None);
            });
        }
    }
}

/// Shorthand for an argument list.
pub fn args(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| s.to_string()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn returns_stdout_or_the_error() {
        assert_eq!(run_blocking("printf", &args(&["hi"]), None), Ok("hi".to_string()));
        assert_eq!(run_blocking("cat", &[], Some("piped")), Ok("piped".to_string()));
        let err = run_blocking("sh", &args(&["-c", "echo boom >&2; exit 3"]), None).unwrap_err();
        assert_eq!(err, "boom");
        assert!(
            run_blocking("no-such-program-xyz", &[], None)
                .unwrap_err()
                .contains("could not run")
        );
    }
}
