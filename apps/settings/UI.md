# Settings app UI rules

How panels in the settings app look and behave. Follow these when adding a
panel or a setting; the shared pieces in `src/ui.rs`, `src/controls.rs` and
`src/style.rs` already do most of it.

## Philosophy: simple at a glance, complex when needed

Every panel first answers the everyday question in one look: is it on,
what is it set to, the one switch most people want. Everything else is
there, but one step away: behind Details, in a collapsed list, in a
dialog, or further down the page.

- **One row per thing at first.** A VPN, a network, a device is one row
  with its name, its state and at most two controls. Its address, options,
  sub-lists and rarely used actions open under it with Details.
- **Don't assume what someone uses.** A tool that may not be installed or
  used (Tailscale, Steam, a VPN) takes no more room than one row, or none
  when it is missing; it never gets a section of its own by default.
- **Rare tasks open on demand.** Joining a hidden network, setting up a
  VPN by hand: a button that opens a dialog or form, not fields always on
  screen.
- **Lists stay short.** Long lists (devices, Proton versions, hidden apps,
  per-app notification rules) start collapsed with a count in the summary
  row (`ui::collapsed_list`); open, they get a search field from eight
  entries.
- **Extras live with their thing.** Controls that belong to one device
  (AirPods noise control) open under that device's row with Details, not in
  a section of their own; a section that would only say "none" is one row.
- **Nothing is lost.** Collapsed does not mean hidden from search or the
  keyboard: Details is a button like any other, and search finds settings
  wherever they are.

## Structure

- **Sidebar groups:** panels are listed under group headers (Connections,
  Input & output, Appearance, Workspace, System; `schema::Group`), with a
  thin line between groups in the icon-only sidebar. A new panel goes in the
  group a user would look in, next to its group's other panels.
- **Sidebar → panel → sections → rows.** A panel is one topic (Keyboard,
  Sound). A section is an uppercase header over one card. A row is one
  option or one item (a network, a device).
- **One option per row.** The label and help text are on the left, the
  control on the right, on one line: toggles, dropdowns, two-option groups
  and sliders all sit beside their label. In a narrow panel the control
  moves under the label (`Layout::stacked`); a multi-select group, a pill
  list and a search picker are always under their label, as they need the
  width.
- **Order inside a panel:** the main switch first (Wi-Fi, Bluetooth), then
  what is in use, then lists of other things, then advanced options.
- Every panel has an `id` for `settings -p <id>` and `keywords` for search,
  so people find it by the words they use ("wifi", "headphones").

## Picking the control

| What the option is | Control |
|---|---|
| On or off | Toggle (`Control::Toggle`) |
| One of **two** options | Joined button group, the picked one filled (`ui::segmented`) |
| One of **three or more** options | Dropdown (`pick_list`) |
| A few short on/off options that belong together (up to four, about 40 characters in all; `ui::fits_buttons`) | Multi-select button group, on ones filled and checked (`ui::multi_select`) |
| More or longer on/off options | Check select: a button saying what is on, opening a checkbox list under the row, with a search field from eight options (`ui::check_head`, `ui::check_list`) |
| A number in a range | Slider with its value and unit beside it |
| One out of a long list (fonts, keyboard layouts) | Search picker: a search field with up to eight matches under it, fonts drawn in themselves (`ui::search_picker`) |
| Free text | Text field, applied on Enter |
| A folder | Text field joined to a Browse… button that opens a folder chooser (`Control::Folder`, zenity) |
| A link | Text field; links are shortened when they hold tokens |

**On/off options never go in a plain dropdown**, which holds one pick: a
few short ones are a button group, the rest a check select. Keep labels
short (one or two words) and put the detail in the help text. A check
select's list opens under its row, never inside it, so the row keeps its
height and the tree lines stay put.

## Buttons on a row

- **One button:** a plain action button (`ui::action`).
- **Two buttons:** one joined group (`ui::button_group`), the main action
  last.
- **More than two:** the main action as a button, everything else in a
  "More" dropdown next to it (`ui::more_actions`, which falls back to a
  joined pair when there is only one other action). Never a dropdown with a
  single entry. The main action is what
  most people come for: Connect, Pair, Add.
- **A text field with buttons** (add a feed, a password, a name) is one
  input group (`ui::input_group`, `ui::fields_group`): field first, Cancel
  before the confirming button.
- Joined parts round only the group's outer corners and share one border
  line (`style::Joint`). Buttons in a group share the width by label length,
  so no label wraps.

## Actions and feedback

- **Apply at once.** No Save button for settings: toggles, groups and
  dropdowns write when changed, sliders when released, text fields on Enter
  (with "Press Enter to apply" while the typed text differs).
- **Destructive actions confirm.** Forget, Remove and the like turn into
  "Sure?" on the first click and act on the second; anything else resets
  them. They are red (`Action::Danger`).
- **Reset to default.** A setting that differs from its default shows a
  small ↺ button that writes the default back.
- **Busy:** while a command runs, its row shows "Working…" in place of its
  buttons and the panel's other actions are disabled.
- **Errors** go at the top of the panel in red, in plain words ("Could not
  save calendar.url: …"), never as a dialog.
- **Empty and loading** states are a muted line inside the card ("No paired
  devices", "Loading…"), so the card never disappears.
- System state (Wi-Fi, devices, volumes) refreshes on its own while the
  panel is open; nothing needs a refresh button except a deliberate scan.

## Wording

- Sentence case everywhere ("Copy to clipboard", not "Copy To Clipboard").
- Labels say what the option is, help text says what it does, in one short
  line. No "Enable"/"Disable" in labels: the toggle already says that.
- Units always shown next to numbers (ms, px, %, fps, min).
- Plain words over jargon: "Frame rate", not "FPS cap"; technical names
  (AAC, XKB codes) only as detail.
- Secrets never shown: passwords are masked, tokens in links are cut.

## Look

- Colours come from `src/style.rs`, which mirrors
  `config/quickshell/Theme.qml`. The accent follows the shell's accent.
- Text font is Adwaita Sans. Icons are Lucide line icons (`lucide-iced`,
  `ui::icon`): they take the colour of the text around them, so a selected
  sidebar entry's icon is the accent. Pick the icon whose plain meaning fits
  the row; the same thing gets the same icon everywhere.
- Spacing steps: 2, 6, 8, 10, 12, 14, 28 px. Cards have a 10 px radius,
  controls 7–8 px.
- Red, green and yellow mean danger, success and warning; do not use them
  for decoration.

## Keyboard and window

- Ctrl+F focuses search, Escape empties it, Enter submits a text field.
- Below 820 px the sidebar shows icons only; below 640 px of panel width
  controls stack under their labels. Nothing may need horizontal scrolling.

## Details

- More about a row that most people do not need (a connection's addresses,
  gateway, DNS) hides behind a **Details** button with a chevron
  (`ui::disclosure`), opening below the row, indented under its title.
- Details is not an action: it does not count toward the two-button limit.

## Trees

- Items that belong to a switch above them (the networks under Wi-Fi) hang
  under it as a tree (`ui::branch`): a guide line with a tick to each item.
  An item's own extras (details, a password field) stay inside its branch.

## Dialogs

- Something used rarely that needs a few fields (joining a hidden network)
  opens in a dialog (`ui::modal`) from a button, instead of sitting in the
  panel. The window behind is dimmed; clicking outside, Cancel or Escape
  closes it, and its first field has the cursor.

## Keyboard

- Two zones: Tab stays inside the open panel (wrapping round); Shift+Tab
  returns to the sidebar, where Up/Down move and Enter opens a panel with
  its first control focused.
- Every control is reachable with Tab: build buttons, switches and
  dropdowns with the `ui` helpers (`ui::action`, `ui::switch`,
  `ui::button_group`, `ui::choice`…), which wrap them in
  `focus::focusable`. A control made by hand needs the same wrapper, with
  the message Enter or Space should send.

