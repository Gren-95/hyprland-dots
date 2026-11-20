//! Running system tools (nmcli, bluetoothctl) without blocking the window:
//! each command runs on its own thread and the result comes back as a future.

use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use iced::futures::channel::oneshot;

use crate::store::{Kind, Store, Value};

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
    // Read both pipes while waiting, so a chatty child cannot fill one and
    // block; a child that outlives RUN_TIMEOUT is killed, so a hung tool
    // still ends in an error instead of a page that waits forever.
    let drain = |pipe: Option<Box<dyn Read + Send>>| {
        std::thread::spawn(move || {
            let mut out = Vec::new();
            if let Some(mut p) = pipe {
                let _ = p.read_to_end(&mut out);
            }
            out
        })
    };
    let stdout = drain(child.stdout.take().map(|p| Box::new(p) as Box<dyn Read + Send>));
    let stderr = drain(child.stderr.take().map(|p| Box::new(p) as Box<dyn Read + Send>));
    let deadline = Instant::now() + RUN_TIMEOUT;
    let status = loop {
        match child.try_wait().map_err(|e| format!("{program}: {e}"))? {
            Some(status) => break status,
            None if Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("{program} did not finish in {} s", RUN_TIMEOUT.as_secs()));
            }
            None => std::thread::sleep(Duration::from_millis(20)),
        }
    };
    let stdout = stdout.join().unwrap_or_default();
    let stderr = stderr.join().unwrap_or_default();
    if status.success() {
        Ok(String::from_utf8_lossy(&stdout).into_owned())
    } else {
        let stderr = String::from_utf8_lossy(&stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&stdout).trim().to_string();
        Err(if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("{program} failed ({status})")
        })
    }
}

/// A zenity file or folder chooser: Ok(Some(path)), Ok(None) when cancelled
/// (zenity exits 1), Err when zenity cannot run.
pub async fn pick(args: Vec<String>) -> Result<Option<String>, String> {
    match run("zenity", args, None).await {
        Ok(out) => Ok(Some(out.trim().to_string()).filter(|p| !p.is_empty())),
        Err(e) if e.starts_with("could not run") => Err("The file chooser (zenity) is not installed".into()),
        Err(_) => Ok(None),
    }
}

/// A failed change that asked polkit for the password: a refused or
/// cancelled prompt reads as such, anything else as the tool's own error.
pub fn polkit_error(e: &str) -> String {
    let lower = e.to_lowercase();
    if ["not authorized", "authentication", "access denied", "dismissed"]
        .iter()
        .any(|w| lower.contains(w))
    {
        "Not changed: the password was not given".into()
    } else {
        format!("Not changed: {e}")
    }
}

/// The longest any tool may run: long enough to type a password into the
/// polkit prompt or pair a Bluetooth device.
const RUN_TIMEOUT: Duration = Duration::from_secs(120);

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
const AFTER_WRITE: &[(&str, &str, &str)] = &[
    ("night-", "night.sh", "apply"),
    ("gamemode-feral", "gamemode.sh", "feral"),
    ("idle-hold-claude", "claude-activity.sh", "prune"),
    ("power-", "power-auto.sh", "once"),
];

/// Settings that also change something outside the shell, by file: the
/// shell reads the setting itself, these make Hyprland or GTK follow. Each
/// gets the stored value. Add a line here for the next one.
type Apply = (&'static str, Kind, fn(Value));

const APPLY: &[Apply] = &[
    ("animations", Kind::Bool, apply_animations),
    ("radius-scale", Kind::Real, apply_rounding),
    ("color-scheme", Kind::Text, apply_color_scheme),
    ("app-font", Kind::Text, apply_app_font),
    ("cursor-size", Kind::Int, apply_cursor_size),
];

fn gsettings_set(key: &str, value: &str) {
    let _ = run_blocking(
        "gsettings",
        &args(&["set", "org.gnome.desktop.interface", key, value]),
        None,
    );
}

/// Dark or light for apps that follow the system; adw-gtk3 has a theme for
/// each, so GTK 3 apps follow too.
fn apply_color_scheme(value: Value) {
    let Value::Text(scheme) = value else { return };
    gsettings_set("color-scheme", &scheme);
    let theme = run_blocking(
        "gsettings",
        &args(&["get", "org.gnome.desktop.interface", "gtk-theme"]),
        None,
    )
    .unwrap_or_default();
    if theme.contains("adw-gtk3") {
        let dark = if scheme == "prefer-dark" {
            "adw-gtk3-dark"
        } else {
            "adw-gtk3"
        };
        gsettings_set("gtk-theme", dark);
    }
}

/// The GTK font, keeping its size ("Adwaita Sans 11").
fn apply_app_font(value: Value) {
    let Value::Text(family) = value else { return };
    let current = run_blocking(
        "gsettings",
        &args(&["get", "org.gnome.desktop.interface", "font-name"]),
        None,
    )
    .unwrap_or_default();
    gsettings_set("font-name", &format!("{family} {}", font_size(&current)));
}

/// The size at the end of a font name ("'Adwaita Sans 11'" is 11).
pub fn font_size(font_name: &str) -> String {
    font_name
        .trim()
        .trim_matches('\'')
        .rsplit_once(' ')
        .map(|(_, size)| size)
        .filter(|s| s.parse::<f64>().is_ok())
        .unwrap_or("11")
        .to_string()
}

fn apply_cursor_size(value: Value) {
    let Value::Int(size) = value else { return };
    let script = crate::store::home().join(".config/scripts/cursor-theme.sh");
    let _ = run_blocking(
        "bash",
        &[script.to_string_lossy().into_owned(), "size".into(), size.to_string()],
        None,
    );
}

/// Animations on or off everywhere: Hyprland's animations:enabled (kept in
/// settings.lua, the option the Windows panel shows) and GTK's
/// enable-animations.
fn apply_animations(value: Value) {
    let on = value != Value::Bool(false);
    set_hyprland("animations:enabled", serde_json::json!(on));
    let _ = run_blocking(
        "gsettings",
        &args(&[
            "set",
            "org.gnome.desktop.interface",
            "enable-animations",
            if on { "true" } else { "false" },
        ]),
        None,
    );
}

/// Window corners in Hyprland, from the shell's corner roundness: the same
/// 12 px base as the shell's large radius (Theme.radius.lg), times the
/// scale. The Windows panel shows the result and can fine-tune it.
fn apply_rounding(value: Value) {
    let Value::Real(scale) = value else { return };
    set_hyprland("decoration:rounding", serde_json::json!(window_rounding(scale)));
}

/// Hyprland's window rounding for a corner roundness scale.
pub fn window_rounding(scale: f64) -> i64 {
    (WINDOW_RADIUS * scale).round().max(0.0) as i64
}

const WINDOW_RADIUS: f64 = 12.0;

/// One Hyprland option, kept in settings.lua and applied now.
fn set_hyprland(option: &str, value: serde_json::Value) {
    let option = option.to_string();
    let _ = crate::hypr::update_blocking(
        move |s| {
            s.options.insert(option, value);
        },
        "",
    );
}

/// Run what a written setting needs, each on its own thread. The window
/// lets them run; the CLI waits for the returned threads before it exits.
pub fn after_write(file: &str) -> Vec<std::thread::JoinHandle<()>> {
    let mut work = Vec::new();
    if let Some((_, kind, apply)) = APPLY.iter().find(|(f, ..)| *f == file) {
        let (kind, apply) = (*kind, *apply);
        if let Some(value) = Store::new(Store::default_dir()).read(file, kind) {
            work.push(std::thread::spawn(move || apply(value)));
        }
    }
    for (prefix, script, arg) in AFTER_WRITE {
        if file.starts_with(prefix) {
            let path = crate::store::home()
                .join(".config/scripts")
                .join(script)
                .to_string_lossy()
                .into_owned();
            work.push(std::thread::spawn(move || {
                let _ = run_blocking("bash", &[path, arg.to_string()], None);
            }));
        }
    }
    work
}

/// Shorthand for an argument list.
pub fn args(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| s.to_string()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_large_output_and_errors() {
        let big = run_blocking("sh", &args(&["-c", "head -c 300000 /dev/zero; echo oops >&2"]), None).unwrap();
        assert_eq!(big.len(), 300000);
        assert_eq!(
            run_blocking("sh", &args(&["-c", "echo nope >&2; exit 3"]), None),
            Err("nope".into())
        );
        assert!(
            run_blocking("no-such-tool-here", &[], None)
                .unwrap_err()
                .starts_with("could not run")
        );
        assert_eq!(
            polkit_error("Interactive authentication required."),
            "Not changed: the password was not given"
        );
        assert_eq!(polkit_error("Unknown unit x"), "Not changed: Unknown unit x");
    }

    #[test]
    fn reads_the_font_size() {
        assert_eq!(font_size("'Adwaita Sans 11'\n"), "11");
        assert_eq!(font_size("'Cantarell 10.5'"), "10.5");
        assert_eq!(font_size("'Sans'"), "11");
    }

    #[test]
    fn window_rounding_follows_the_scale() {
        assert_eq!(window_rounding(1.0), 12);
        assert_eq!(window_rounding(0.5), 6);
        assert_eq!(window_rounding(0.0), 0);
        assert_eq!(window_rounding(1.55), 19);
    }

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
