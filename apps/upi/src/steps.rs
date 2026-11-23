//! The update sources, in the order they run.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Step {
    Dnf,
    Firmware,
    Flatpak,
    AppImages,
    Npm,
    Uv,
    Bun,
    Fisher,
}

use Step::*;

impl Step {
    pub const ALL: [Step; 8] = [Dnf, Firmware, Flatpak, AppImages, Npm, Uv, Bun, Fisher];

    /// The name on the command line (`upi dnf flatpak`).
    pub fn id(self) -> &'static str {
        match self {
            Dnf => "dnf",
            Firmware => "firmware",
            Flatpak => "flatpak",
            AppImages => "appimages",
            Npm => "npm",
            Uv => "uv",
            Bun => "bun",
            Fisher => "fisher",
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Dnf => "System packages",
            Firmware => "Firmware",
            Flatpak => "Flatpak apps",
            AppImages => "AppImages",
            Npm => "npm globals",
            Uv => "uv tools",
            Bun => "bun",
            Fisher => "fish plugins",
        }
    }

    /// The program the step needs; without it the step is passed over.
    pub fn tool(self) -> &'static str {
        match self {
            Dnf => "dnf",
            Firmware => "fwupdmgr",
            Flatpak | AppImages => "flatpak",
            Npm => "npm",
            Uv => "uv",
            Bun => "bun",
            Fisher => "fish",
        }
    }

    /// Runs commands with sudo, so the password is asked before the run.
    pub fn needs_sudo(self) -> bool {
        matches!(self, Dnf | Firmware)
    }

    pub fn from_id(id: &str) -> Option<Step> {
        Step::ALL.into_iter().find(|s| s.id() == id)
    }
}
