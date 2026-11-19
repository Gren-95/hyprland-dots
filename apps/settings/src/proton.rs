//! Proton versions on the Gaming panel, collapsed by default: the
//! compatibility tools Steam has (GE-Proton and others in
//! compatibilitytools.d, Valve's Proton in the libraries), which one is the
//! default and how many installed games use each (CompatToolMapping in
//! config.vdf), versions installed games are set to that are no longer
//! installed, and on request
//! the newest GE-Proton release on GitHub.

use std::path::{Path, PathBuf};

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

const GE_RELEASES: &str = "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest";
const PROTONPLUS: &str = "com.vysp3r.ProtonPlus";

/// An installed compatibility tool.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Tool {
    /// The name Steam's settings use ("GE-Proton11-12-x86_64", "proton_hotfix").
    pub internal: String,
    /// Its folder name ("GE-Proton11-12", "Proton Hotfix").
    pub name: String,
    /// When it was built, from its version file: "2026-10-28".
    pub built: String,
}

#[derive(Debug, Clone, Default)]
pub struct Tools {
    pub installed: Vec<Tool>,
    /// (app id, tool name): "0" is the default for every game.
    pub mappings: Vec<(String, String)>,
}

impl Tools {
    pub fn default_tool(&self) -> Option<&str> {
        self.mappings
            .iter()
            .find(|(app, _)| app == "0")
            .map(|(_, t)| t.as_str())
    }

    /// Games set to `tool` (the default entry not counted).
    pub fn games_using(&self, tool: &str) -> usize {
        self.mappings.iter().filter(|(app, t)| app != "0" && t == tool).count()
    }

    /// Tools games are set to that are not installed, with how many games.
    pub fn missing(&self) -> Vec<(String, usize)> {
        let mut names: Vec<String> = self
            .mappings
            .iter()
            .map(|(_, t)| t.clone())
            .filter(|t| !self.installed.iter().any(|i| &i.internal == t))
            .collect();
        names.sort();
        names.dedup();
        names.into_iter().map(|n| (n.clone(), self.games_using(&n))).collect()
    }
}

/// The CompatToolMapping entries of Steam's config.vdf: (app id, name).
pub fn parse_mappings(vdf: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut lines = vdf.lines().map(str::trim).skip_while(|l| *l != "\"CompatToolMapping\"");
    if lines.next().is_none() {
        return out;
    }
    let (mut depth, mut app) = (0, String::new());
    for line in lines {
        match line {
            "{" => depth += 1,
            "}" => {
                depth -= 1;
                if depth == 0 {
                    break;
                }
            }
            _ => {
                let words: Vec<&str> = line.split('"').skip(1).step_by(2).collect();
                match words.as_slice() {
                    [key] if depth == 1 => app = key.to_string(),
                    ["name", value] if depth == 2 && !value.is_empty() => out.push((app.clone(), value.to_string())),
                    _ => {}
                }
            }
        }
    }
    out
}

/// The tool name a compatibilitytool.vdf declares (first key under
/// "compat_tools").
pub fn parse_tool_name(vdf: &str) -> Option<String> {
    let mut lines = vdf.lines().map(|l| l.split("//").next().unwrap_or_default().trim());
    lines.find(|l| *l == "\"compat_tools\"")?;
    lines
        .filter(|l| *l != "{")
        .find_map(|l| l.split('"').nth(1).map(String::from))
        .filter(|n| !n.is_empty())
}

/// Valve's internal name for a Proton folder: "Proton 9.0" -> proton_9,
/// "Proton - Experimental" -> proton_experimental, "Proton Hotfix" ->
/// proton_hotfix.
pub fn valve_name(folder: &str) -> String {
    let rest = folder
        .trim_start_matches("Proton")
        .trim()
        .trim_start_matches('-')
        .trim();
    let key = rest
        .split('.')
        .next()
        .unwrap_or_default()
        .to_lowercase()
        .replace(' ', "_");
    format!("proton_{key}")
}

/// A Unix time as "YYYY-MM-DD" (UTC).
pub fn date(secs: u64) -> String {
    // Days to civil date (Howard Hinnant's algorithm).
    let z = (secs / 86400) as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

/// The build date in a version file ("1793687165 GE-Proton11-12").
fn built(dir: &Path) -> String {
    std::fs::read_to_string(dir.join("version"))
        .ok()
        .and_then(|v| v.split_whitespace().next()?.parse().ok())
        .map(date)
        .unwrap_or_default()
}

fn steam_dir() -> PathBuf {
    crate::store::home().join(".local/share/Steam")
}

/// Every Steam library folder (libraryfolders.vdf "path" entries).
fn libraries() -> Vec<PathBuf> {
    let vdf = std::fs::read_to_string(steam_dir().join("steamapps/libraryfolders.vdf")).unwrap_or_default();
    vdf.lines()
        .filter_map(|l| {
            let words: Vec<&str> = l.split('"').skip(1).step_by(2).collect();
            match words.as_slice() {
                ["path", p] => Some(PathBuf::from(p)),
                _ => None,
            }
        })
        .collect()
}

/// App ids with an appmanifest_<id>.acf in any library.
fn installed_games() -> Vec<String> {
    libraries()
        .iter()
        .flat_map(|lib| std::fs::read_dir(lib.join("steamapps")).into_iter().flatten().flatten())
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            name.strip_prefix("appmanifest_")?
                .strip_suffix(".acf")
                .map(String::from)
        })
        .collect()
}

fn subdirs(dir: &Path) -> Vec<PathBuf> {
    let mut list: Vec<PathBuf> = std::fs::read_dir(dir)
        .map(|e| e.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect())
        .unwrap_or_default();
    list.sort();
    list
}

fn load() -> Tools {
    let mut installed = Vec::new();
    for dir in subdirs(&steam_dir().join("compatibilitytools.d")) {
        let name = dir.file_name().unwrap_or_default().to_string_lossy().into_owned();
        let vdf = std::fs::read_to_string(dir.join("compatibilitytool.vdf")).unwrap_or_default();
        let internal = parse_tool_name(&vdf).unwrap_or_else(|| name.clone());
        installed.push(Tool {
            internal,
            built: built(&dir),
            name,
        });
    }
    for library in libraries() {
        for dir in subdirs(&library.join("steamapps/common")) {
            let name = dir.file_name().unwrap_or_default().to_string_lossy().into_owned();
            if name.starts_with("Proton") && dir.join("proton").is_file() {
                installed.push(Tool {
                    internal: valve_name(&name),
                    built: built(&dir),
                    name,
                });
            }
        }
    }
    let config = std::fs::read_to_string(steam_dir().join("config/config.vdf")).unwrap_or_default();
    // Steam keeps the setting of games that were uninstalled; only the
    // default and installed games count.
    let games = installed_games();
    let mappings = parse_mappings(&config)
        .into_iter()
        .filter(|(app, _)| app == "0" || games.contains(app))
        .collect();
    Tools { installed, mappings }
}

/// The tag of GE-Proton's latest release, from the GitHub API JSON.
pub fn parse_latest(json: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    v["tag_name"].as_str().map(String::from)
}

fn latest_ge() -> Result<String, String> {
    let json = system::run_blocking("curl", &args(&["-fsSL", "--max-time", "10", GE_RELEASES]), None)
        .map_err(|_| "Could not reach GitHub".to_string())?;
    parse_latest(&json).ok_or_else(|| "GitHub sent no release".to_string())
}

#[derive(Default)]
pub struct State {
    tools: Option<Tools>,
    open: bool,
    /// The newest GE-Proton once checked, or why it could not be.
    latest: Option<Result<String, String>>,
    checking: bool,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Tools),
    Toggle,
    Check,
    Checked(Result<String, String>),
    OpenProtonPlus,
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(load), |t| Msg::Loaded(t.unwrap_or_default())),
            Msg::Loaded(t) => self.tools = Some(t),
            Msg::Toggle => self.open = !self.open,
            Msg::Check => {
                self.checking = true;
                return Task::perform(system::spawn(latest_ge), |r| {
                    Msg::Checked(r.unwrap_or_else(|| Err("checking stopped unexpectedly".into())))
                });
            }
            Msg::Checked(r) => {
                self.checking = false;
                self.latest = Some(r);
            }
            Msg::OpenProtonPlus => {
                return Task::perform(system::run("gtk-launch", vec![PROTONPLUS.into()], None), |_| Msg::Load);
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(tools) = &self.tools else {
            return vec![ui::note("Looking for Proton…")];
        };
        let default = tools.default_tool().unwrap_or("");
        let shown_default = tools
            .installed
            .iter()
            .find(|t| t.internal == default)
            .map_or(default, |t| t.name.as_str());
        let summary = match (tools.installed.len(), shown_default.is_empty()) {
            (0, _) => "None installed".to_string(),
            (n, true) => format!("{n} installed"),
            (n, false) => format!("Default {shown_default} · {n} installed"),
        };
        let mut rows = vec![ui::item(
            ico::LAYERS,
            "Proton versions".into(),
            summary,
            vec![ui::disclosure(self.open, Msg::Toggle)],
        )];
        if !self.open {
            return rows;
        }
        for tool in &tools.installed {
            let mut detail = Vec::new();
            if !tool.built.is_empty() {
                detail.push(format!("Built {}", tool.built));
            }
            if tool.internal == default {
                detail.push("Default".into());
            }
            let games = tools.games_using(&tool.internal);
            if games > 0 {
                detail.push(format!("{games} game{}", if games == 1 { "" } else { "s" }));
            }
            rows.push(ui::item(ico::BOX, tool.name.clone(), detail.join(" · "), vec![]));
        }
        for (name, games) in tools.missing() {
            let detail = format!(
                "Not installed · set for {games} game{}",
                if games == 1 { "" } else { "s" }
            );
            rows.push(ui::item(ico::TRIANGLE_EXCLAMATION_POINT, name, detail, vec![]));
        }
        let latest = match (&self.latest, self.checking) {
            (_, true) => "Checking GitHub…".to_string(),
            (None, _) => "Newest GE-Proton release".to_string(),
            (Some(Ok(tag)), _) if tools.installed.iter().any(|t| &t.name == tag) => format!("{tag} · installed"),
            (Some(Ok(tag)), _) => format!("{tag} · not installed"),
            (Some(Err(e)), _) => e.clone(),
        };
        rows.push(ui::item(
            ico::DOWNLOAD,
            "GE-Proton".into(),
            latest,
            vec![ui::button_group(vec![
                ("Check", (!self.checking).then_some(Msg::Check), Action::Normal),
                ("ProtonPlus", Some(Msg::OpenProtonPlus), Action::Normal),
            ])],
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONFIG: &str = "\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n\t\t\t\t\t\"0\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"GE-Proton11-12-x86_64\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t}\n\t\t\t\t\t\"489830\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"GE-Proton10-34\"\n\t\t\t\t\t}\n\t\t\t\t\t\"559650\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"GE-Proton9-25\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t\t\"Other\"\t\t\"1\"\n";

    #[test]
    fn reads_tool_mappings() {
        let m = parse_mappings(CONFIG);
        assert_eq!(m.len(), 3);
        assert_eq!(m[0], ("0".into(), "GE-Proton11-12-x86_64".into()));
        let tools = Tools {
            installed: vec![
                Tool {
                    internal: "GE-Proton11-12-x86_64".into(),
                    name: "GE-Proton11-12".into(),
                    built: String::new(),
                },
                Tool {
                    internal: "GE-Proton10-34".into(),
                    name: "GE-Proton10-34".into(),
                    built: String::new(),
                },
            ],
            mappings: m,
        };
        assert_eq!(tools.default_tool(), Some("GE-Proton11-12-x86_64"));
        assert_eq!(tools.games_using("GE-Proton10-34"), 1);
        assert_eq!(tools.missing(), [("GE-Proton9-25".to_string(), 1)]);
    }

    #[test]
    fn reads_tool_names() {
        let vdf = "\"compatibilitytools\"\n{\n  \"compat_tools\"\n  {\n    \"GE-Proton11-12-x86_64\" // Internal name of this tool\n    {\n";
        assert_eq!(parse_tool_name(vdf).as_deref(), Some("GE-Proton11-12-x86_64"));
        assert_eq!(valve_name("Proton Hotfix"), "proton_hotfix");
        assert_eq!(valve_name("Proton 9.0"), "proton_9");
        assert_eq!(valve_name("Proton - Experimental"), "proton_experimental");
    }

    #[test]
    fn dates_and_releases() {
        assert_eq!(date(1_793_687_165), "2026-11-03");
        assert_eq!(date(0), "1970-01-01");
        assert_eq!(
            parse_latest(r#"{"tag_name":"GE-Proton11-13"}"#).as_deref(),
            Some("GE-Proton11-13")
        );
        assert_eq!(parse_latest("{}"), None);
    }
}
