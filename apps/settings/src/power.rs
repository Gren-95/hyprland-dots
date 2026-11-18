//! Power panel's own part: the battery (charge, health, cycles, charge
//! limit, power, temperature, model, age), refreshed while the panel is
//! open. The panel's settings sections follow it (app.rs with_settings).

use iced::widget::Column;
use iced::{Task, widget::column};

use crate::infoview;
use crate::sysinfo::{self, Battery};
use crate::system;

#[derive(Default)]
pub struct State {
    /// None until read; Some(None) when there is no battery.
    battery: Option<Option<Battery>>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Option<Battery>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return Task::perform(system::spawn(sysinfo::battery), |b| Msg::Refreshed(b.flatten())),
            Msg::Refreshed(b) => self.battery = Some(b),
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, body: Column<'a, Msg>) -> Column<'a, Msg> {
        match &self.battery {
            Some(Some(b)) => infoview::battery(body, b),
            _ => body.push(column![]),
        }
    }
}
