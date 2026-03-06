#!/bin/bash
# keybinds.sh - Searchable keybind viewer using rofi

python3 - <<'EOF'
import subprocess, json, re, os, sys

raw = subprocess.check_output(['hyprctl', 'binds', '-j']).decode()
binds = json.loads(raw)

MOD_BITS = [(64,'Super'),(4,'Ctrl'),(8,'Alt'),(1,'Shift')]

KEY_NAMES = {
    'grave':'`', 'bracketleft':'[', 'bracketright':']',
    'semicolon':';', 'apostrophe':"'", 'comma':',', 'period':'.',
    'slash':'/', 'backslash':'\\', 'minus':'-', 'equal':'=',
    'space':'Space', 'Return':'Return', 'Tab':'Tab',
    'Delete':'Del', 'BackSpace':'Bksp', 'Escape':'Esc',
    'KP_Add':'Num+', 'KP_Subtract':'Num-',
    'XF86AudioRaiseVolume':'Vol↑', 'XF86AudioLowerVolume':'Vol↓',
    'XF86AudioMute':'Mute', 'XF86AudioMicMute':'MicMute',
    'XF86MonBrightnessUp':'Bright↑', 'XF86MonBrightnessDown':'Bright↓',
    'XF86AudioNext':'Next', 'XF86AudioPrev':'Prev',
    'XF86AudioPlay':'Play', 'XF86AudioPause':'Pause',
    'XF86PowerOff':'Power', 'XF86CapsLock':'Caps',
    'mouse_down':'Scroll↓', 'mouse_up':'Scroll↑',
    'UP':'↑', 'DOWN':'↓', 'left':'←', 'right':'→', 'up':'↑', 'down':'↓',
}

EXEC_LABELS = [
    (r'kitty(?:\s|$)',              'Terminal'),
    (r'nautilus',                   'File Manager'),
    (r'firefox',                    'Browser'),
    (r'rofi.*drun',                  'App Launcher'),
    (r'gtklock',                    'Lock Screen'),
    (r'swaync-client.*-t',          'Notifications'),
    (r'hyprpicker',                 'Color Picker'),
    (r'playerctl next',             'Next Track'),
    (r'playerctl previous',         'Prev Track'),
    (r'playerctl play-pause',       'Play / Pause'),
    (r'swayosd.*output-volume raise','Volume Up'),
    (r'swayosd.*output-volume lower','Volume Down'),
    (r'swayosd.*mute-toggle',       'Toggle Mute'),
    (r'swayosd.*input-volume mute', 'Toggle Mic'),
    (r'swayosd.*brightness raise',  'Brightness Up'),
    (r'swayosd.*brightness lower',  'Brightness Down'),
    (r'swayosd.*caps-lock',         'Caps Lock'),
    (r'systemctl suspend',          'Suspend'),
    (r'restart\.sh',                'Restart Services'),
    (r'wallpaper\.sh',              'Change Wallpaper'),
    (r'screenshot-ocr',             'Screenshot → OCR'),
    (r'swappy',                     'Screenshot & Annotate'),
    (r'grim.*wl-copy',              'Screenshot'),
    (r'wayvnc-toggle',              'Toggle WayVNC'),
    (r'keybinds',                   'Show Keybinds'),
    (r'media start',                'Media Start'),
    (r'media stop',                 'Media Stop'),
    (r'bluetooth',                  'Bluetooth'),
    (r'wifi',                       'Wi-Fi & VPN'),
    (r'powermenu',                  'Power Menu'),
    (r'pavucontrol',                'Audio Mixer'),
]

def get_mods(mask):
    return [n for b, n in MOD_BITS if mask & b]

def fmt_key(k):
    return KEY_NAMES.get(k, k.upper() if len(k) == 1 else k)

def get_label(b):
    d, a = b['dispatcher'], b['arg']
    if b.get('has_description') and b.get('description'):
        return b['description']
    if d == 'exec':
        for pat, lbl in EXEC_LABELS:
            if re.search(pat, a): return lbl
        return a.split()[0].split('/')[-1].replace('-', ' ').title()
    if d == 'killactive':              return 'Close Window'
    if d == 'togglefloating':         return 'Toggle Float'
    if d == 'fullscreenstate':        return 'Fullscreen'
    if d == 'pseudo':                 return 'Pseudo Tile'
    if d == 'togglesplit':            return 'Toggle Split'
    if d == 'cyclenext':              return 'Cycle Windows'
    if d == 'resizeactive':           return 'Resize Window'
    if d == 'movecurrentworkspacetomonitor': return 'WS → Next Monitor'
    if d == 'focusmonitor':           return 'Focus Next Monitor'
    if d == 'movefocus':              return f'Focus {a.title()}'
    if d == 'movewindow':             return f'Move Window {a.title()}'
    if d == 'workspace':
        if a == 'previous': return 'Last Workspace'
        if a == 'm-1': return 'Prev WS on Monitor'
        if a == 'm+1': return 'Next WS on Monitor'
        return f'Workspace {a}'
    if d == 'movetoworkspace':
        if a == 'm-1': return '→ Prev WS'
        if a == 'm+1': return '→ Next WS'
        return f'→ Workspace {a}'
    return f'{d} {a}'.strip()

def get_cat(b):
    d, a, k = b['dispatcher'], b['arg'], b['key']
    if b['mouse'] or k.startswith('switch:') or k.startswith('mouse:'): return None
    if d == 'exec':
        if re.search(r'playerctl|XF86Audio', a) or re.search(r'XF86Audio', k): return 'Media'
        if re.search(r'brightness', a) or re.search(r'XF86MonBrightness', k): return 'Brightness'
        if re.search(r'grim|slurp|swappy|screenshot', a): return 'Screenshots'
        if re.search(r'kitty|nautilus|firefox|rofi|hyprpicker|pavucontrol', a): return 'Apps'
        return 'System'
    if re.search(r'killactive|togglefloating|fullscreen|pseudo|togglesplit|resize|movewindow|movefocus|cyclenext', d):
        return 'Windows'
    if re.search(r'workspace|movetoworkspace|movecurrent|focusmonitor', d):
        return 'Workspaces'
    return None

def get_action(b):
    d, a = b['dispatcher'], b['arg']
    if d == 'exec': return a
    return f'hyprctl dispatch {d} {a}'

CAT_ORDER = ['Apps','Windows','Workspaces','Screenshots','Media','Brightness','System']

grouped = {}
for b in binds:
    c = get_cat(b)
    if not c: continue
    grouped.setdefault(c, []).append(b)

# Compact workspace 1-10 into single rows
if 'Workspaces' in grouped:
    items = grouped['Workspaces']
    ws_nums = [b for b in items if b['dispatcher'] == 'workspace'       and re.match(r'^\d+$', b['arg'])]
    mv_nums = [b for b in items if b['dispatcher'] == 'movetoworkspace' and re.match(r'^\d+$', b['arg'])]
    rest    = [b for b in items if b not in ws_nums and b not in mv_nums]
    if mv_nums:
        rest.insert(0, {'_compact':True,'modmask':65,'key':'1–0','dispatcher':'movetoworkspace','arg':'','_label':'Move to Workspace 1–10','_action':None})
    if ws_nums:
        rest.insert(0, {'_compact':True,'modmask':64,'key':'1–0','dispatcher':'workspace','arg':'','_label':'Switch to Workspace 1–10','_action':None})
    grouped['Workspaces'] = rest

# Build rofi entries
entries = []  # (markup_line, action)

for cat in CAT_ORDER:
    items = grouped.get(cat, [])
    if not items: continue
    for b in items:
        mod_keys  = get_mods(b['modmask'])
        key_str   = fmt_key(b['key'])
        all_keys  = mod_keys + [key_str]
        label     = b.get('_label') or get_label(b)
        action    = b.get('_action', get_action(b)) if not b.get('_compact') else None

        # Build colored key markup
        parts = []
        for k in all_keys:
            if k in mod_keys:
                parts.append(f'<span foreground="#33ccff">{k}</span>')
            else:
                parts.append(f'<span foreground="#e7e3de" weight="bold">{k}</span>')
        keys_markup = f'<span foreground="#3a3735"> + </span>'.join(parts)

        # Pad plain key string to align descriptions (monospace font)
        plain_keys = ' + '.join(all_keys)
        pad = ' ' * max(2, 30 - len(plain_keys))

        cat_markup  = f'<span foreground="#5c5855">{cat:<13}</span>'
        desc_markup = f'<span foreground="#9d9490">{label}</span>'

        line = f'{cat_markup}  {keys_markup}{pad}{desc_markup}'
        entries.append((line, action))

if not entries:
    sys.exit(1)

display = '\n'.join(l for l, _ in entries)
result = subprocess.run(
    ['rofi', '-dmenu', '-i', '-markup-rows', '-p', 'Keybinds',
     '-format', 'i', '-no-custom',
     '-theme', os.path.expanduser('~/.config/rofi/keybinds.rasi')],
    input=display, capture_output=True, text=True
)

if result.returncode == 0 and result.stdout.strip():
    idx = int(result.stdout.strip())
    if 0 <= idx < len(entries):
        _, action = entries[idx]
        if action:
            subprocess.Popen(action, shell=True)
EOF
