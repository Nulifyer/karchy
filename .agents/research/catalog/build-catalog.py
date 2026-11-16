#!/usr/bin/env python3
"""Build default/karchy/quick-install.json from the merged catalog research.

One-time generator, kept so the first catalog can be reproduced. After that
the JSON is edited by hand and tools/catalog-check keeps it honest. Edited by
hand since: the apps karchy ships (`default` entries, D-71), and LocalSend
moved to karchy's own entry.

Inputs (this folder): merged.json (merge.py), pacinfo.json (pacman -Si of every
package named), aurinfo.json (AUR RPC), omarchyinfo.json ([omarchy] repo db),
papirus-apps.txt (Papirus app icon names).

Rules (D-67, 2026-11-15):
  - list everything whose packages come from a signed repo: Arch, [cachyos]
    or [omarchy]
  - from the AUR only well-kept packages: 100+ votes, a maintainer, not
    flagged out of date
  - drop what karchy already installs, what the research said to skip,
    Flatpak-only apps, and things that conflict with karchy's own parts
"""
import json, os, re, glob

HERE = os.path.dirname(os.path.abspath(__file__))
KARCHY = os.path.abspath(os.path.join(HERE, '../../..'))
J = lambda f: json.load(open(os.path.join(HERE, f)))
merged, pac, aur, om = J('merged.json'), J('pacinfo.json'), J('aurinfo.json'), J('omarchyinfo.json')
papirus = set(open(os.path.join(HERE, 'papirus-apps.txt')).read().split())

CATEGORIES = [
    ('browsers', 'Browsers', 'Browsers'),
    ('chat', 'Chat & email', 'Chat & email'),
    ('office', 'Office & notes', 'Office & notes'),
    ('media', 'Media & creative', 'Media & creative'),
    ('gaming', 'Gaming', 'Gaming'),
    ('languages', 'Languages', 'Languages'),
    ('editors', 'Editors & IDEs', 'Editors & IDEs'),
    ('devtools', 'Developer tools', 'Developer tools'),
    ('databases', 'Databases & APIs', 'Databases & APIs'),
    ('cloud', 'Cloud & containers', 'Cloud & containers'),
    ('ai', 'AI', 'AI'),
    ('security', 'Passwords & security', 'Passwords & security'),
    ('network', 'Sync & remote', 'Sync & remote'),
    ('utilities', 'Utilities', 'Utilities'),
    ('system', 'System features', 'System features'),
]
CAT_ID = {src: cid for cid, _, src in CATEGORIES}

# What karchy already installs: every package its PKGBUILDs depend on.
base = set()
for f in glob.glob(os.path.join(KARCHY, 'packaging/pkgbuilds/*/PKGBUILD')):
    if 'nvidia' in f or 'vpn' in f:
        continue
    text = '\n'.join(l.split('#', 1)[0] for l in open(f).read().splitlines())
    for m in re.finditer(r"\bdepends=\((.*?)\)", text, re.S):
        base |= set(re.findall(r"'([^'<>=]+)", m.group(1)))

# Conflicts with karchy's own parts, or not an app.
DENY = {
    'timeshift': 'karchy snapshots with snapper',
    'noctalia-shell': 'a desktop shell; karchy has its own',
    'dux-shell': 'a desktop shell; karchy has its own',
    'gamescope-session-cachyos': 'karchy logs straight into Hyprland',
    'ananicy-cpp': 'system tuning, not an app',
    'bpftune': 'system tuning, not an app',
    'auto-cpufreq': 'fights power-profiles-daemon, which karchy uses',
    'octopi': 'a second package manager front end',
    'shelly': 'a second package manager front end',
    'opencl-nvidia': 'driver part; karchy-nvidia owns the driver',
    'cachyos-gaming-meta': 'a bundle of the separate gaming entries',
    'cachyos-gaming-applications': 'a bundle of the separate gaming entries',
    'bpftune-git': 'system tuning, not an app',
    'qemu-desktop': 'replaced by the Virtual machines feature',
    'podman': 'replaced by the Containers feature',
    'cups': 'replaced by the Printers & scanners feature',
    'virtualbox': 'conflicts with KVM',
    'ventoy': 'writes boot loaders to disks; use Popsicle or dd',
}
# Structured setup the install command applies (bin/karchy-quick-install).
SETUP = {
    'steam': {'gpu32': True},
    'lutris': {'gpu32': True},
    'heroic-games-launcher-bin': {'gpu32': True},
    'faugus-launcher': {'gpu32': True},
    'rustup': {'run': ['rustup default stable']},
    'docker': {'services': ['docker.socket'], 'groups': ['docker']},
    'tailscale': {'services': ['tailscaled.service']},
    'ollama': {'services': ['ollama.service']},
    'ollama-cuda': {'services': ['ollama.service']},
    'ollama-rocm': {'services': ['ollama.service']},
    'syncthing': {'userServices': ['syncthing.service']},
    'gamemode': {'groups': ['gamemode']},
    'wireshark-qt': {'groups': ['wireshark']},
    'virt-manager': {'services': ['libvirtd.socket'], 'groups': ['libvirt']},
    'sunshine': {'note': 'Pair a device from Sunshine\'s web page at https://localhost:47990.'},
    'postgresql': {'note': 'Create the database cluster before first use: sudo -iu postgres initdb -D /var/lib/postgres/data, then sudo systemctl enable --now postgresql.'},
    'mariadb': {'note': 'Create the data directory before first use: sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql, then sudo systemctl enable --now mariadb.'},
    'valkey': {'services': ['valkey.service']},
    'mullvad-vpn': {'services': ['mullvad-daemon.service']},
    'nordvpn-bin': {'services': ['nordvpnd.service'], 'groups': ['nordvpn']},
    'coolercontrol': {'services': ['coolercontrold.service']},
    'lact': {'services': ['lactd.service']},
    'ckb-next': {'services': ['ckb-next-daemon.service']},
    'scx-scheds': {'services': ['scx_loader.service']},
    'profile-sync-daemon': {'userServices': ['psd.service']},
    'git-lfs': {'run': ['git lfs install']},
    'tealdeer': {'run': ['tldr --update']},
}
# Package lists the research got wrong for karchy.
PACKAGES = {
    'docker': ['docker', 'docker-compose', 'docker-buildx'],  # ufw-docker rewrites ufw rules karchy owns
    'steam': ['steam'],  # the 32-bit driver comes from gpu32, for the GPU this machine has
}
# Need a setup script karchy doesn't have yet.
DROP_IDS = {
    'battle-net': 'needs its installer downloaded and run under umu',
    'xbox-controllers': 'needs DKMS headers for both kernels and xpad blacklisted',
}
NAME_FIX = {
    'GNU Image Manipulation Program (GIMP)': 'GIMP',
    'Heroic (Epic/GOG/Amazon)': 'Heroic Games Launcher',
    'Sunshine (stream this PC)': 'Sunshine',
    'Moonlight (stream client)': 'Moonlight',
    'Minecraft': 'Prism Launcher (Minecraft)',
    'Proton-GE / Proton manager': 'ProtonUp-Qt',
    'Totem (GNOME Videos)': 'GNOME Videos',
    'Discord / Vesktop': 'Discord',
    'Node.js (current)': 'Node.js',
    'Java (JDK)': 'Java',
    'Python': 'uv (Python)',
}
FEATURES = [
    dict(id='printing', name='Printers & scanners', category='system', icon='printer',
         description='Print to network and USB printers, and scan with Document Scanner. Printers that need no driver are found on their own.',
         packages=['cups', 'cups-browsed', 'sane-airscan', 'simple-scan'], source='karchy', feature='karchy-feature-printing', keywords=['cups', 'scan', 'sane']),
    dict(id='vms', name='Virtual machines', category='system', icon='virt-manager',
         description='Run Linux and Windows VMs with QEMU/KVM, each in a window of its own. The bar shows which VMs are running.',
         packages=['qemu-desktop', 'edk2-ovmf', 'swtpm', 'spice-gtk'], source='karchy', feature='karchy-feature-vms', keywords=['qemu', 'kvm', 'windows']),
    dict(id='containers', name='Containers', category='system', icon='podman-desktop',
         description='Run containers with Podman, without root. The docker command and docker compose work too, and the bar shows what\'s running.',
         packages=['podman', 'podman-docker', 'docker-compose'], source='karchy', feature='karchy-feature-containers', keywords=['podman', 'docker', 'compose']),
]
FONTS = [('Cascadia Mono', 'ttf-cascadia-mono-nerd'), ('Meslo LG', 'ttf-meslo-nerd'), ('Fira Code', 'ttf-firacode-nerd'),
         ('Victor Mono', 'ttf-victor-mono-nerd'), ('Bitstream Vera Mono', 'ttf-bitstream-vera-mono-nerd'), ('Iosevka', 'ttf-iosevka-nerd')]


def source(p):
    r = set(pac.get(p, {}).get('repos', []))
    if r & {'core', 'extra', 'multilib'}:
        return 'arch'
    if any(x.startswith('cachyos') for x in r):
        return 'cachyos'
    if p in om:
        return 'omarchy'
    a = aur.get(p)
    if a and a['NumVotes'] >= 100 and a['Maintainer'] and not a['OutOfDate']:
        return 'aur'
    return None


def prefer(p):
    """Arch's own package when it has one, else the -bin build (user 2026-11-15)."""
    stem = re.sub(r'-(bin|git)$', '', p)
    b = stem + '-bin'
    if source(b) == 'arch':
        return b
    if source(stem) == 'arch':
        return stem
    if source(b):
        return b
    return stem if source(stem) else p


def description(p):
    d = pac.get(p, {}).get('desc') or (om.get(p) or {}).get('desc') or (aur.get(p) or {}).get('Description') or ''
    d = re.sub(r'\s+', ' ', d).strip().rstrip('.')
    return d[:1].upper() + d[1:] if d else ''


def icon(p, name):
    stem = re.sub(r'-(bin|git|desktop|stable|beta|nerd)$', '', p)
    cands = [p, stem, re.sub(r'-(browser|launcher|qt|gtk|fresh|still|openjdk|edition)$', '', stem),
             re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-'), name.lower().split()[0]]
    for c in cands:
        if c in papirus:
            return c
    return ''


def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')


apps, seen, dropped = [], set(), {}
for f in FEATURES:
    apps.append(f); seen.add(f['id'])
for o in merged:
    pk = [p for p in o['pkgs'] if re.fullmatch(r'[a-z0-9@._+-]+', p)]
    if not pk:
        dropped[o['name']] = 'no package'; continue
    main = pk[0]
    if o['skip']:
        dropped[o['name']] = 'research: ' + o['skip']; continue
    if main in DENY:
        dropped[o['name']] = DENY[main]; continue
    if main in base or o['base']:
        dropped[o['name']] = 'karchy installs it'; continue
    main = prefer(main)
    pk = [main] + pk[1:]
    src = source(main)
    if not src:
        dropped[o['name']] = 'AUR package not well kept, or not found'; continue
    # Every other package must also come from somewhere allowed.
    pk = PACKAGES.get(main) or [p for p in pk if source(p) and p not in base] or [main]
    name = NAME_FIX.get(o['name'], o['name'])
    name = name[:1].upper() + name[1:]
    kw = re.findall(r'\(([^)]*)\)', name)
    name = re.sub(r'\s*\([^)]*\)', '', name).strip() if kw and name not in ('Prism Launcher (Minecraft)', 'uv (Python)') else name
    aid = slug(name)
    if aid in seen:
        aid = slug(name + '-' + main)
    if aid in seen:
        dropped[o['name']] = 'duplicate'; continue
    if aid in DROP_IDS:
        dropped[o['name']] = DROP_IDS[aid]; continue
    seen.add(aid)
    app = dict(id=aid, name=name, category=CAT_ID.get(o['cat'], 'utilities'), description=description(main),
               icon=icon(main, name), packages=pk[:6], source=('aur' if any(source(p) == 'aur' for p in pk) else src))
    if any('multilib' in pac.get(p, {}).get('repos', []) for p in pk):
        app['multilib'] = True
    s = dict(SETUP.get(main, {}))
    if s.get('gpu32'):
        app['multilib'] = True
    if s:
        app['setup'] = s
    if kw:
        app['keywords'] = [k.strip() for k in re.split(r'[,/]', ' '.join(kw)) if k.strip()]
    apps.append(app)

# Nerd Fonts: one entry per face, as Omarchy offers them.
for name, p in FONTS:
    if source(p) and slug(name + ' nerd font') not in seen:
        apps.append(dict(id=slug(name + ' nerd font'), name=name + ' Nerd Font', category='utilities',
                         description=description(p) or 'Patched font with Nerd Font icons', icon='', packages=[p], source=source(p), keywords=['font', 'nerd']))
apps = [a for a in apps if not (a['name'].startswith('Nerd Fonts'))]

order = {cid: i for i, (cid, _, _) in enumerate(CATEGORIES)}
apps.sort(key=lambda a: (order[a['category']], a['name'].lower()))
out = dict(categories=[dict(id=c, name=n) for c, n, _ in CATEGORIES], apps=apps)
dst = os.path.join(KARCHY, 'default/karchy/quick-install.json')
with open(dst, 'w') as fh:
    fh.write('{\n  "categories": [\n')
    fh.write(',\n'.join('    ' + json.dumps(c, ensure_ascii=False) for c in out['categories']))
    fh.write('\n  ],\n  "apps": [\n')
    fh.write(',\n'.join('    ' + json.dumps(a, ensure_ascii=False) for a in apps))
    fh.write('\n  ]\n}\n')
json.dump(dropped, open(os.path.join(HERE, 'dropped.json'), 'w'), indent=1, ensure_ascii=False)
from collections import Counter
print(len(apps), 'apps;', Counter(a['source'] for a in apps), '; no icon:', sum(not a['icon'] for a in apps), '; dropped', len(dropped))
print(Counter(a['category'] for a in apps))
print(Counter(v.split(':')[0] for v in dropped.values()))
