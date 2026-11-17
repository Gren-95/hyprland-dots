//! Command line: `settings [-p|--panel <name>] [-s|--search <text>] [--list-panels] [-h|--help]`.

use crate::schema::{PANELS, panel_index};

#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    /// Open the window on this panel (index into PANELS), with this text in
    /// the search field.
    Open {
        panel: usize,
        search: String,
    },
    ListPanels,
    Help,
}

pub fn usage() -> String {
    let names: Vec<_> = PANELS.iter().map(|p| p.id).collect();
    format!(
        "Usage: settings [-p|--panel <name>] [-s|--search <text>] [--list-panels] [-h|--help]\n\n\
         Opens the settings app, on the given panel if one is named, or with\n\
         the settings matching a search.\n\
         Panels: {}\n",
        names.join(", ")
    )
}

/// Parse the arguments after the program name.
pub fn parse<I: IntoIterator<Item = String>>(args: I) -> Result<Command, String> {
    let mut panel = 0;
    let mut search = String::new();
    let mut args = args.into_iter();
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
            }
            _ => {
                if let Some(name) = arg.strip_prefix("--panel=") {
                    panel = find_panel(name)?;
                } else if let Some(text) = arg.strip_prefix("--search=") {
                    search = text.to_string();
                } else {
                    return Err(format!("unknown argument: {arg}"));
                }
            }
        }
    }
    Ok(Command::Open { panel, search })
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
                search: String::new()
            })
        );
    }

    #[test]
    fn opens_a_named_panel() {
        let notifications = panel_index("notifications").unwrap();
        let open = Ok(Command::Open {
            panel: notifications,
            search: String::new(),
        });
        assert_eq!(run(&["-p", "notifications"]), open);
        assert_eq!(run(&["--panel", "notifications"]), open);
        assert_eq!(run(&["--panel=notifications"]), open);
    }

    #[test]
    fn opens_with_a_search() {
        let open = Ok(Command::Open {
            panel: 0,
            search: "volume step".to_string(),
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
