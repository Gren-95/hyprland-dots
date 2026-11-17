//! Settings app for the Hyprland dots. See apps/settings/README.md.

mod app;
mod args;
mod controls;
mod reveal;
mod schema;
mod search;
mod sidebar;
mod store;
mod style;

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
