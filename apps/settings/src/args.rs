//! Command line: `settings [-p|--panel <name>] [-s|--search <text>] [--list-panels] [-h|--help]`.

use crate::schema::{PANELS, SHORTCUTS, panel_index};

#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    /// Open the window on this panel (index into PANELS), with this text in
    /// the search field; `shortcuts` opens the key binds page of Keyboard
    /// (`-p shortcuts`).
    Open {
        panel: usize,
        search: String,
        shortcuts: bool,
    },
    ListPanels,
    /// Print every setting, or one.
    Get(Option<String>),
    /// Change one setting.
    Set(String, String),
    /// Write every setting to a file.
    Export(String),
    /// Read settings back from a file, after showing what changes.
    Import(String),
    Help,
}

pub fn usage() -> String {
    let names: Vec<_> = PANELS.iter().map(|p| p.id).collect();
    format!(
        "Usage: settings [-p|--panel <name>] [-s|--search <text>] [--list-panels] [-h|--help]\n\
         \x20      settings get [key]\n\
         \x20      settings set <key> <value>\n\
         \x20      settings export <file> | settings import <file>\n\n\
         Opens the settings app, on the given panel if one is named, or with\n\
         the settings matching a search. get prints settings as key and value,\n\
         set changes one (true/false, a number, one of the choices, or JSON).\n\
         export writes every setting (shell, Hyprland, default apps) to a\n\
         file; import lists what it would change and asks first.\n\
         Panels: {}, {SHORTCUTS} (the key binds, in Keyboard)\n",
        names.join(", ")
    )
}

/// Parse the arguments after the program name.
pub fn parse<I: IntoIterator<Item = String>>(args: I) -> Result<Command, String> {
    let mut panel = 0;
    let mut shortcuts = false;
    let mut search = String::new();
    let mut args = args.into_iter().peekable();
    match args.peek().map(String::as_str) {
        Some("get") => {
            args.next();
            let key = args.next();
            return match args.next() {
                Some(extra) => Err(format!("get takes one key, got also {extra}")),
                None => Ok(Command::Get(key)),
            };
        }
        Some(verb @ ("export" | "import")) => {
            let verb = verb.to_string();
            args.next();
            let (Some(file), None) = (args.next(), args.next()) else {
                return Err(format!("{verb} needs one file"));
            };
            return Ok(if verb == "export" {
                Command::Export(file)
            } else {
                Command::Import(file)
            });
        }
        Some("set") => {
            args.next();
            let (Some(key), Some(value), None) = (args.next(), args.next(), args.next()) else {
                return Err("set needs a key and a value".into());
            };
            return Ok(Command::Set(key, value));
        }
        _ => {}
    }
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            "--list-panels" => return Ok(Command::ListPanels),
            "-s" | "--search" => {
                search = args
                    .next()
                    .ok_or_else(|| format!("{arg} needs the text to search for"))?
            }
            "-p" | "--panel" => {
                let name = args.next().ok_or_else(|| format!("{arg} needs a panel name"))?;
                panel = find_panel(&name)?;
                shortcuts = name == SHORTCUTS;
            }
            _ => {
                if let Some(name) = arg.strip_prefix("--panel=") {
                    panel = find_panel(name)?;
                    shortcuts = name == SHORTCUTS;
                } else if let Some(text) = arg.strip_prefix("--search=") {
                    search = text.to_string();
                } else {
                    return Err(format!("unknown argument: {arg}"));
                }
            }
        }
    }
    Ok(Command::Open {
        panel,
        search,
        shortcuts,
    })
}

fn find_panel(name: &str) -> Result<usize, String> {
    panel_index(name).ok_or_else(|| format!("unknown panel: {name} (see --list-panels)"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Result<Command, String> {
        parse(args.iter().map(|s| s.to_string()))
    }

    #[test]
    fn opens_the_first_panel_by_default() {
        assert_eq!(
            run(&[]),
            Ok(Command::Open {
                panel: 0,
                search: String::new(),
                shortcuts: false
            })
        );
    }

    #[test]
    fn opens_a_named_panel() {
        let notifications = panel_index("notifications").unwrap();
        let open = Ok(Command::Open {
            panel: notifications,
            search: String::new(),
            shortcuts: false,
        });
        assert_eq!(run(&["-p", "notifications"]), open);
        assert_eq!(run(&["--panel", "notifications"]), open);
        assert_eq!(run(&["--panel=notifications"]), open);
    }

    #[test]
    fn parses_get_and_set() {
        assert_eq!(run(&["get"]), Ok(Command::Get(None)));
        assert_eq!(run(&["get", "bar-height"]), Ok(Command::Get(Some("bar-height".into()))));
        assert_eq!(
            run(&["set", "bar-height", "40"]),
            Ok(Command::Set("bar-height".into(), "40".into()))
        );
        assert!(run(&["set", "bar-height"]).is_err());
        assert!(run(&["set", "a", "b", "c"]).is_err());
        assert!(run(&["get", "a", "b"]).is_err());
    }

    #[test]
    fn parses_export_and_import() {
        assert_eq!(run(&["export", "a.json"]), Ok(Command::Export("a.json".into())));
        assert_eq!(run(&["import", "a.json"]), Ok(Command::Import("a.json".into())));
        assert!(run(&["export"]).is_err());
        assert!(run(&["import", "a", "b"]).is_err());
    }

    #[test]
    fn old_panel_names_still_open() {
        let clock = panel_index("datetime").unwrap();
        assert_eq!(
            run(&["-p", "weather"]),
            Ok(Command::Open {
                panel: clock,
                search: String::new(),
                shortcuts: false
            })
        );
    }

    #[test]
    fn opens_the_key_binds_page() {
        assert_eq!(
            run(&["-p", "shortcuts"]),
            Ok(Command::Open {
                panel: panel_index("keyboard").unwrap(),
                search: String::new(),
                shortcuts: true
            })
        );
    }

    #[test]
    fn opens_with_a_search() {
        let open = Ok(Command::Open {
            panel: 0,
            search: "volume step".to_string(),
            shortcuts: false,
        });
        assert_eq!(run(&["-s", "volume step"]), open);
        assert_eq!(run(&["--search", "volume step"]), open);
        assert_eq!(run(&["--search=volume step"]), open);
    }

    #[test]
    fn rejects_bad_input() {
        assert!(run(&["-p"]).unwrap_err().contains("needs a panel name"));
        assert!(run(&["-s"]).unwrap_err().contains("needs the text"));
        assert!(
            run(&["-p", "frobnicator"])
                .unwrap_err()
                .contains("unknown panel: frobnicator")
        );
        assert!(run(&["--frobnicate"]).unwrap_err().contains("unknown argument"));
    }

    #[test]
    fn lists_panels_and_help() {
        assert_eq!(run(&["--list-panels"]), Ok(Command::ListPanels));
        assert_eq!(run(&["-h"]), Ok(Command::Help));
        assert!(usage().contains("notifications"));
    }
}
