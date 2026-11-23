//! The sync tools released as static builds on GitHub: immich-rs (the Immich
//! photo sync's CLI) and jellyfin-music-rs (the Jellyfin music sync). The
//! installed copy is the one `dots.sh setup` puts in ~/.local/bin, where the
//! sync scripts run it from. The newest release is read from where
//! `releases/latest` redirects, which spends no GitHub API quota. The update
//! downloads that release's build for this machine, checks it against the
//! release's SHA256SUMS and swaps it in by rename.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use crate::check::Item;
use crate::sys::{self, Log};

/// The program names, which are also their repositories' names.
pub const IMMICH_RS: &str = "immich-rs";
pub const JELLYFIN_MUSIC_RS: &str = "jellyfin-music-rs";

fn repo(name: &str) -> String {
    format!("https://github.com/Gren-95/{name}")
}

fn installed(name: &str) -> PathBuf {
    sys::home().join(".local/bin").join(name)
}

/// The release a `releases/latest` redirect points at:
/// ".../releases/tag/v3.4.2" is "3.4.2".
pub fn parse_release_url(url: &str) -> Option<String> {
    let version = url.trim().rsplit_once("/releases/tag/v")?.1;
    (!version.is_empty() && !version.contains('/')).then(|| version.to_string())
}

/// The version in `--version` output: its last word ("3.4.2" from immich-rs,
/// "jellyfin-music-rs 0.1.0" from clap-style tools).
pub fn parse_version(out: &str) -> String {
    out.split_whitespace().last().unwrap_or_default().to_string()
}

/// The hash `sha256sum` output gives for `file`.
pub fn sum_for<'a>(sums: &'a str, file: &str) -> Option<&'a str> {
    sums.lines().find_map(|l| {
        let (hash, name) = l.split_once(char::is_whitespace)?;
        (name.trim_start_matches([' ', '*']) == file).then_some(hash)
    })
}

/// The release build for this machine.
fn asset(name: &str) -> String {
    format!("{name}-{}-linux.tar.gz", std::env::consts::ARCH)
}

fn latest(name: &str) -> Result<String, String> {
    let url = format!("{}/releases/latest", repo(name));
    let ran = sys::run(
        &Log::none(),
        "curl",
        &[
            "-sS",
            "--max-time",
            "20",
            "-o",
            "/dev/null",
            "-w",
            "%{redirect_url}",
            &url,
        ],
    )?;
    if !ran.ok() {
        return Err(format!("GitHub: {}", ran.err.trim()));
    }
    parse_release_url(&ran.out).ok_or_else(|| format!("{url} points at no release"))
}

/// None when ~/.local/bin does not hold `name`; otherwise the update, if any.
pub fn check(name: &str) -> Result<Option<Vec<Item>>, String> {
    let bin = installed(name);
    if !bin.is_file() {
        return Ok(None);
    }
    let ran = sys::run(&Log::none(), &bin.to_string_lossy(), &["--version"])?;
    let current = parse_version(&ran.out);
    let latest = latest(name)?;
    Ok(Some(if current == latest {
        Vec::new()
    } else {
        vec![Item::new(name, current, latest)]
    }))
}

/// Installs release `version`, leaving the installed copy as it was on any
/// failure.
pub fn update(log: &Log, name: &str, version: &str) -> Result<(), String> {
    let ran = sys::run(log, "mktemp", &["-d"])?;
    if !ran.ok() {
        return Err(format!("mktemp: {}", ran.tail(1)));
    }
    let dir = PathBuf::from(ran.out.trim());
    let result = download_and_install(log, &dir, name, version);
    let _ = fs::remove_dir_all(&dir);
    result
}

fn download_and_install(log: &Log, dir: &Path, name: &str, version: &str) -> Result<(), String> {
    let base = format!("{}/releases/download/v{version}", repo(name));
    let asset = asset(name);
    let tarball = dir.join(&asset);
    let sums = dir.join("SHA256SUMS");
    for (file, path) in [(asset.as_str(), &tarball), ("SHA256SUMS", &sums)] {
        let url = format!("{base}/{file}");
        expect_ok(
            log,
            "curl",
            &["-fsSL", "--max-time", "300", "-o", &path.to_string_lossy(), &url],
        )?;
    }

    let sums = fs::read_to_string(&sums).map_err(|e| format!("SHA256SUMS: {e}"))?;
    let expected = sum_for(&sums, &asset).ok_or_else(|| format!("SHA256SUMS lists no {asset}"))?;
    let hashed = expect_ok(log, "sha256sum", &[&tarball.to_string_lossy()])?;
    if hashed.split_whitespace().next() != Some(expected) {
        return Err(format!("{asset} does not match its SHA256SUMS entry"));
    }

    expect_ok(
        log,
        "tar",
        &["-xzf", &tarball.to_string_lossy(), "-C", &dir.to_string_lossy(), name],
    )?;
    let built = dir.join(name);
    let got = expect_ok(log, &built.to_string_lossy(), &["--version"])?;
    if parse_version(&got) != version {
        return Err(format!("the {version} download reports version {}", got.trim()));
    }

    // Copied next to the installed one, then renamed over it: a sync that is
    // running keeps the program it started with.
    let target = installed(name);
    let staged = target.with_file_name(format!(".{name}.new"));
    fs::copy(&built, &staged)
        .and_then(|_| fs::set_permissions(&staged, fs::Permissions::from_mode(0o755)))
        .and_then(|_| fs::rename(&staged, &target))
        .map_err(|e| {
            let _ = fs::remove_file(&staged);
            format!("could not install {}: {e}", target.display())
        })
}

/// Runs `program`; its stdout when it exits with 0.
fn expect_ok(log: &Log, program: &str, args: &[&str]) -> Result<String, String> {
    let ran = sys::run(log, program, args)?;
    if ran.ok() {
        Ok(ran.out)
    } else {
        let name = Path::new(program)
            .file_name()
            .map_or(program.into(), |n| n.to_string_lossy());
        Err(format!("{name} exited with {}: {}", ran.code, ran.tail(3)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_newest_release() {
        assert_eq!(
            parse_release_url("https://github.com/Gren-95/immich-rs/releases/tag/v3.4.2"),
            Some("3.4.2".into())
        );
        // No release yet: GitHub redirects to the release list.
        assert_eq!(parse_release_url("https://github.com/Gren-95/immich-rs/releases"), None);
        assert_eq!(parse_release_url(""), None);
    }

    #[test]
    fn reads_both_version_styles() {
        assert_eq!(parse_version("3.4.2\n"), "3.4.2");
        assert_eq!(parse_version("jellyfin-music-rs 0.1.0\n"), "0.1.0");
        assert_eq!(parse_version(""), "");
    }

    #[test]
    fn finds_the_checksum() {
        let sums = "aaa  immich-rs-aarch64-linux.tar.gz\nbbb  immich-rs-x86_64-linux.tar.gz\nccc *other.tar.gz\n";
        assert_eq!(sum_for(sums, "immich-rs-x86_64-linux.tar.gz"), Some("bbb"));
        assert_eq!(sum_for(sums, "other.tar.gz"), Some("ccc"));
        assert_eq!(sum_for(sums, "immich-rs-riscv64-linux.tar.gz"), None);
    }
}
