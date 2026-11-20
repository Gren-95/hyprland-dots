//! Settings app for the Hyprland dots. See apps/settings/README.md.

mod about;
mod airpods;
mod app;
mod appearance;
mod args;
mod audio;
mod backup;
mod bluetooth;
mod calendar;
mod cli;
mod controls;
mod defaultapps;
mod focus;
mod fonts;
mod gaming;
mod hiddenapps;
mod hypr;
mod hyprpage;
mod idle;
mod infocache;
mod infoview;
mod keyboard;
mod keysearch;
mod memory;
mod mouse;
mod network;
mod notifapps;
mod ocr;
mod placement;
mod power;
mod proton;
mod reveal;
mod schema;
mod search;
mod services;
mod sharing;
mod shortcuts;
mod sidebar;
mod startup;
mod store;
mod style;
mod sync;
mod sysinfo;
mod system;
mod sysunits;
mod tailscale;
mod themes;
mod ui;
mod units;
mod vnc;
mod vpn;
mod windowrules;
mod windows;

use std::process::ExitCode;

use app::App;
use args::Command;
use store::Store;

fn main() -> ExitCode {
    let (panel, search) = match args::parse(std::env::args().skip(1)) {
        Ok(Command::Open { panel, search }) => (panel, search),
        Ok(Command::ListPanels) => {
            for p in schema::PANELS {
                println!("{}\t{}", p.id, p.title);
            }
            return ExitCode::SUCCESS;
        }
        Ok(Command::Get(key)) => {
            return report(cli::get(&Store::new(Store::default_dir()), key.as_deref()).map(|out| print!("{out}")));
        }
        Ok(Command::Set(key, value)) => {
            return report(cli::set(&Store::new(Store::default_dir()), &key, &value));
        }
        Ok(Command::Export(file)) => {
            return report(backup::export_to(std::path::Path::new(&file), &Store::default_dir()));
        }
        Ok(Command::Import(file)) => return report(cli::import(std::path::Path::new(&file))),
        Ok(Command::Help) => {
            print!("{}", args::usage());
            return ExitCode::SUCCESS;
        }
        Err(e) => {
            eprintln!("settings: {e}");
            eprint!("{}", args::usage());
            return ExitCode::from(2);
        }
    };

    let result = iced::application(
        move || App::new(panel, search.clone(), Store::new(Store::default_dir())),
        App::update,
        App::view,
    )
    .title(App::title)
    .theme(App::theme)
    .subscription(App::subscription)
    .default_font(style::FONT)
    .window(iced::window::Settings {
        size: iced::Size::new(1000.0, 680.0),
        // Wayland app id: matches dots-settings.desktop for the icon and name.
        platform_specific: iced::window::settings::PlatformSpecific {
            application_id: "dots-settings".to_string(),
            ..Default::default()
        },
        ..Default::default()
    })
    .run();
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("settings: {e}");
            ExitCode::FAILURE
        }
    }
}

/// Exit status for a command-line action: errors go to stderr, exit 1.
fn report(result: Result<(), String>) -> ExitCode {
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("settings: {e}");
            ExitCode::FAILURE
        }
    }
}
