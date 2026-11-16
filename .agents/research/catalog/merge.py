import re, json, sys, collections
D='/home/nulifyer/Projects/karchy/.agents/research/catalog/'
CR='/home/nulifyer/Projects/karchy/.agents/research/catalog-research.md'

def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]
def pkgs(s):
    # Packages installed together; alternatives after ';' or 'or' are left out.
    s = re.split(r';|\bor\b|\balso\b|\balternatively\b|\binstead\b|\bfallback\b', s, maxsplit=1, flags=re.I)[0]
    return [t for t in re.findall(r'`([^`]+)`', s) for t in t.split()]
def clean(s):
    s=re.sub(r'\*\*|⚙','',s); return re.sub(r'\s+',' ',s).strip()
def repo_of(s):
    s=s.lower(); out=[]
    for r in ['cachyos','core','extra','multilib','omarchy','aur','flatpak']:
        if re.search(r'\b'+r+r'\b',s): out.append(r)
    if 'missing' in s: out.append('missing')
    return out

FINAL=['Browsers','Chat & email','Office & notes','Media & creative','Gaming','Languages','Editors & IDEs','Developer tools','Databases & APIs','Cloud & containers','AI','Passwords & security','Sync & remote','Utilities','System features']
def cat_of(src, sub, name):
    s=(sub+' '+name).lower()
    m=[('browser','Browsers'),('communication','Chat'),('chat','Chat'),('password','Passwords & security'),('security','Passwords & security'),
       ('office','Office & notes'),('pdf','Office & notes'),('notes','Office & notes'),
       ('design','Media & creative'),('media','Media & creative'),('creative','Media & creative'),
       ('emulator','Gaming'),('game','Gaming'),('gaming','Gaming'),
       ('languages','Languages'),('toolchain','Languages'),('editors','Editors & IDEs'),('editor','Editors & IDEs'),
       ('git','Developer tools'),('terminal tools','Developer tools'),('developer tools','Developer tools'),
       ('apis','Databases & APIs'),('database','Databases & APIs'),('cloud','Cloud & containers'),('container','Cloud & containers'),
       ('ai','AI'),('sync','Sync & remote'),('remote','Sync & remote'),('vpn','Sync & remote'),('backup','Sync & remote'),
       ('virtualization','System features'),('platform','System features'),('system','System features'),
       ('hardware','Utilities'),('fonts','Utilities'),('terminal','Utilities'),('utilit','Utilities')]
    sub=sub.lower()
    for k,v in m:
        if re.search(r'\b'+re.escape(k), sub): return v
    return 'Utilities'

rows=[]
OVR=[({'bitwarden','keepassxc','1password','proton-pass','proton-pass-bin','keepassxc'},'Passwords & security'),
     ({'nordvpn-bin','tailscale','mullvad-vpn-bin','protonvpn','protonvpn-app'},'Sync & remote'),
     ({'gnome-builder'},'Editors & IDEs'),
     ({'thunderbird','evolution','geary','kmail','betterbird-bin','proton-mail-bin'},'Chat & email'),
     ({'gnome-boxes','qemu-desktop','virt-manager','docker','podman','winboat','dockurr/windows','nvidia-container-toolkit','distrobox','virtualbox'},'System features')]
# 1. catalog-research (Omarchy O, CachyOS C, usage A, N new)
sec=None
for line in open(CR):
    if line.startswith('## 2'): break
    h=re.match(r'### 1\.\d+ (.*)',line)
    if h: sec=h.group(1); continue
    if sec and line.startswith('| ') and not line.startswith('| Entry') and not line.startswith('|---'):
        c=cells(line)
        if len(c)<4: continue
        src=c[3]; srcs=set()
        if re.search(r'\bO\b',src): srcs.add('Omarchy')
        if re.search(r'\bC\b',src): srcs.add('CachyOS')
        if re.search(r'\bA\b',src): srcs.add('You use it')
        skip='Skip' in src
        sk = re.search(r'\*\*Skip\*\*:?\s*(.*)',src)
        rows.append(dict(name=clean(c[0]), sub=sec, pkgs=pkgs(c[1]), repo=repo_of(c[1]), setup=clean(c[2]), sources=srcs,
                         skip=(clean(sk.group(1)) if sk else ''), via='catalog'))
# 2. linutil
sec=None
for line in open(D+'linutil.md'):
    h=re.match(r'## .*› (.*)',line) or re.match(r'## (Utilities)',line)
    if h: sec=h.group(1); continue
    if sec and line.startswith('| ') and not line.startswith('| App') and not line.startswith('|---'):
        c=cells(line)
        if len(c)<6: continue
        sub=sec if 'other top-level' not in sec else c[0]
        rows.append(dict(name=clean(c[0]), sub=('Linutil '+sec), pkgs=pkgs(c[2]), repo=repo_of(c[3]+' '+c[4]), setup='', sources={'Linutil'}, skip='', note=clean(c[5])[:200], via='linutil'))
# 3. distros
on=False
for line in open(D+'distros.md'):
    if line.startswith('## Merged'): on=True; continue
    if on and line.startswith('| ') and not line.startswith('| App') and not line.startswith('|---'):
        c=cells(line)
        if len(c)<5: continue
        srcs={s.strip().replace('Pop','Pop!_OS').replace('EOS','EndeavourOS') for s in c[2].split(',') if s.strip()}
        rows.append(dict(name=clean(c[0]), sub=c[1], pkgs=pkgs(c[4]), repo=repo_of(c[4]), setup='', sources=srcs, skip=('Flatpak only' if 'Flatpak only' in c[4] else ('no package' if 'missing' in c[4].lower() else '')), via='distros'))
# 4. programming
sec=None
for line in open(D+'programming.md'):
    h=re.match(r'## (.*)',line)
    if h: sec=h.group(1); continue
    if line.startswith('| ') and not line.startswith('| Entry') and not line.startswith('|---'):
        c=cells(line)
        if len(c)<7: continue
        pick=clean(c[6]); srcs={'Dev surveys'} if re.search(r'SO25|JB25',c[5]) else set()
        if re.search(r'\bAudit\b',c[5]): srcs.add('You use it')
        if re.search(r'\bO\b',c[5]): srcs.add('Omarchy')
        rows.append(dict(name=clean(c[0]), sub=c[1], pkgs=pkgs(c[2]), repo=repo_of(c[3]), setup=clean(c[4]), sources=srcs, pick=pick,
                         skip=(pick if pick.startswith('Skip') else ''), base=pick.startswith('in base') or 'in base' in c[4], via='prog', pop=clean(c[5])[:160]))

# split combined rows ("A, B" / "A / B") when names and packages pair up
split=[]
for r in rows:
    nm=re.sub(r'^(Game tools|Windows apps): ','',r['name'])
    if nm=='Reverse engineering, Odin': nm='Ghidra, Odin'
    parts=[x.strip() for x in re.split(r', | / ',nm)]
    pk=[x for x in r['pkgs'] if not x.startswith('-')]
    if len(parts)>1 and len(parts)==len(pk) and '{' not in ''.join(pk):
        for a,b in zip(parts,pk): split.append(dict(r,name=a,pkgs=[b]))
    else: split.append(dict(r,name=nm))
rows=split
def key(n): return re.sub(r'[^a-z0-9]','',re.sub(r'\(.*?\)','',n.lower()))
ALIAS={'brave-browser':'brave-bin'}
merged=[]; bypkg={}; byname={}
for r in rows:
    p=[ALIAS.get(x,x) for x in r['pkgs'] if not x.startswith('-')]
    r['pkgs']=p
    hit=None
    if p and p[0] in bypkg: hit=bypkg[p[0]]
    elif key(r['name']) in byname: hit=byname[key(r['name'])]
    if hit is None:
        hit=dict(name=r['name'], subs=[], pkgs=p, repo=set(), setup='', sources=set(), skip=set(), notes=[], picks=[], base=False, vias=set(), pop='')
        merged.append(hit)
    hit['subs'].append((r['via'],r['sub'])); hit['repo'] |= set(r['repo']); hit['sources'] |= r['sources']; hit['vias'].add(r['via'])
    if r.get('setup') and r['setup'].lower() not in ('none','') and not hit['setup']: hit['setup']=r['setup']
    if r.get('skip'): hit['skip'].add(r['skip'])
    if r.get('pick'): hit['picks'].append(r['pick'])
    if r.get('base'): hit['base']=True
    if r.get('pop') and not hit['pop']: hit['pop']=r['pop']
    if not hit['pkgs'] and p: hit['pkgs']=p
    for x in p[:1]: bypkg.setdefault(x,hit)
    byname.setdefault(key(r['name']),hit)
    if r['via']=='prog': hit['name']=r['name']

# karchy base packages
import subprocess,glob
base=set()
for f in glob.glob('/home/nulifyer/Projects/karchy/packaging/pkgbuilds/karchy*/PKGBUILD'):
    t=open(f).read()
    for m in re.finditer(r"depends=\((.*?)\)",t,re.S): base|=set(re.findall(r"'([^'<>=]+)",m.group(1)))
base|=set(open('/home/nulifyer/Projects/karchy/install/packages/base.txt').read().split()) if __import__('os').path.exists('/home/nulifyer/Projects/karchy/install/packages/base.txt') else set()

out=[]
for m in merged:
    # category: prefer prog, then catalog, then distros, then linutil
    order={'prog':0,'catalog':1,'distros':2,'linutil':3}
    via,sub=sorted(m['subs'],key=lambda x:order[x[0]])[0]
    cat=cat_of(via,sub,m['name'])
    if via=='prog':
        cat={'Languages':'Languages','Editors & IDEs':'Editors & IDEs','Git':'Developer tools','Terminal tools':'Developer tools','APIs & databases':'Databases & APIs','Cloud & containers':'Cloud & containers','AI coding':'AI'}.get(sub,cat)
    inbase = m['base'] or (bool(m['pkgs']) and all(p in base for p in m['pkgs'][:1]))
    src=sorted(m['sources'])
    n=len(m['sources'] - {'You use it','Dev surveys'})
    skip='; '.join(sorted(m['skip']))
    yes = any(p.startswith('Yes') for p in m['picks'])
    maybe = any(p.startswith('Maybe') for p in m['picks'])
    rec = (not skip and not inbase and m['pkgs'] and
           (yes or 'You use it' in m['sources'] or ('Omarchy' in m['sources'] and n>=1) or n>=3 or ('CachyOS' in m['sources'] and n>=2)))
    first=(m['pkgs'] or [''])[0]
    for pkgset,c in OVR:
        if first in pkgset: cat=c
    if cat=='Chat': cat='Chat & email'
    if first=='GeForceNOWSetup.bin': skip='needs Flatpak'; rec=False
    out.append(dict(name=m['name'], cat=cat, pkgs=m['pkgs'][:6], repo=sorted(m['repo']), setup=m['setup'][:220], sources=src, n=n,
                    skip=skip[:160], base=inbase, rec=bool(rec), aur=('aur' in m['repo'] and not ({'extra','core','cachyos','multilib','omarchy'} & m['repo'])),
                    pick=(m['picks'][0] if m['picks'] else ''), pop=m['pop']))
json.dump(out,open(D+'merged.json','w'),indent=0)
c=collections.Counter(o['cat'] for o in out); r=collections.Counter(o['cat'] for o in out if o['rec'])
print(len(rows),'rows ->',len(out),'entries;',sum(o['rec'] for o in out),'recommended;',sum(o['base'] for o in out),'in base;',sum(bool(o['skip']) for o in out),'skipped')
for k in FINAL: print(f'{k:22} {c[k]:4} rec {r[k]}')
