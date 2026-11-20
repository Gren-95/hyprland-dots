//! Sync panel's own rows: where each sync connects, read from its own
//! configuration. The Immich server is the immich CLI's login; the Jellyfin
//! key comes from the environment or sync.conf. The app only says whether a
//! key is there: it never reads one into the window or writes one.

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::store::home;
use crate::system;
use crate::ui;

/// The immich CLI login file (paths.sh IMMICH_AUTH): its `url:` line.
pub fn parse_immich_url(auth: &str) -> String {
    auth.lines()
        .find_map(|l| l.strip_prefix("url:"))
        .map(|u| u.trim().trim_end_matches("/api").to_string())
        .unwrap_or_default()
}

/// sync.conf (shell assignments): the URL, and whether a key is set. The
/// key's value is not kept.
pub fn parse_jellyfin_conf(conf: &str) -> (String, bool) {
    let value = |key: &str| {
        conf.lines()
            .find_map(|l| l.strip_prefix(&format!("{key}=")))
            .map(|v| v.trim().trim_matches(['\'', '"']).to_string())
            .unwrap_or_default()
    };
    (value("JELLYFIN_URL"), !value("JELLYFIN_API_KEY").is_empty())
}

/// Where the Jellyfin key comes from.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum KeySource {
    #[default]
    Missing,
    Environment,
    File,
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub immich_url: String,
    pub jellyfin_url: String,
    pub jellyfin_key: KeySource,
}

fn read() -> Reading {
    let auth = std::fs::read_to_string(home().join(".config/immich/auth.yml")).unwrap_or_default();
    let conf = std::fs::read_to_string(home().join(".config/jellyfin/sync.conf")).unwrap_or_default();
    let (jellyfin_url, key_in_file) = parse_jellyfin_conf(&conf);
    let key_in_env = std::env::var_os("JELLYFIN_API_KEY").is_some_and(|k| !k.is_empty());
    Reading {
        immich_url: parse_immich_url(&auth),
        jellyfin_url,
        jellyfin_key: match (key_in_env, key_in_file) {
            (true, _) => KeySource::Environment,
            (false, true) => KeySource::File,
            _ => KeySource::Missing,
        },
    }
}

#[derive(Default)]
pub struct State {
    reading: Option<Reading>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Reading),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(read), |r| Msg::Loaded(r.unwrap_or_default())),
            Msg::Loaded(r) => self.reading = Some(r),
        }
        Task::none()
    }

    pub fn immich_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(r) = &self.reading else { return Vec::new() };
        let detail = if r.immich_url.is_empty() {
            "Not logged in: run immich login <server> <key> in a terminal".to_string()
        } else {
            format!("{} · change it with immich login", r.immich_url)
        };
        vec![ui::item(ico::SERVER, "Server".into(), detail, vec![])]
    }

    pub fn jellyfin_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(r) = &self.reading else { return Vec::new() };
        let detail = match r.jellyfin_key {
            KeySource::Environment => "Set, from JELLYFIN_API_KEY in the environment",
            KeySource::File => "Set, in ~/.config/jellyfin/sync.conf",
            KeySource::Missing => "Missing: set JELLYFIN_API_KEY, or run the sync once in a terminal",
        };
        let mut rows = vec![ui::item(ico::KEY_ROUND, "API key".into(), detail.into(), vec![])];
        if !r.jellyfin_url.is_empty() {
            rows.push(ui::item(
                ico::SERVER,
                "Server in sync.conf".into(),
                format!("{} · used while the server address above is empty", r.jellyfin_url),
                vec![],
            ));
        }
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_where_syncs_connect() {
        assert_eq!(
            parse_immich_url("url: http://192.168.0.200:2283/api\nkey: secret\n"),
            "http://192.168.0.200:2283"
        );
        assert_eq!(parse_immich_url(""), "");
        assert_eq!(
            parse_jellyfin_conf("JELLYFIN_URL=https://jf.example\nJELLYFIN_API_KEY=abc\n"),
            ("https://jf.example".to_string(), true)
        );
        assert_eq!(
            parse_jellyfin_conf("JELLYFIN_URL=''\nJELLYFIN_API_KEY=''\n"),
            (String::new(), false)
        );
    }
}
