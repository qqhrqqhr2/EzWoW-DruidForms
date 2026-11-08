#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Druid Forms (docs/images/ui_*.png, settings_*.png).

The button, quick menu and settings window are rebuilt from the sizes, positions, colours
and texts in Modules/Forms.lua, UI/OptionsWindow.lua, Core/UIKit.lua, Core/Init.lua and
Core/Locales.lua (game pixels x scale). Form icons are simple flat shapes.
usage: python scripts/make_readme_images.py . [scratch dir]   (needs Google Chrome; standard library only)
"""
import base64
import json
import html
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/usr/bin/google-chrome", "/usr/bin/chromium",
]

# Core/Init.lua ns.Style
def rgb(c, a=None):
    r, g, b = (round(v * 255) for v in c[:3])
    return f"rgba({r},{g},{b},{c[3] if a is None and len(c) > 3 else (1 if a is None else a)})"

STYLE = {
    "bgPrimary": (0.071, 0.094, 0.122, 0.97), "bgSecondary": (0.114, 0.157, 0.192, 0.96),
    "bgInput": (0.047, 0.067, 0.086, 0.96), "bgAccent": (0.230, 0.150, 0.080, 0.96),
    "border": (0.204, 0.298, 0.357, 1.0), "textBody": (0.929, 0.957, 0.969, 1.0),
    "textMuted": (0.655, 0.725, 0.773, 1.0), "accent": (0.961, 0.604, 0.290, 1.0),
    "warning": (0.906, 0.486, 0.439, 1.0), "disabled": (0.388, 0.447, 0.482, 1.0),
}
C = {k: rgb(v) for k, v in STYLE.items()}
ACCENT = "#F59A4A"
FONT = "'Noto Sans KR','Malgun Gothic',sans-serif"

# Example character: a feral druid around level 40 (Moonkin Form not learned).
# Stance bar order = learn order: 1 bear, 2 aquatic, 3 cat, 4 travel.
FORMS = {
    "ko": {"bear": (1, "광포한 곰 변신"), "aquatic": (2, "수중 동물 변신"), "cat": (3, "표범 변신"), "travel": (4, "치타 변신")},
    "en": {"bear": (1, "Dire Bear Form"), "aquatic": (2, "Aquatic Form"), "cat": (3, "Cat Form"), "travel": (4, "Travel Form")},
}
FORM_ORDER = ["bear", "aquatic", "cat", "travel", "moonkin"]
DB = {"combatForm": "bear", "useAquatic": True, "useTravel": True, "indoorCat": True,
      "useModifiers": True, "showButton": True, "buttonSize": 40}
KEY = "F"


def build_macro(f, db):
    """Same lines as ns.BuildMacro() in Modules/Forms.lua."""
    # one /cast line, first true case wins; "!" never leaves a form you are already in
    lines, clauses = [], []

    def clause(cond, name):
        clauses.append(f"{cond} {name}")
    if db["useModifiers"]:
        lines += ["/cancelform [mod:alt]", "/stopmacro [mod:alt]"]
        if "bear" in f:
            clause("[mod:shift]", "!" + f["bear"][1])
        if "cat" in f:
            clause("[mod:ctrl]", "!" + f["cat"][1])
    kind = db["combatForm"]
    if kind != "caster" and kind not in f:
        kind = "bear" if "bear" in f else ("cat" if "cat" in f else "caster")
    outdoor = ("travel" if db["useTravel"] and "travel" in f else None) or ("cat" if "cat" in f else None) or ("bear" if "bear" in f else None)
    indoor = (("cat" if "cat" in f else None) or ("bear" if "bear" in f else None)) if db["indoorCat"] else None
    water = ("aquatic" if db["useAquatic"] and "aquatic" in f else None) or outdoor
    swim = db["useAquatic"] and "aquatic" in f
    if swim:
        clause("[swimming]", "!" + f["aquatic"][1])
    if kind == "caster":
        cond = "[combat" + (",nomod" if db["useModifiers"] else "") + (",noswimming" if swim else "") + "]"
        lines += ["/cancelform " + cond, "/stopmacro " + cond]
    else:
        clause("[combat]", "!" + f[kind][1])
    if water and not swim:
        clause("[swimming]", f[water][1])
    if outdoor:
        clause("[outdoors]", f[outdoor][1])
    if indoor:
        clause("[indoors]", f[indoor][1])
    if clauses:
        lines.append("/cast " + "; ".join(clauses))
    return lines


def read_locales(root):
    """koKR / enUS strings from Core/Locales.lua."""
    src = (root / "Core" / "Locales.lua").read_text(encoding="utf-8")
    out = {}
    for lang in ("koKR", "enUS"):
        m = re.search(lang + r"\s*=\s*\{(.*?)\n    \},", src, re.S)
        body = m.group(1)
        out[lang] = {k: v.replace("\\n", "\n") for k, v in re.findall(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', body)}
    return out


def read_version(root):
    m = re.search(r"^## Version:\s*(\S+)", (root / "EzWoW-DruidForms.toc").read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else ""


TEXT = {
    "ko": {
        "lead": "단축키 하나로 상황(물속·야외·실내·전투)에 맞는 드루이드 변신",
        "sLead": "/ezdf · 단축키, 전투 중 변신, 전투 밖 규칙, 화면 버튼, 지금 쓰는 매크로",
        "badge": "설정창", "langLabel": "한국어",
        "sitTitle": "한 번 누르면",
        "sitRows": [
            ("물속 (전투 중에도)", "aquatic", "수중 동물 변신 (켰을 때)"),
            ("전투 밖 · 야외", "travel", "여행 변신 (없으면 표범)"),
            ("전투 밖 · 실내", "cat", "표범 변신 (끌 수 있음)"),
            ("야외·실내에서 다시", "caster", "원래 모습 (전투 밖)"),
            ("전투 중", "bear", "고른 변신 · 기본 곰"),
            ("Shift / Ctrl / Alt (언제나)", "mods", "곰 / 표범 / 변신 풀기"),
        ],
        "sitFoot": "배운 변신만 씁니다. 전투 중·물속·Shift/Ctrl 변신은 다시 눌러도 풀리지 않습니다.",
        "drag": "Ctrl + 드래그",
        "notes": [
            ("화면 버튼", "왼쪽 클릭으로 변신합니다. 아이콘은 지금 누르면 될 변신으로 계속 바뀝니다."),
            ("단축키", "지정한 키가 오른쪽 위에 짧게 보입니다."),
            ("전투 중 변신", "왼쪽 아래 글자는 전투 중에 누르면 될 변신입니다."),
            ("빠른 설정 · 전투 중", "오른쪽 클릭으로 엽니다. 곰·표범·원래 모습·달빛야수 중 고르고, 배우지 않은 변신은 회색입니다."),
            ("빠른 설정 · 전투 밖", "물속·야외·실내 규칙과 Shift/Ctrl/Alt를 켜고 끕니다. 전투 중에 바꾸면 전투가 끝난 뒤 적용됩니다."),
            ("그 밖", "단축키 지정(설정 창에서 키 입력 대기), 설정 창 열기."),
            ("이동", "Ctrl을 누른 채 끌어서 옮깁니다. 위치는 저장되고 설정 창에서 초기화합니다."),
        ],
        "sNotes": [
            ("배운 변신 · 단축키", "누르고 쓸 키를 입력합니다(Esc 취소, 휠·마우스 버튼 가능). 키의 기존 동작이 바뀌거나 Shift/Ctrl + 그 키가 다른 기능에 쓰이고 있으면 대화창에 알려 줍니다."),
            ("전투 중 누르면", "곰 · 표범 · 원래 모습 · 달빛야수. 이미 그 변신이면 풀리지 않습니다."),
            ("전투 밖에서 누르면", "물속 → 수중(전투 중 물속도), 야외 → 여행, 실내 → 표범, 보조키 Shift = 곰 · Ctrl = 표범 · Alt = 풀기."),
            ("화면 버튼", "표시 여부, 크기 24~64, 위치 초기화. Ctrl + 드래그로 이동."),
            ("지금 쓰는 매크로", "설정대로 만든 매크로를 보여 줍니다. 길면 자동으로 나눠 실행하고, 창도 함께 늘어납니다."),
            ("언어 · 후원", "자동 + 8개 언어, 후원 링크 복사."),
        ],
        "note": "애드온 코드의 크기·좌표·색상·문구로 재현한 예시 화면입니다. 변신 아이콘은 단순한 도형이고, 주문 이름·단축키는 예시입니다.",
    },
    "en": {
        "lead": "One key for the right druid form: water, outdoors, indoors or combat",
        "sLead": "/ezdf · key, combat form, out-of-combat rules, on-screen button, current macro",
        "badge": "Settings", "langLabel": "English",
        "sitTitle": "One press does",
        "sitRows": [
            ("Swimming (also in combat)", "aquatic", "Aquatic Form (when enabled)"),
            ("Out of combat · outdoors", "travel", "Travel Form, else Cat"),
            ("Out of combat · indoors", "cat", "Cat Form (optional)"),
            ("Again, outdoors / indoors", "caster", "Caster form (out of combat)"),
            ("In combat", "bear", "Your choice · Bear by default"),
            ("Shift / Ctrl / Alt, any time", "mods", "Bear / Cat / leave form"),
        ],
        "sitFoot": "Only learned forms are used. Combat, swimming and Shift/Ctrl forms are kept when you press again.",
        "drag": "Ctrl + drag",
        "notes": [
            ("On-screen button", "Left-click to shift. The icon always shows the form the next press gives."),
            ("Key", "The bound key, shortened, in the top right corner."),
            ("Combat form", "The bottom-left label is the form a press in combat goes to."),
            ("Quick menu · combat", "Right-click to open. Pick Bear, Cat, Caster or Moonkin; forms you have not learned are grey."),
            ("Quick menu · out of combat", "Toggle the water / outdoors / indoors rules and Shift/Ctrl/Alt. Changes made in combat apply when it ends."),
            ("More", "Set the key (opens settings and waits for a key), open settings."),
            ("Move", "Hold Ctrl and drag. The position is saved; reset it in settings."),
        ],
        "sNotes": [
            ("Learned forms · key", "Click, then press the key (Esc cancels; wheel and mouse buttons work). Chat tells you when the key's old action is replaced or when Shift/Ctrl + that key is bound to something else."),
            ("In combat", "Bear · Cat · Caster · Moonkin. Already in that form: it stays."),
            ("Out of combat", "Water → Aquatic (also in combat), outdoors → Travel, indoors → Cat, Shift = Bear · Ctrl = Cat · Alt = leave form."),
            ("On-screen button", "Show or hide, size 24–64, reset position. Ctrl + drag moves it."),
            ("Current macro", "The macro built from your settings. A long one is split up and run in parts automatically; the window grows with it."),
            ("Language · donate", "Automatic + 8 languages, copy the donate link."),
        ],
        "note": "Mock-ups rebuilt from the sizes, coordinates, colours and strings in the addon code. Form icons are flat shapes; spell names and the key are examples.",
    },
}

# flat form icons: (background, shapes) on a 100x100 view box
def form_svg(kind, size):
    art = {
        "bear": ("#3a2414", '<circle cx="28" cy="30" r="13" fill="#8a5a32"/><circle cx="72" cy="30" r="13" fill="#8a5a32"/>'
                 '<circle cx="50" cy="56" r="32" fill="#8a5a32"/><ellipse cx="50" cy="68" rx="15" ry="11" fill="#c89a6a"/>'
                 '<circle cx="50" cy="63" r="5" fill="#2a1a0e"/><circle cx="38" cy="48" r="4" fill="#2a1a0e"/><circle cx="62" cy="48" r="4" fill="#2a1a0e"/>'),
        "cat": ("#33240c", '<path d="M22 18 L40 40 L60 40 L78 18 L82 60 Q50 92 18 60 Z" fill="#d9a441"/>'
                '<path d="M34 54 L44 50 L44 56 Z M66 54 L56 50 L56 56 Z" fill="#1d1406"/><path d="M46 66 H54 L50 71 Z" fill="#1d1406"/>'),
        "aquatic": ("#0e2836", '<ellipse cx="50" cy="48" rx="32" ry="22" fill="#6fb3d6"/><path d="M76 46 L94 30 L92 64 Z" fill="#6fb3d6"/>'
                    '<circle cx="34" cy="42" r="4" fill="#0e2836"/><path d="M8 82 Q22 72 36 82 T64 82 T92 82" stroke="#9fd6f0" stroke-width="6" fill="none"/>'),
        "travel": ("#26301a", '<ellipse cx="50" cy="62" rx="20" ry="16" fill="#d8c08a"/><circle cx="26" cy="40" r="9" fill="#d8c08a"/>'
                   '<circle cx="42" cy="26" r="9" fill="#d8c08a"/><circle cx="60" cy="26" r="9" fill="#d8c08a"/><circle cx="76" cy="40" r="9" fill="#d8c08a"/>'),
        "moonkin": ("#22183a", '<path d="M62 16 A34 34 0 1 0 84 70 A27 27 0 1 1 62 16 Z" fill="#c9b6ff"/>'),
        "caster": ("#173020", '<path d="M50 88 C18 64 20 32 50 12 C80 32 82 64 50 88 Z" fill="#7cc46a"/><path d="M50 84 V24" stroke="#173020" stroke-width="5"/>'),
    }
    bg, shapes = art[kind]
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 100 100" style="display:block"><rect width="100" height="100" fill="{bg}"/>'
            f'{shapes}<rect width="100" height="100" fill="url(#shade)"/></svg>')


SHADE = ('<svg width="0" height="0" style="position:absolute"><defs><linearGradient id="shade" x1="0" y1="0" x2="1" y2="1">'
         '<stop offset="0" stop-color="#fff" stop-opacity=".16"/><stop offset=".55" stop-color="#000" stop-opacity="0"/>'
         '<stop offset="1" stop-color="#000" stop-opacity=".35"/></linearGradient></defs></svg>')

CSS = f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{ height: 100%; }}
body {{ width: 1600px; overflow: hidden; background-color: #0d0c0a; background: radial-gradient(ellipse at 30% 0%, #2a2118 0%, #15130f 55%, #0d0c0a 100%);
  font-family: {FONT}; color: {C['textBody']}; }}
.page {{ position: relative; padding: 34px 50px 0; }}
h1 {{ color: {ACCENT}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {ACCENT}; color: #1a1206; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #ddd6cd; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.nw {{ white-space: nowrap; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {ACCENT}; color: #1d1405; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #1a1206; box-shadow: 0 0 0 2px {ACCENT}55; z-index: 5; }}
.note {{ display: flex; gap: 12px; margin-bottom: 11px; font-size: 16.5px; line-height: 1.5; color: #e6e1da; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {ACCENT}; color: #1d1405; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; margin-top: 1px; }}
.note b {{ color: #fff; }}
.foot {{ color: #8c857c; font-size: 13.5px; }}
.wbtn {{ position: absolute; border: 1px solid {C['border']}; background: {C['bgSecondary']}; color: {C['textBody']};
  display: flex; align-items: center; justify-content: center; white-space: nowrap; overflow: hidden; }}
.wbtn.acc {{ background: {C['bgAccent']}; border-color: {ACCENT}; color: {ACCENT}; }}
.wbtn.off {{ color: {C['disabled']}; }}
.check {{ position: absolute; border: 1px solid #6d6a5d; background: #191919; border-radius: 2px; }}
.check::after {{ content: '✔'; position: absolute; left: 12%; top: -26%; font-size: 112%; color: #ffd200; text-shadow: 0 0 1px #000; }}
"""


def esc(s):
    return html.escape(s, quote=False)


class G:
    """Game-pixel helper: positions in game px, multiplied by the scale."""
    def __init__(self, scale):
        self.s = scale

    def __call__(self, v):
        return f"{v * self.s:.2f}px"

    def box(self, x, y, w=None, h=None):
        st = f"left:{self(x)};top:{self(y)};"
        if w is not None:
            st += f"width:{self(w)};"
        if h is not None:
            st += f"height:{self(h)};"
        return st


def note_list(items, start=1):
    return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {esc(b)}</div></div>'
                   for i, (a, b) in enumerate(items))


# ---------------------------------------------------------------------------
# ui page: on-screen button + quick menu, and the "situation -> form" panel
# ---------------------------------------------------------------------------
def ui_page(lang, L, icon_uri):
    t = TEXT[lang]
    f = FORMS[lang]
    g = G(1.8)
    p = []
    # in-game area
    sx, sy, sw, sh = 50, 160, 730, 690
    p.append(f'<div class="abs" style="left:{sx}px;top:{sy}px;width:{sw}px;height:{sh}px;border-radius:10px;'
             'background:linear-gradient(170deg,#24301f 0%,#1b2418 45%,#141a12 100%);border:1px solid #3a3a2c;'
             'box-shadow:inset 0 0 80px #0008"></div>')
    # quick menu: 240 wide, ROW_H 20, rows from y=4, inset 3; above the button (button in lower half)
    rows = [("h", "secCombat")]
    rows += [("r", k, k == "caster" or k in f) for k in ("bear", "cat", "caster", "moonkin")]
    rows += [("h", "secPlace")]
    rows += [("c", "useAquatic", "aquatic" in f), ("c", "useTravel", "travel" in f), ("c", "indoorCat", True), ("c", "useModifiers", True)]
    rows += [("h", "secMore"), ("a", "setKey"), ("a", "options")]
    mw, mh = 240, len(rows) * 20 + 8
    bsize = DB["buttonSize"]
    mx = 120                                   # page px
    my = sy + 46
    bx_page, by_page = mx, my + (mh + 4) * g.s
    menu = [f'<div class="abs" style="left:{mx}px;top:{my}px;width:{g(mw)};height:{g(mh)};background:{rgb(STYLE["bgPrimary"], .98)};'
            f'border:1px solid {ACCENT};font-size:{g(10)}">']
    section_y = {}
    for i, row in enumerate(rows):
        y = 4 + i * 20
        inner = f'left:{g(3)};top:{g(y)};width:{g(mw - 6)};height:{g(20)};'
        if row[0] == "h":
            section_y[row[1]] = y
            menu.append(f'<div class="abs nw" style="{inner}display:flex;align-items:center;padding-left:{g(8)};color:{ACCENT}">{esc(L[row[1]])}</div>')
            continue
        if row[0] == "r":
            text, on, avail = L["form_" + row[1]], DB["combatForm"] == row[1], row[2]
        elif row[0] == "c":
            text, on, avail = L["opt_" + row[1]], DB[row[1]], row[2]
        else:
            text, on, avail = L["menu_" + row[1]], None, True
        color = (ACCENT if on else C["textBody"]) if avail else C["disabled"]
        mark = ""
        if row[0] in ("r", "c"):
            base = STYLE["accent"] if (avail and on) else (STYLE["textBody"] if avail else STYLE["disabled"])
            mark = (f'<div class="abs" style="left:{g(10)};top:{g(5)};width:{g(10)};height:{g(10)};'
                    f'background:{rgb(base, 1 if on else 0.25)}"></div>')
        menu.append(f'<div class="abs" style="{inner}">{mark}<div class="abs nw" style="left:{g(28)};top:0;height:{g(20)};'
                    f'display:flex;align-items:center;color:{color}">{esc(text)}</div></div>')
    menu.append('</div>')
    p += menu
    # the button (bgSecondary, 1px border, icon inset 2, hotkey TOPRIGHT -3,-3, combat label BOTTOMLEFT 3,3)
    combat_short = L["short_" + DB["combatForm"]]
    p.append(f'<div class="abs" style="left:{bx_page}px;top:{by_page:.1f}px;width:{g(bsize)};height:{g(bsize)};'
             f'background:{C["bgSecondary"]};border:1px solid {C["border"]}">'
             f'<div class="abs" style="left:{g(1)};top:{g(1)}">{form_svg("travel", round((bsize - 4) * g.s))}</div>'
             f'<div class="abs" style="right:{g(3)};top:{g(2)};font-size:{g(10)};color:#bdbdbd;font-weight:700;'
             f'text-shadow:1px 1px 0 #000">{KEY}</div>'
             f'<div class="abs nw" style="left:{g(3)};bottom:{g(2)};font-size:{g(10)};color:{ACCENT};font-weight:700;'
             f'text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000">{esc(combat_short)}</div></div>')
    # ctrl-drag ghost
    bw = bsize * g.s
    gx = bx_page + bw + 150
    p.append(f'<div class="abs" style="left:{gx}px;top:{by_page:.1f}px;width:{bw}px;height:{bw}px;border:2px dashed {ACCENT}99;border-radius:2px"></div>')
    ax1, ax2, ay = bx_page + bw + 44, gx - 12, by_page + bw / 2
    p.append(f'<svg class="abs" style="left:{ax1}px;top:{ay - 12:.1f}px" width="{ax2 - ax1}" height="24">'
             f'<line x1="0" y1="12" x2="{ax2 - ax1 - 12}" y2="12" stroke="{ACCENT}" stroke-width="3"/>'
             f'<path d="M{ax2 - ax1 - 14} 3 L{ax2 - ax1} 12 L{ax2 - ax1 - 14} 21 Z" fill="{ACCENT}"/></svg>')
    p.append(f'<div class="abs nw" style="left:{ax1}px;top:{ay + 16:.1f}px;width:{ax2 - ax1}px;text-align:center;font-size:15px;'
             f'color:{ACCENT}">{esc(t["drag"])}</div>')
    # callouts
    cx = mx - 44
    calls = [
        (cx, by_page + bw / 2 - 15),                                  # 1 button
        (bx_page + bw + 6, by_page + 1),                              # 2 hotkey
        (cx, by_page + bw - 14),                                      # 3 combat label
        (mx + mw * g.s + 14, my + (section_y["secCombat"] + 50) * g.s - 15),
        (mx + mw * g.s + 14, my + (section_y["secPlace"] + 50) * g.s - 15),
        (mx + mw * g.s + 14, my + (section_y["secMore"] + 30) * g.s - 15),
        (gx + bw + 14, ay - 15),                                      # 7 move
    ]
    # keep 1 and 3 apart
    if abs(calls[2][1] - calls[0][1]) < 34:
        calls[0] = (cx, calls[0][1] - 20)
        calls[2] = (cx, calls[2][1] + 14)
    p += [f'<div class="call" style="left:{x:.0f}px;top:{y:.0f}px">{i}</div>' for i, (x, y) in enumerate(calls, 1)]

    # situation -> form panel (EzWoW panel look)
    px0, py0, pw = 830, 160, 720
    rowh = 66
    sit = [f'<div class="abs" style="left:{px0}px;top:{py0}px;width:{pw}px;background:{C["bgPrimary"]};border:1px solid {C["border"]}">'
           f'<div style="height:58px;background:{rgb(STYLE["bgSecondary"], .98)};border-bottom:2px solid {ACCENT};display:flex;align-items:center;gap:12px;padding-left:16px">'
           f'<img src="{icon_uri}" style="width:34px;height:34px"><div style="color:{ACCENT};font-size:21px;font-weight:600">{esc(t["sitTitle"])}</div></div>'
           '<div style="padding:10px 18px 4px">']
    for i, (cond, kind, result) in enumerate(t["sitRows"]):
        if kind == "mods":
            icon = ('<div style="display:flex;gap:4px">' + "".join(
                f'<div style="width:30px;height:30px;border:1px solid {C["border"]}">{form_svg(k, 28)}</div>' for k in ("bear", "cat", "caster")) + '</div>')
            iw = 124
        else:
            icon = f'<div style="width:46px;height:46px;border:1px solid {C["border"]}">{form_svg(kind, 44)}</div>'
            iw = 124
        bg = "background:rgba(255,255,255,.025);" if i % 2 == 0 else ""
        sit.append(f'<div style="display:flex;align-items:center;height:{rowh}px;{bg}padding:0 10px">'
                   f'<div style="width:250px;font-size:17px;color:{C["textMuted"]}">{esc(cond)}</div>'
                   f'<div style="width:36px;color:{ACCENT};font-size:20px">→</div>'
                   f'<div style="width:{iw}px;display:flex;justify-content:flex-start">{icon}</div>'
                   f'<div style="flex:1;font-size:17.5px;color:{C["textBody"]}">{esc(result)}</div></div>')
    sit.append(f'<div style="margin:10px 10px 14px;font-size:14.5px;color:{C["textMuted"]};line-height:1.5">{esc(t["sitFoot"])}</div></div></div>')
    p += sit

    notes_top = sy + sh + 34
    left, right = t["notes"][:4], t["notes"][4:]
    p.append(f'<div class="abs" style="left:50px;top:{notes_top}px;width:720px">{note_list(left, 1)}</div>')
    p.append(f'<div class="abs" style="left:830px;top:{notes_top}px;width:720px">{note_list(right, 5)}</div>')
    p.append(f'<div id="foot" class="abs foot" style="left:50px">{esc(t["note"])}</div>')
    head = f'<div class="page"><h1>EzWoW - Druid Forms</h1><div class="lead">{esc(t["lead"])}</div></div>'
    script = ("<script>(function(){var b=0;document.querySelectorAll('.abs').forEach(function(e){if(e.id!=='foot'){"
              "var r=e.getBoundingClientRect();if(r.bottom>b)b=r.bottom;}});var f=document.getElementById('foot');"
              "f.style.top=(b+40)+'px';document.body.setAttribute('data-h',Math.ceil(b+40+f.offsetHeight+30));})();</script>")
    return head + "".join(p) + script


# ---------------------------------------------------------------------------
# settings page: UI/OptionsWindow.lua
# ---------------------------------------------------------------------------
def settings_page(lang, L, icon_uri, version):
    t = TEXT[lang]
    f = FORMS[lang]
    g = G(1.36)
    W = 440
    ox, oy = 72, 160
    p = []

    def lbl(x, y, text, size, color, extra=""):
        p.append(f'<div class="abs nw" style="{g.box(x, y)}font-size:{g(size)};color:{color};{extra}">{esc(text)}</div>')

    def btn(x, y, w, h, text, size, cls="", extra=""):
        p.append(f'<div class="wbtn {cls}" style="{g.box(x, y, w, h)}font-size:{g(size)};{extra}">{esc(text)}</div>')

    def section(key, y):
        lbl(20, y, L[key], 13, ACCENT)
        p.append(f'<div class="abs" style="{g.box(20, y + 20, W - 40, 1)}background:{rgb(STYLE["border"], .85)}"></div>')

    # header (58 high, bgSecondary .98, accent line 2 at the bottom)
    p.append(f'<div class="abs" style="{g.box(1, 1, W - 2, 58)}background:{rgb(STYLE["bgSecondary"], .98)}">'
             f'<div class="abs" style="left:0;right:0;bottom:0;height:{g(2)};background:{ACCENT}"></div></div>')
    p.append(f'<img class="abs" src="{icon_uri}" style="{g.box(15, 15, 28, 28)}">')
    lbl(49, 10, "EzWoW - Druid Forms", 16, ACCENT)
    lbl(49, 32, L["settingsSub"], 10, C["textMuted"])
    btn(W - 1 - 10 - 22, 11, 22, 22, "X", 12)

    names = [f[k][1] for k in FORM_ORDER if k in f]
    p.append(f'<div class="abs" style="{g.box(22, 68, 396)}font-size:{g(10)};color:{C["textMuted"]};line-height:1.25">'
             f'{esc(L["learned"] + " " + ", ".join(names))}</div>')
    section("secKey", 104)
    btn(20, 130, 290, 34, L["keyIs"].replace("%s", KEY), 12, "acc")
    btn(316, 130, 104, 34, L["keyClear"], 11)
    section("secCombat", 182)
    for i, kind in enumerate(("bear", "cat", "caster", "moonkin")):
        avail = kind == "caster" or kind in f
        cls = "acc" if (avail and DB["combatForm"] == kind) else ("" if avail else "off")
        btn(20 + i * 101, 208, 97, 28, L["form_" + kind], 11, cls)
    section("secPlace", 254)

    def option(y, key):
        p.append(f'<div class="check" style="{g.box(23, y + 3, 18, 18)}"></div>')
        lbl(48, y + 5, L["opt_" + key], 12, C["textBody"])
    for y, key in ((278, "useAquatic"), (304, "useTravel"), (330, "indoorCat"), (356, "useModifiers")):
        option(y, key)
    section("secButton", 394)
    option(418, "showButton")
    p.append(f'<div class="abs" style="{g.box(24, 450, 392)}font-size:{g(10)};color:{C["textMuted"]};line-height:1.25">{esc(L["moveHint"])}</div>')
    lbl(24, 480, L["buttonSize"], 12, C["textBody"])
    btn(150, 473, 27, 27, "-", 16)
    p.append(f'<div class="abs" style="{g.box(181, 479, 40)}text-align:center;font-size:{g(12)}">{DB["buttonSize"]}</div>')
    btn(225, 473, 27, 27, "+", 16)
    btn(270, 473, 150, 27, L["resetPos"], 11)
    section("secMacro", 516)
    macro = "\n".join(build_macro(f, DB))
    p.append(f'<div id="macro" class="abs" style="{g.box(22, 542, 396)}font-size:{g(10)};color:{C["textMuted"]};'
             f'line-height:1.25;white-space:pre-wrap;overflow-wrap:anywhere">{esc(macro)}</div>')
    # bottom row: anchored BOTTOMLEFT 20,32 / BOTTOMRIGHT -20,32 / foot BOTTOM 0,12 -> placed by the script
    lang_label = f'{L["language"]}: {t["langLabel"]} ▼'
    p.append(f'<div id="langBtn" class="wbtn" style="left:{g(20)};width:{g(197)};height:{g(28)};font-size:{g(12)}">{esc(lang_label)}</div>')
    p.append(f'<div id="donBtn" class="wbtn acc" style="left:{g(W - 20 - 197)};width:{g(197)};height:{g(28)};font-size:{g(12)}">{esc(L["donate"])}</div>')
    foot = "EzWoW - Druid Forms" + (f" v{version}" if version else "") + "  ·  /ezdf"
    p.append(f'<div id="wfoot" class="abs nw" style="left:0;width:100%;text-align:center;font-size:{g(10)};color:#808080">{esc(foot)}</div>')

    win = (f'<div id="win" class="abs" style="left:{ox}px;top:{oy}px;width:{g(W)};background:{C["bgPrimary"]};'
           f'border:1px solid {C["border"]}">' + "".join(p) + '</div>')
    # callouts next to the window, per block
    blocks = [(68, 172), (182, 244), (254, 384), (394, 506), (516, None), (None, None)]
    calls = "".join(f'<div class="call" id="c{i}" style="left:{ox + W * g.s + 16:.0f}px">{i}</div>' for i in range(1, 7))
    nx = ox + W * g.s + 76
    notes = f'<div class="abs" style="left:{nx:.0f}px;top:{oy + 6}px;width:{1600 - nx - 50:.0f}px">{note_list(t["sNotes"])}</div>'
    head = (f'<div class="page"><h1>EzWoW - Druid Forms <span class="badge">{esc(t["badge"])}</span></h1>'
            f'<div class="lead">{esc(t["sLead"])}</div></div>')
    S = g.s
    script = f"""<script>(function(){{
var S={S}, oy={oy};
var m=document.getElementById('macro'); var mh=m.getBoundingClientRect().height/S;
var H=Math.max(600, Math.ceil(542+mh+84));
var win=document.getElementById('win'); win.style.height=(H*S)+'px';
['langBtn','donBtn'].forEach(function(id){{document.getElementById(id).style.top=((H-32-28)*S)+'px';}});
var wf=document.getElementById('wfoot'); wf.style.top=((H-12)*S-wf.offsetHeight)+'px';
var spans={json.dumps(blocks)};
spans[4]=[516, 542+mh]; spans[5]=[H-60, H-32];
for(var i=0;i<6;i++){{var c=document.getElementById('c'+(i+1));c.style.top=(oy+(spans[i][0]+spans[i][1])/2*S-15)+'px';}}
var f=document.getElementById('foot'); var b=oy+H*S;
f.style.top=(b+30)+'px';
document.body.setAttribute('data-h',Math.ceil(b+30+f.offsetHeight+30));
document.body.setAttribute('data-macro',Math.round(mh));
}})();</script>"""
    return head + win + calls + notes + f'<div id="foot" class="abs foot" style="left:50px">{esc(t["note"])}</div>' + script


# ---------------------------------------------------------------------------
def find_chrome():
    for c in CHROME_CANDIDATES:
        if os.path.exists(c):
            return c
    sys.exit("Google Chrome not found")


def render(chrome, html_path, png_path, profile):
    url = Path(html_path).resolve().as_uri()
    base = [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={profile}"]
    # output goes to files, not pipes: a helper process Chrome leaves behind can keep a
    # pipe open and make the call wait forever
    dom_path = Path(html_path).with_suffix(".dom.txt")
    with open(dom_path, "wb") as fh:
        subprocess.run(base + ["--window-size=1600,2000", "--dump-dom", url], stdout=fh,
                       stderr=subprocess.DEVNULL, timeout=120)
    dom = dom_path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'data-h="(\d+)"', dom)
    height = int(m.group(1)) if m else 1400
    mm = re.search(r'data-macro="(\d+)"', dom)
    subprocess.run(base + [f"--window-size=1600,{height}", f"--screenshot={png_path}", url],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    return height, (mm.group(1) if mm else None)


def main(root: Path):
    root = root.resolve()
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    icon_uri = "data:image/png;base64," + base64.b64encode((root / "Media" / "Icon.png").read_bytes()).decode()
    loc = read_locales(root)
    version = read_version(root)
    chrome = find_chrome()
    # optional 2nd argument: a scratch folder for the html pages and the browser profile
    work = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix="ezdf_img_"))
    work.mkdir(parents=True, exist_ok=True)
    profile = work / "chrome_tmp_EzWoW-DruidForms"
    for lang, code in (("ko", "koKR"), ("en", "enUS")):
        L = dict(loc["enUS"])
        L.update(loc[code])
        pages = {"ui": ui_page(lang, L, icon_uri), "settings": settings_page(lang, L, icon_uri, version)}
        for name, body in pages.items():
            doc = (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>'
                   f'<body>{SHADE}{body}</body></html>')
            hp = work / f"{name}_{lang}.html"
            hp.write_text(doc, encoding="utf-8")
            png = out / f"{name}_{lang}.png"
            h, macro_h = render(chrome, hp, png, profile)
            print("wrote", png, h, f"(macro {macro_h} game px)" if macro_h else "")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
