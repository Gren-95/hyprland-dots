//! Date & time panel's own rows: the time zone (picked from
//! `timedatectl list-timezones`) and network time, set through timedatectl,
//! which asks polkit for the password; and date format presets, each shown
//! as today's date in it, beside the typed format (a store setting).

use iced::widget::container;
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::app::Message;
use crate::store::Value;
use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// Qt date formats offered as presets.
pub const DATE_PRESETS: &[&str] = &[
    "ddd, dd MMM",
    "ddd d MMMM",
    "dd.MM.yyyy",
    "yyyy-MM-dd",
    "MM/dd/yyyy",
    "d MMM yyyy",
];

const DAYS: [&str; 7] = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
];
const MONTHS: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];

/// A date: year, month (1-12), day (1-31), weekday (1 = Monday).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Day {
    pub year: i32,
    pub month: u32,
    pub day: u32,
    pub weekday: u32,
}

/// `date '+%Y %m %d %u'`.
pub fn parse_day(out: &str) -> Option<Day> {
    let f: Vec<&str> = out.split_whitespace().collect();
    let [y, m, d, w] = f.as_slice() else { return None };
    Some(Day {
        year: y.parse().ok()?,
        month: m.parse().ok()?,
        day: d.parse().ok()?,
        weekday: w.parse().ok()?,
    })
}

/// A date in a Qt date format (d, dd, ddd, dddd, M, MM, MMM, MMMM, yy,
/// yyyy; text in single quotes is kept). English names, as the shell shows.
pub fn render(format: &str, day: Day) -> String {
    let chars: Vec<char> = format.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\'' {
            let end = chars[i + 1..]
                .iter()
                .position(|&q| q == '\'')
                .map_or(chars.len(), |p| i + 1 + p);
            out.extend(&chars[i + 1..end]);
            i = end + 1;
            continue;
        }
        let run = chars[i..].iter().take_while(|&&x| x == c).count();
        let weekday = DAYS[(day.weekday.clamp(1, 7) - 1) as usize];
        let month = MONTHS[(day.month.clamp(1, 12) - 1) as usize];
        let piece = match (c, run) {
            ('d', 1) => day.day.to_string(),
            ('d', 2) => format!("{:02}", day.day),
            ('d', 3) => weekday[..3].to_string(),
            ('d', _) => weekday.to_string(),
            ('M', 1) => day.month.to_string(),
            ('M', 2) => format!("{:02}", day.month),
            ('M', 3) => month[..3].to_string(),
            ('M', _) => month.to_string(),
            ('y', 2) => format!("{:02}", day.year % 100),
            ('y', 4) => day.year.to_string(),
            _ => chars[i..i + run].iter().collect(),
        };
        out.push_str(&piece);
        i += run;
    }
    out
}

/// `timedatectl show`: (time zone, network time on, synchronized).
pub fn parse_show(out: &str) -> (String, bool, bool) {
    let get = |k: &str| {
        out.lines()
            .find_map(|l| l.strip_prefix(&format!("{k}=")))
            .unwrap_or_default()
            .to_string()
    };
    (get("Timezone"), get("NTP") == "yes", get("NTPSynchronized") == "yes")
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub zone: String,
    pub ntp: bool,
    pub synced: bool,
    pub zones: Vec<String>,
    pub today: Day,
    /// Why the time settings could not be read (timedatectl missing).
    pub problem: Option<String>,
}

fn read() -> Reading {
    let today = parse_day(&system::run_blocking("date", &args(&["+%Y %m %d %u"]), None).unwrap_or_default())
        .unwrap_or_default();
    let show = match system::run_blocking("timedatectl", &args(&["show"]), None) {
        Ok(out) => out,
        Err(e) => {
            return Reading {
                today,
                problem: Some(format!("Could not read the time settings: {e}")),
                ..Reading::default()
            };
        }
    };
    let (zone, ntp, synced) = parse_show(&show);
    Reading {
        zone,
        ntp,
        synced,
        zones: system::run_blocking("timedatectl", &args(&["list-timezones"]), None)
            .unwrap_or_default()
            .lines()
            .map(String::from)
            .collect(),
        today,
        problem: None,
    }
}

#[derive(Default)]
pub struct State {
    reading: Option<Reading>,
    /// Today in each preset, in DATE_PRESETS order.
    date_labels: Vec<String>,
    picking: bool,
    query: String,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Reading),
    StartPick,
    CancelPick,
    Query(String),
    Zone(String),
    Ntp(bool),
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(read), |r| Msg::Loaded(r.unwrap_or_default())),
            Msg::Loaded(r) => {
                self.date_labels = DATE_PRESETS.iter().map(|f| render(f, r.today)).collect();
                self.reading = Some(r);
                self.busy = false;
            }
            Msg::StartPick => {
                self.picking = true;
                self.query.clear();
            }
            Msg::CancelPick => self.picking = false,
            Msg::Query(q) => self.query = q,
            Msg::Zone(zone) => {
                self.picking = false;
                self.busy = true;
                return Task::perform(system::run("timedatectl", args(&["set-timezone", &zone]), None), |r| {
                    Msg::Done(r.map(|_| ()))
                });
            }
            Msg::Ntp(on) => {
                self.busy = true;
                let value = if on { "true" } else { "false" };
                return Task::perform(system::run("timedatectl", args(&["set-ntp", value]), None), |r| {
                    Msg::Done(r.map(|_| ()))
                });
            }
            Msg::Done(r) => {
                self.error = r.err().map(|e| system::polkit_error(&e));
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    pub fn time_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(r) = &self.reading else {
            return vec![ui::note("Looking…")];
        };
        if let Some(p) = &r.problem {
            return vec![ui::note(p.clone())];
        }
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let idle = !self.busy;
        rows.push(ui::item(
            ico::GLOBE,
            "Time zone".into(),
            format!("{} · changing it asks for your password", r.zone.replace('_', " ")),
            vec![if self.picking {
                ui::action("Cancel", Some(Msg::CancelPick), Action::Normal)
            } else {
                ui::action("Change…", idle.then_some(Msg::StartPick), Action::Normal)
            }],
        ));
        if self.picking {
            let matches = r
                .zones
                .iter()
                .filter(|z| ui::matches_query(&z.replace('_', " "), &self.query))
                .take(8)
                .map(|z| ui::PickerMatch {
                    label: z.replace('_', " "),
                    font: None,
                    detail: String::new(),
                    on_pick: Msg::Zone(z.clone()),
                })
                .collect();
            let picker = ui::search_picker("Search a city or region", &self.query, Msg::Query, matches);
            rows.push(container(picker).padding([4, 14]).into());
        }
        let state = match (r.ntp, r.synced) {
            (true, true) => "On, synchronized",
            (true, false) => "On, not synchronized yet",
            (false, _) => "Off: the clock keeps its own time",
        };
        rows.push(ui::item(
            ico::REFRESH_CW,
            "Network time".into(),
            format!("{state} · asks for your password"),
            vec![ui::switch(r.ntp, idle.then_some(Msg::Ntp))],
        ));
        rows
    }

    /// The date format presets as a dropdown, each as today's date in it;
    /// a typed format that is not a preset shows as Custom.
    pub fn date_row(&self, current: &str) -> Element<'_, Message> {
        let today = self.reading.as_ref().map(|r| r.today).unwrap_or_default();
        let mut items: Vec<(&str, bool, Option<Message>)> = DATE_PRESETS
            .iter()
            .zip(&self.date_labels)
            .map(|(f, l)| {
                (
                    l.as_str(),
                    *f == current,
                    Some(Message::Set("clock-date-format", Value::Text(f.to_string()))),
                )
            })
            .collect();
        if !DATE_PRESETS.contains(&current) {
            items.push(("Custom (typed above)", true, None));
        }
        ui::item(
            ico::CALENDAR,
            "Presets".into(),
            format!("Today in the bar: {}", render(current, today)),
            vec![ui::select(items, Length::Fixed(300.0))],
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FRI: Day = Day {
        year: 2026,
        month: 11,
        day: 20,
        weekday: 5,
    };

    #[test]
    fn renders_qt_date_formats() {
        assert_eq!(render("ddd, dd MMM", FRI), "Fri, 20 Nov");
        assert_eq!(render("dddd d MMMM yyyy", FRI), "Friday 20 November 2026");
        assert_eq!(render("dd.MM.yy", FRI), "20.11.26");
        assert_eq!(render("'week' d", FRI), "week 20");
        assert_eq!(parse_day("2026 11 20 5\n"), Some(FRI));
        assert_eq!(parse_day("x"), None);
    }

    #[test]
    fn reads_timedatectl() {
        let out = "Timezone=Europe/Tallinn\nLocalRTC=no\nNTP=yes\nNTPSynchronized=no\n";
        assert_eq!(parse_show(out), ("Europe/Tallinn".to_string(), true, false));
    }
}
