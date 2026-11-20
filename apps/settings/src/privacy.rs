//! Privacy panel's own rows: clear the clipboard history (`cliphist wipe`)
//! and the recent files list (~/.local/share/recently-used.xbel, which GTK
//! apps read and write). Each asks once more before it clears.

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::store::home;
use crate::system::{self, args};
use crate::ui;

/// An empty recent files list, as GTK writes one.
const EMPTY_XBEL: &str = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xbel version=\"1.0\"\n      xmlns:bookmark=\"http://www.freedesktop.org/standards/desktop-bookmarks\"\n      xmlns:mime=\"http://www.freedesktop.org/standards/shared-mime-info\"\n>\n</xbel>\n";

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum What {
    Clipboard,
    Recent,
}

#[derive(Default)]
pub struct State {
    confirming: Option<What>,
    busy: bool,
    note: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Clear(What),
    Done(What, Result<(), String>),
}

fn clear_recent() -> Result<(), String> {
    let path = home().join(".local/share/recently-used.xbel");
    let tmp = path.with_extension("xbel.tmp");
    std::fs::write(&tmp, EMPTY_XBEL)
        .and_then(|()| std::fs::rename(&tmp, &path))
        .map_err(|e| format!("Could not clear the recent files: {e}"))
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Clear(what) if self.confirming != Some(what) => {
                self.confirming = Some(what);
                self.note = None;
            }
            Msg::Clear(what) => {
                self.confirming = None;
                self.busy = true;
                return match what {
                    What::Clipboard => Task::perform(system::run("cliphist", args(&["wipe"]), None), |r| {
                        Msg::Done(What::Clipboard, r.map(|_| ()))
                    }),
                    What::Recent => Task::perform(system::spawn(clear_recent), |r| {
                        Msg::Done(
                            What::Recent,
                            r.unwrap_or_else(|| Err("clearing stopped unexpectedly".into())),
                        )
                    }),
                };
            }
            Msg::Done(what, r) => {
                self.busy = false;
                match r {
                    Ok(()) => {
                        self.error = None;
                        self.note = Some(
                            match what {
                                What::Clipboard => "Clipboard history cleared",
                                What::Recent => "Recent files cleared",
                            }
                            .into(),
                        );
                    }
                    Err(e) => self.error = Some(e),
                }
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if let Some(n) = &self.note {
            rows.push(ui::note(n.clone()));
        }
        for (what, glyph, title, detail) in [
            (
                What::Clipboard,
                ico::CLIPBOARD_X,
                "Clear clipboard history",
                "Copied text and images",
            ),
            (
                What::Recent,
                ico::FILE_CLOCK,
                "Clear recent files",
                "Apps' recent files list",
            ),
        ] {
            let asking = self.confirming == Some(what);
            rows.push(ui::item(
                glyph,
                title.into(),
                if asking {
                    "Cannot be undone".into()
                } else {
                    detail.into()
                },
                vec![ui::confirm_action(
                    ico::ERASER,
                    title,
                    asking,
                    (!self.busy).then_some(Msg::Clear(what)),
                )],
            ));
        }
        rows
    }
}
