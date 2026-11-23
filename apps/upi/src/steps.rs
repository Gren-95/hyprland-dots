//! The update sources, in the order they run.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Step {
    Dnf,
    /// After dnf: a new Hyprland needs its plugins rebuilt.
    Plugins,
    Firmware,
    Flatpak,
    AppImages,
    Npm,
    Uv,
    Bun,
    /// The Immich CLI the photo sync uploads with, from its GitHub releases.
    ImmichRs,
    /// The Jellyfin music sync, from its GitHub releases.
    JellyfinMusicRs,
    Fisher,
    VsCode,
    Tldr,
    /// Only says whether the dots repo is behind; never pulls.
    Dots,
}

use Step::*;

impl Step {
    pub const ALL: [Step; 14] = [
        Dnf,
        Plugins,
        Firmware,
        Flatpak,
        AppImages,
        Npm,
        Uv,
        Bun,
        ImmichRs,
        JellyfinMusicRs,
        Fisher,
        VsCode,
        Tldr,
        Dots,
    ];

    /// The name on the command line (`upi dnf flatpak`).
    pub fn id(self) -> &'static str {
        match self {
            Dnf => "dnf",
            Plugins => "plugins",
            Firmware => "firmware",
            Flatpak => "flatpak",
            AppImages => "appimages",
            Npm => "npm",
            Uv => "uv",
            Bun => "bun",
            ImmichRs => "immich-rs",
            JellyfinMusicRs => "jellyfin-music-rs",
            Fisher => "fisher",
            VsCode => "vscode",
            Tldr => "tldr",
            Dots => "dots",
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Dnf => "System packages",
            Plugins => "Hyprland plugins",
            Firmware => "Firmware",
            Flatpak => "Flatpak apps",
            AppImages => "AppImages",
            Npm => "npm globals",
            Uv => "uv tools",
            Bun => "bun",
            ImmichRs => "immich-rs",
            JellyfinMusicRs => "jellyfin-music-rs",
            Fisher => "fish plugins",
            VsCode => "VS Code extensions",
            Tldr => "tldr pages",
            Dots => "dots repo",
        }
    }

    /// The program the step needs; without it the step is passed over.
    pub fn tool(self) -> &'static str {
        match self {
            Dnf => "dnf",
            Plugins => "hyprctl",
            Firmware => "fwupdmgr",
            Flatpak | AppImages => "flatpak",
            Npm => "npm",
            Uv => "uv",
            Bun => "bun",
            ImmichRs | JellyfinMusicRs => "curl",
            Fisher => "fish",
            VsCode => "code",
            Tldr => "tldr",
            Dots => "git",
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
