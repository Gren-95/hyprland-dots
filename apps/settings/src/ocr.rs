//! The languages screenshot text recognition reads (screenshot-ocr.sh), on
//! the Screenshots & recording panel: a switch tree of the Tesseract
//! languages installed. Stored as "eng+est" in ocr-languages; unset means
//! every installed language.

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::store::{Kind, Store, Value};
use crate::system::{self, args};
use crate::ui;

const FILE: &str = "ocr-languages";

/// Names for the common Tesseract language codes; others show their code.
const NAMES: &[(&str, &str)] = &[
    ("ara", "Arabic"),
    ("ces", "Czech"),
    ("chi_sim", "Chinese (simplified)"),
    ("chi_tra", "Chinese (traditional)"),
    ("dan", "Danish"),
    ("deu", "German"),
    ("ell", "Greek"),
    ("eng", "English"),
    ("est", "Estonian"),
    ("fin", "Finnish"),
    ("fra", "French"),
    ("heb", "Hebrew"),
    ("hin", "Hindi"),
    ("hun", "Hungarian"),
    ("ita", "Italian"),
    ("jpn", "Japanese"),
    ("kor", "Korean"),
    ("lav", "Latvian"),
    ("lit", "Lithuanian"),
    ("nld", "Dutch"),
    ("nor", "Norwegian"),
    ("pol", "Polish"),
    ("por", "Portuguese"),
    ("ron", "Romanian"),
    ("rus", "Russian"),
    ("spa", "Spanish"),
    ("swe", "Swedish"),
    ("tur", "Turkish"),
    ("ukr", "Ukrainian"),
];

/// `tesseract --list-langs`: the codes after the heading line, without the
/// script detection data (osd), which is not a language.
pub fn parse_langs(out: &str) -> Vec<String> {
    out.lines()
        .skip_while(|l| !l.starts_with("List of available languages"))
        .skip(1)
        .map(str::trim)
        .filter(|l| !l.is_empty() && *l != "osd")
        .map(String::from)
        .collect()
}

pub fn name(code: &str) -> String {
    NAMES
        .iter()
        .find(|(c, _)| *c == code)
        .map_or_else(|| code.to_string(), |(_, n)| n.to_string())
}

/// The chosen languages that are installed; all of them when none is
/// chosen.
pub fn chosen(stored: &str, installed: &[String]) -> Vec<String> {
    let picked: Vec<String> = stored
        .split('+')
        .filter(|c| installed.iter().any(|i| i == c))
        .map(String::from)
        .collect();
    if picked.is_empty() { installed.to_vec() } else { picked }
}

fn store() -> Store {
    Store::new(Store::default_dir())
}

fn stored() -> String {
    match store().read(FILE, Kind::Text) {
        Some(Value::Text(t)) => t.trim().to_string(),
        _ => String::new(),
    }
}

/// The installed languages; Err says why there are none to read.
fn load() -> Result<Vec<String>, String> {
    let out = system::run_blocking("tesseract", &args(&["--list-langs"]), None).map_err(|e| {
        if e.starts_with("could not run") {
            "Tesseract is not installed, so text cannot be read from screenshots".to_string()
        } else {
            format!("Tesseract could not list its languages: {e}")
        }
    })?;
    let langs = parse_langs(&out);
    if langs.is_empty() {
        return Err("No Tesseract language is installed (for English: tesseract-langpack-eng)".into());
    }
    Ok(langs)
}

#[derive(Default)]
pub struct State {
    /// Installed codes; None until read, empty without Tesseract.
    installed: Option<Vec<String>>,
    /// Their names, in the same order.
    names: Vec<String>,
    chosen: Vec<String>,
    open: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Result<Vec<String>, String>),
    Toggle,
    Flip(String),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                return Task::perform(system::spawn(load), |l| {
                    Msg::Loaded(l.unwrap_or_else(|| Err("Reading the languages stopped unexpectedly".into())))
                });
            }
            Msg::Loaded(Err(e)) => {
                self.installed = Some(Vec::new());
                self.error = Some(e);
            }
            Msg::Loaded(Ok(langs)) => {
                self.error = None;
                self.chosen = chosen(&stored(), &langs);
                self.names = langs.iter().map(|c| name(c)).collect();
                self.installed = Some(langs);
            }
            Msg::Toggle => self.open = !self.open,
            Msg::Flip(code) => {
                let installed = self.installed.clone().unwrap_or_default();
                let mut next: Vec<String> = installed
                    .iter()
                    .filter(|c| (**c == code) != self.chosen.contains(c))
                    .cloned()
                    .collect();
                if next.is_empty() {
                    next = self.chosen.clone();
                }
                match store().write(FILE, &Value::Text(next.join("+"))) {
                    Ok(()) => {
                        self.chosen = next;
                        self.error = None;
                    }
                    Err(e) => self.error = Some(format!("Could not save: {e}")),
                }
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(installed) = &self.installed else {
            return vec![ui::note("Looking…")];
        };
        if installed.is_empty() {
            return vec![ui::note(self.error.clone().unwrap_or_default())];
        }
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        // The last language on cannot be switched off: OCR needs one.
        let last = self.chosen.len() == 1;
        let items: Vec<(&str, bool, Option<Msg>)> = installed
            .iter()
            .zip(&self.names)
            .map(|(code, label)| {
                let on = self.chosen.contains(code);
                let flip = (!(on && last)).then(|| Msg::Flip(code.clone()));
                (label.as_str(), on, flip)
            })
            .collect();
        rows.push(ui::item(
            ico::SCAN_TEXT,
            "Languages".into(),
            "More: tesseract-langpack packages".into(),
            vec![ui::switch_tree_head(&items, self.open, Msg::Toggle)],
        ));
        if self.open {
            rows.extend(ui::switch_rows(items));
        }
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_installed_languages() {
        let out = "List of available languages in \"/usr/share/tesseract/tessdata/\" (3):\neng\nest\nosd\n";
        assert_eq!(parse_langs(out), ["eng", "est"]);
        assert!(parse_langs("tesseract: command not found").is_empty());
    }

    #[test]
    fn keeps_installed_choices_or_all() {
        let installed = vec!["eng".to_string(), "est".to_string()];
        assert_eq!(chosen("est+deu", &installed), ["est"]);
        assert_eq!(chosen("", &installed), installed);
        assert_eq!(chosen("deu", &installed), installed);
        assert_eq!(name("est"), "Estonian");
        assert_eq!(name("xyz"), "xyz");
    }
}
