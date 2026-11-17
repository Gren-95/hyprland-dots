# Settings app UI rules

How panels in the settings app look and behave. Follow these when adding a
panel or a setting; the shared pieces in `src/ui.rs`, `src/controls.rs` and
`src/style.rs` already do most of it.

## Structure

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
| Several on/off options that belong together | Multi-select button group, on ones filled and checked (`ui::multi_select`) |
| A number in a range | Slider with its value and unit beside it |
| One out of a long list (fonts, keyboard layouts) | Search picker: a search field with up to eight matches under it, fonts drawn in themselves (`ui::search_picker`) |
| Free text | Text field, applied on Enter |
| A path or a link | Text field; links are shortened when they hold tokens |

**Multi-select is the exception to the dropdown rule:** a dropdown holds one
pick, so several on/off options stay a button group however many there are.
Keep their labels short (one or two words) and put the detail in the help
text.

## Buttons on a row

- **One button:** a plain action button (`ui::action`).
- **Two buttons:** one joined group (`ui::button_group`), the main action
  last.
- **More than two:** the main action as a button, everything else in a
  "More" dropdown next to it (`ui::more_actions`). The main action is what
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
- Text font is Adwaita Sans; glyphs (sidebar, list rows) use the Nerd Font.
- Spacing steps: 2, 6, 8, 10, 12, 14, 28 px. Cards have a 10 px radius,
  controls 7–8 px.
- Red, green and yellow mean danger, success and warning; do not use them
  for decoration.

## Keyboard and window

- Ctrl+F focuses search, Escape empties it, Enter submits a text field.
- Below 820 px the sidebar shows icons only; below 640 px of panel width
  controls stack under their labels. Nothing may need horizontal scrolling.
