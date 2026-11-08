#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Frame Mover (docs/images/ui_*.png, settings_*.png).

The settings window, the scale toast, the hover guide tooltip and the quest tracker
are rebuilt from the sizes, coordinates, colours and strings in the addon code
(UI/OptionsWindow.lua, UI/QuestTracker.lua, Modules/MoverEngine.lua DEFAULTS,
Core/Locales.lua), in game pixels x scale. The character window is a simplified
drawing of the default game window; quests and character names are made up.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
"""
import base64
import html
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PAGE_W = 1600
CALL = "#7aa2f7"

# ---------------------------------------------------------------------------
# Values read from the Lua code
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def parse_style(src):
    block = re.search(r"local STYLE = \{(.*?)\n\}", src, re.S).group(1)
    return {k: [float(v) for v in body.split(",")] for k, body in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", block)}


def parse_consts(src):
    return {k: int(v) for k, v in re.findall(r"^local ([A-Z_]+) = (-?\d+)\b(?!\.)", src, re.M)}


def parse_defaults(src):
    block = re.search(r"ns\.DEFAULTS = \{(.*?)\n\}", src, re.S).group(1)
    out = {}
    for k, v in re.findall(r"^\s*(\w+)\s*=\s*([^,\n]+),", block, re.M):
        v = v.strip()
        out[k] = True if v == "true" else False if v == "false" else v.strip('"')
    return out


def parse_locale(src, var, code):
    start = src.index(f"local {var} = {{")
    end = src.index("\n}", start)
    out = {k: v.replace('\\"', '"').replace("\\n", "\n")
           for k, v in re.findall(r'^\s*(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', src[start:end], re.M)}
    # strings added later as ns.Locales.xxXX["KEY"] = "..."
    for k, v in re.findall(rf'^ns\.Locales\.{code}\["(\w+)"\] = "((?:[^"\\]|\\.)*)"', src, re.M):
        out[k] = v.replace('\\"', '"').replace("\\n", "\n")
    return out


def parse_options(src):
    """Window size, section headers, check boxes, buttons and the status box of UI/OptionsWindow.lua."""
    size = re.search(r'windowFrame:SetSize\((\d+), (\d+)\)', src)
    sections = {name: int(y) for name, y in re.findall(r"windowFrame\.(\w+) = SettingsDialog\.buildSectionHeader\(windowFrame, (-?\d+)\)", src)}
    checks = {}
    for name, x, y in re.findall(r"windowFrame\.(\w+) = SettingsDialog\.buildFlatCheckbox\(windowFrame, (\d+), (-?\d+)", src):
        checks[name] = {"x": int(x), "y": int(y), "w": 440}
    qw = int(re.search(r"rowWidget:SetWidth\((\d+)\)", src).group(1))
    for name, x, y, field in re.findall(r'windowFrame\.(\w+) = questCheck\((\d+), (-?\d+), "(\w+)"\)', src):
        checks[name] = {"x": int(x), "y": int(y), "w": qw}
    for name, key in re.findall(r'setFittedLabel\(windowFrame\.(\w+), self:L\("(\w+)"\)\)', src):
        if name in checks:
            checks[name]["label"] = key
    for name, field, op in re.findall(r"windowFrame\.(\w+):SetChecked\(savedDB\.(\w+) (~= false|== true)\)", src):
        checks[name]["field"], checks[name]["op"] = field, op
    buttons = {}
    for name, w, h in re.findall(r'windowFrame\.(\w+) = SettingsDialog\.buildFlatButton\(\w+, (\d+), (\d+), ""', src):
        buttons[name] = {"w": int(w), "h": int(h)}
    for name, side, y in re.findall(r'windowFrame\.(\w+):SetPoint\("(TOPLEFT|TOPRIGHT)", windowFrame, "\w+", -?\d+, (-?\d+)\)', src):
        buttons[name]["side"], buttons[name]["y"] = side, -int(y)
    for name, key in re.findall(r'setFittedLabel\(windowFrame\.(btn\w+), self:L\("(\w+)"\)\)', src):
        buttons[name]["label"] = key
    status = re.search(r'statusBox:SetPoint\("TOPLEFT", windowFrame, "TOPLEFT", (\d+), (-?\d+)\).*?statusBox:SetHeight\((\d+)\)', src, re.S)
    managed = re.search(r"local QUEST_OPTION_ROWS = \{(.*?)\}", src, re.S).group(1)
    return {
        "size": (int(size.group(1)), int(size.group(2))),
        "sections": sections, "checks": checks, "buttons": buttons,
        "status": (int(status.group(1)), -int(status.group(2)), int(status.group(3))),
        "managed": re.findall(r'"(\w+)"', managed),
    }


def parse_version(src):
    m = re.search(r"^## Version:\s*(\S+)", src, re.M)
    return m.group(1) if m else ""


def css(c, alpha=None, mul=1.0):
    r, g, b = (round(min(1, v * mul) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


def hexc(c):
    return "#%02x%02x%02x" % tuple(round(v * 255) for v in c[:3])


# ---------------------------------------------------------------------------
# Game colour rules used by the tracker
# ---------------------------------------------------------------------------
PLAYER_LEVEL = 11


def difficulty(level):
    """Client quest difficulty colours relative to the player level."""
    d = level - PLAYER_LEVEL
    if d >= 5:
        return "#ff1a1a"
    if d >= 3:
        return "#ff8040"
    if d >= -2:
        return "#ffd100"
    if d >= -8:
        return "#40bf40"
    return "#808080"


def progress(have, need, finished=False):
    """resolveObjectiveProgressHex in UI/QuestTracker.lua."""
    if finished or (need and have >= need):
        return "#40ff59"
    if have <= 0:
        return "#dce6ec"
    pct = max(0.0, min(1.0, have / need))
    if pct < 0.5:
        v = pct * 2
        r, g, b = 1.0, 0.55 + 0.35 * v, 0.38 - 0.08 * v
    else:
        v = (pct - 0.5) * 2
        r, g, b = 1.0 - 0.45 * v, 0.90 + 0.10 * v, 0.30 + 0.05 * v
    return hexc((r, g, b))


# ---------------------------------------------------------------------------
# Texts (quests and names are made up; UI strings come from Core/Locales.lua)
# ---------------------------------------------------------------------------
T = {
    "ko": {
        "lead": "움직일 수 없던 기본 창을 끌어 옮기고 Ctrl + 휠로 크기 조절, 스크롤형 퀘스트 추적기와 퀘스트 자동화·파티 알림",
        "zones": ["엘윈 숲", "서부 몰락지대"],
        "q": {
            "wolf": "늑대 무리 쫓아내기", "wolfObj": "굶주린 회색 늑대 처치",
            "supply": "흩어진 보급품", "supplyObj": "보급 상자", "supplyObj2": "신호 피리 사용",
            "mine": "광산 정찰",
            "bandit": "들판의 도적단", "banditObj": "도적단 정찰병 처치", "banditObj2": "도적단 명령서",
            "crow": "허수아비 조사", "crowObj": "수상한 허수아비 조사",
            "late": "늦은 배달",
            "letter": "집으로 보내는 편지",
        },
        "charTitle": "캐릭터 정보",
        "charLine": "레벨 11 이끼발톱",
        "charTabs": ["캐릭터", "평판", "기술"],
        "ghost": "원래 위치",
        "me": "이끼발톱",
        "party": "파티",
        "notes": [
            ("끌어서 이동", "캐릭터 창, 마법책, 퀘스트 목록·대화창, 상점, 우편함, 은행, 친구·길드, 경매장, 특성, 업적, 달력 등 기본 창과 나중에 로드되는 창을 끌어 옮기고 위치를 저장합니다. 하위 영역을 잡아도 상위 창이 함께 움직이고, Alt + 드래그로 하위 창만 떼어 냅니다."),
            ("Ctrl + 휠 크기 조절", "창 위에서 Ctrl + 휠로 50~150%(5% 단위). 화면 위쪽에 바뀐 배율을 잠깐 알려 줍니다."),
            ("조작 안내 툴팁", "창에 마우스를 올리면 쓸 수 있는 조작과 현재 배율을 보여 줍니다(설정에서 끌 수 있음). Shift + 우클릭: 위치, Ctrl + 우클릭: 크기, Ctrl + Alt + 우클릭: 모두 초기화."),
            ("퀘스트 추적기", "기본 추적창 대신 쓰는 스크롤형 추적기. 머리줄 좌클릭: 접기·펼치기, 우클릭: 설정창. 지역별로 묶고 [레벨]을 난이도 색으로 표시합니다."),
            ("퀘스트 줄 · 목표 색", "목표 진행에 따라 흰색 → 주황 → 노랑 → 초록, (완료)·(실패)를 바로 표시. 좌클릭: 퀘스트 로그, Shift + 좌클릭: 채팅 링크, 우클릭: 목표 접기, Alt + 우클릭: 숨기기."),
            ("퀘스트 아이템 버튼", "사용 아이템이 있는 퀘스트는 왼쪽 버튼을 눌러 바로 씁니다."),
            ("크기 조절", "아래 모서리를 끌어 가로·세로 크기 조절(기본 270×360, 우클릭: 초기화). 긴 목록은 마우스 휠로 스크롤."),
            ("파티 진행 알림", "파티(인스턴스 그룹)에 퀘스트 수락·목표 진행·목표 달성·완료를 알립니다. 공격대에서는 보내지 않습니다."),
        ],
        "handover": "EzWoW - Quest가 함께 켜져 있으면 ④~⑧ 퀘스트 기능(추적기·자동화·파티 알림)은 EzWoW - Quest가 맡고, 이 애드온의 퀘스트 기능은 저절로 꺼집니다.",
        "foot": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 캐릭터 창은 기본 게임 창을 단순화한 그림이고, 퀘스트와 캐릭터 이름은 지어낸 예시입니다.",
        "sTitle": "설정창",
        "sLead": "/ezfm · /창이동 · 창 이동·크기 규칙, 퀘스트 추적기, 퀘스트 자동화, 저장 현황, 초기화 도구",
        "sNotes": [
            ("언어", "자동 또는 8개 언어 중 선택."),
            ("창 이동 및 크기 조절 규칙", "드래그 이동, 위치 계속 저장, Ctrl 누를 때만 이동, Ctrl + 휠 크기 조절, 화면 밖 이탈 방지, 우클릭 빠른 초기화, 조작 안내 툴팁."),
            ("퀘스트 추적 목록", "추적기 사용(끄면 게임 기본 추적창), 기본 추적창 숨기기, 모든 퀘스트 자동 표시, 지역 헤더·[레벨] 난이도 색, 반투명 배경. 추적기를 끄면 아래 항목은 흐려집니다."),
            ("퀘스트 자동화", "자동 수락(Shift를 누르고 대화하면 건너뜀)·자동 완료는 처음에 꺼져 있습니다. 반복·회색 퀘스트 제외, 판매가가 가장 높은 보상 표시, 아이템을 내는 퀘스트 제외, 파티 진행 알림(처음에 켜짐)."),
            ("저장 현황", "연결된 기본 창 수, 저장된 위치·크기 수와 간단한 사용법."),
            ("초기화 도구", "모든 창 위치 / 모든 창 크기(100%) / 지금 열린 창 초기화, 기본 창 다시 스캔."),
            ("하단", "설정 기본값 복원, 후원 주소 복사."),
        ],
        "sHand": ("EzWoW - Quest와 함께 쓸 때", "③·④ 항목은 흐려지고 제목 옆에 “(EzWoW - Quest에서 설정합니다)”가 붙습니다. 처음 실행할 때 이 애드온의 퀘스트 설정을 EzWoW - Quest가 한 번 가져갑니다."),
        "sFoot": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 체크 상태는 기본값이고, 저장 현황의 숫자는 예시입니다.",
    },
    "en": {
        "lead": "Drag fixed default windows anywhere, scale them with Ctrl + wheel, plus a scrollable quest tracker, quest automation and party messages",
        "zones": ["Elwynn Forest", "Westfall"],
        "q": {
            "wolf": "Driving Off the Wolf Pack", "wolfObj": "Hungry Grey Wolf slain",
            "supply": "Scattered Supplies", "supplyObj": "Supply Crate", "supplyObj2": "Signal Whistle used",
            "mine": "Scouting the Mine",
            "bandit": "Bandits in the Fields", "banditObj": "Bandit Scout slain", "banditObj2": "Bandit Orders",
            "crow": "The Scarecrow Survey", "crowObj": "Suspicious Scarecrow inspected",
            "late": "A Late Delivery",
            "letter": "A Letter Home",
        },
        "charTitle": "Character Info",
        "charLine": "Level 11 Mossclaw",
        "charTabs": ["Character", "Reputation", "Skills"],
        "ghost": "original spot",
        "me": "Mossclaw",
        "party": "Party",
        "notes": [
            ("Drag to move", "Character, Spellbook, Quest log and dialog, Merchant, Mail, Bank, Friends and Guild, Auction House, Talents, Achievements, Calendar and load-on-demand windows can be dragged; positions are saved. Dragging a sub-area moves the parent window; Alt + drag detaches the sub-frame."),
            ("Ctrl + wheel scaling", "Hold Ctrl and scroll over a window for 50–150% (5% steps). A short notice at the top shows the new scale."),
            ("Control guide tooltip", "Hovering a window lists the available controls and its current scale (can be turned off). Shift + right-click: position, Ctrl + right-click: scale, Ctrl + Alt + right-click: reset both."),
            ("Quest tracker", "A scrollable tracker that replaces the default one. Header left-click: collapse or expand, right-click: settings. Quests are grouped by zone with difficulty-coloured [Lv]."),
            ("Quest line · objective colours", "Objectives go white → orange → yellow → green as you progress; (Complete) and (Failed) show at once. Left-click: quest log, Shift + left-click: chat link, right-click: fold objectives, Alt + right-click: hide."),
            ("Quest item button", "Quests with a usable item get a button on the left; click it to use the item."),
            ("Resize", "Drag the bottom corner to resize (default 270×360, right-click: reset). Long lists scroll with the mouse wheel."),
            ("Party progress messages", "Tells your party (or instance group) when you accept a quest, make progress, finish the objectives and turn it in. Never sent in a raid."),
        ],
        "handover": "When EzWoW - Quest is enabled too, the quest features ④–⑧ (tracker, automation, party messages) are handled by EzWoW - Quest and the ones in this addon turn themselves off.",
        "foot": "Mock-up rebuilt from the window sizes, coordinates, colours and strings in the addon code. The character window is a simplified drawing of the default game window; quests and character names are made up.",
        "sTitle": "Settings",
        "sLead": "/ezfm · move & scale rules, quest tracker, quest automation, saved data, reset tools",
        "sNotes": [
            ("Language", "Auto or one of 8 languages."),
            ("Window drag & scale rules", "Drag to move, keep positions, require Ctrl to drag, Ctrl + wheel scaling, keep windows on screen, right-click quick resets, control guide tooltip."),
            ("Quest tracker", "Use the tracker (off = game default tracker), hide the default tracker, show all active quests, zone headers and difficulty-coloured [Lv], translucent background. The options below dim while the tracker is off."),
            ("Quest automation", "Auto accept (hold Shift while talking to skip) and auto turn-in start off. Skip repeatable and grey quests, mark the reward that sells for most, skip quests that take items, party progress messages (on by default)."),
            ("Saved data", "Hooked windows, saved positions and scales, plus a short guide."),
            ("Reset tools", "Reset all positions / all scales (100%) / open windows, rescan windows."),
            ("Bottom", "Restore defaults, copy the support link."),
        ],
        "sHand": ("With EzWoW - Quest", "Sections ③ and ④ dim and their titles read “(set in EzWoW - Quest)”. On its first start EzWoW - Quest takes over these quest settings once."),
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. Check boxes show the defaults; the saved-data numbers are examples.",
    },
}

# quests in the tracker: zone index, key, level, state (0 / 1 complete / -1 failed), objectives, item
QUESTS = [
    (0, "wolf", 8, 0, [("wolfObj", 5, 8)], False),
    (0, "supply", 9, 0, [("supplyObj", 1, 4), ("supplyObj2", 0, 1)], True),
    (0, "mine", 7, 1, [], False),
    (1, "bandit", 14, 0, [("banditObj", 0, 10), ("banditObj2", 0, 1)], False),
    (1, "crow", 12, 0, [("crowObj", 3, 4)], False),
    (1, "late", 11, -1, [], False),
]

# ---------------------------------------------------------------------------
# Page parts
# ---------------------------------------------------------------------------
S = 1.6  # game px -> page px (set per page)


def px(v):
    return f"{v * S:.2f}px"


def esc(s):
    return html.escape(s, quote=False)


SHADOW = "text-shadow:1px 1px 0 #000,0 0 2px rgba(0,0,0,.8);"
OUTLINE = "text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000,0 0 3px #000;"

CSS = f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ width: {PAGE_W}px; overflow: hidden; background: radial-gradient(ellipse at 30% 0%, #1f2a3d 0%, #121922 55%, #0b1014 100%);
  font-family: 'Noto Sans KR', 'Malgun Gothic', sans-serif; color: #edf4f7; }}
.page {{ position: relative; padding: 34px 50px 40px; }}
h1 {{ color: {CALL}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {CALL}; color: #0b1430; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; white-space: nowrap; line-height: 1; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {CALL}; color: #0b1430; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #0b1430; box-shadow: 0 0 0 2px {CALL}55; z-index: 50; }}
.notes {{ position: absolute; }}
.note {{ display: flex; gap: 12px; margin-bottom: 10px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {CALL}; color: #0b1430; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note .n.i {{ background: #e0af68; }}
.note b {{ color: #fff; }}
.hand {{ position: absolute; border: 1px solid #e0af6888; background: rgba(224,175,104,.08); border-radius: 6px; padding: 10px 14px;
  font-size: 15.5px; line-height: 1.5; color: #e9dcc6; }}
.foot {{ color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.fit {{ display: inline-block; }}
.tl {{ font-size: {10.5 * 1.6:.1f}px; line-height: {13 * 1.6:.1f}px; white-space: normal; {SHADOW} }}
"""

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
});
</script>
"""


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def notes_height(notes, width):
    h = 0
    for a, b in notes:
        chars = len(a) + len(b) + 3
        wide = sum(1 for ch in a + b if ord(ch) > 0x2e80)
        per_line = width / (8.4 + 7.4 * wide / chars)
        h += max(1, math.ceil(chars / per_line)) * 24 + 10
    return h


def note_html(start, lst, info=False):
    return "".join(f'<div class="note"><span class="n{" i" if info else ""}">{start + i if not info else "i"}</span>'
                   f'<div><b>{esc(a)}</b> — {esc(b)}</div></div>' for i, (a, b) in enumerate(lst))


# ---------------------------------------------------------------------------
# Quest tracker (UI/QuestTracker.lua)
# ---------------------------------------------------------------------------
ITEM_ICON = ('<svg viewBox="0 0 32 32" width="100%" height="100%"><defs><linearGradient id="ig" x1="0" y1="0" x2="1" y2="1">'
             '<stop offset="0" stop-color="#5b4a33"/><stop offset="1" stop-color="#231a10"/></linearGradient></defs>'
             '<rect width="32" height="32" fill="url(#ig)"/>'
             '<path d="M6 21 L20 9 Q24 6 26 9 Q28 12 24 15 L10 25 Z" fill="#c9ccd2" stroke="#2a2d33" stroke-width="1.5"/>'
             '<circle cx="23" cy="11" r="2.4" fill="#2a2d33"/><path d="M6 21 L10 25 L6 27 Z" fill="#e3b448"/></svg>')


def tracker(ctx, lang, ox, oy):
    """Returns (html, anchors, size) for the tracker placed at page px (ox, oy)."""
    t, L, st, k = T[lang], ctx["L"][lang], ctx["tstyle"], ctx["tconst"]
    W = k["TRACKER_DEFAULT_WIDTH"]
    BH = k["TRACKER_DEFAULT_HEIGHT"]
    HH = k["HEADER_HEIGHT"]
    PAD = k["LINE_PADDING_X"]
    p = []
    a = {}
    # header
    p.append(box(0, 0, W, HH, f"background:{css(st['header'])};border:1px solid {css(st['border'])}"))
    p.append(box(1, HH - 1, W - 2, 1, f"background:{css(st['accent'])}"))
    p.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{px(6)};top:{px((HH - 16) / 2)};width:{px(16)};height:{px(16)}">')
    p.append(f'<div class="t" style="left:{px(28)};top:{px(HH / 2)};transform:translate(0,-50%);font-size:{px(10.5)};color:{css(st["text"])};{SHADOW}">'
             f'{esc(L["TRACKER_HEADER_FORMAT"].replace("%d", "{}").format(len(QUESTS), 20))}</div>')
    p.append(f'<div class="t" style="right:{px(8)};top:{px(HH / 2)};transform:translate(0,-50%);font-size:{px(10.5)};color:{css(st["accent"])};{SHADOW}">[-]</div>')
    # body
    by = HH + 2
    p.append(box(0, by, W, BH, f"background:{css(st['bgMain'])};border:1px solid {css(st['border'])}"))
    for i, h in enumerate((3, 6, 9)):
        x = W - 1 - 2 - (2 - i) * 3 - 2
        p.append(box(x, by + BH - 1 - 2 - h, 2, h, f"background:{css(st['textSub'], .55)}"))

    inner = W - 18
    rows = []
    y = -4  # yOffset inside the scroll child
    for zi, zone in enumerate(t["zones"]):
        a.setdefault("zone%d" % zi, -y)
        rows.append(f'<div class="abs tl" style="left:{px(PAD - 2)};top:{px(-y)};width:{px(inner - 10)};font-size:{px(10.5)};color:{css(st["zone"])}">'
                    f'▾ {esc(zone)}</div>')
        y -= 15 + 2
        for (qz, key, lvl, state, objs, item) in QUESTS:
            if qz != zi:
                continue
            indent = 0
            if item:
                rows.append(box(PAD - 2, -y, 20, 20, f"background:{css(st['border'], .95)};padding:{px(1)}",
                                f'<div style="width:100%;height:100%;overflow:hidden">{ITEM_ICON}</div>'))
                a["item"] = -y + 3
                indent = 23
            a.setdefault("quest_" + key, -y)
            suffix = ""
            if state == 1:
                suffix = f' <span style="color:#40ff59">{esc(L["TRACKER_COMPLETE_TAG"])}</span>'
            elif state == -1:
                suffix = f' <span style="color:#ff5555">{esc(L["TRACKER_FAILED_TAG"])}</span>'
            rows.append(f'<div class="abs tl" style="left:{px(PAD - 2 + indent)};top:{px(-y)};width:{px(inner - 8 - indent)}">'
                        f'<span class="abs" style="left:0;top:{px(-1)};width:{px(14)};height:{px(14)};text-align:center;color:{css(st["textSub"])}">-</span>'
                        f'<div style="margin-left:{px(15)};color:{difficulty(lvl)}">[{lvl}] {esc(t["q"][key])}{suffix}</div></div>')
            y -= 15 + 1
            ow = inner - 26 - indent
            if state == 1 and not objs:
                lines = [(f'• {L["TRACKER_QUEST_COMPLETE"]}', "#40ff59")]
            elif state == -1:
                lines = [(f'• {L["TRACKER_QUEST_FAILED"]}', "#ff5555")]
            else:
                lines = [(f'• {t["q"][ok]}: {have}/{need}', progress(have, need)) for ok, have, need in objs]
            for i, (text, col) in enumerate(lines):
                if key == "wolf" and i == 0:
                    a["obj"] = -y
                rows.append(f'<div class="abs tl" style="left:{px(PAD + 13 + indent)};top:{px(-y)};width:{px(ow)};color:{col}">{esc(text)}</div>')
                y -= 14 + 1
            y -= 3
    p.append(f'<div class="abs" style="left:{px(2)};top:{px(by + 4)};width:{px(inner)};height:{px(BH - 12)};overflow:hidden">{"".join(rows)}</div>')
    for key in list(a):
        a[key] = by + 4 + a[key] + 7
    html_ = f'<div class="abs" style="left:{ox}px;top:{oy}px;width:{px(W)};height:{px(HH + 2 + BH)}">' + "".join(p) + "</div>"
    return html_, a, (W, HH + 2 + BH)


# ---------------------------------------------------------------------------
# Character window (simplified drawing), scale toast and hover tooltip
# ---------------------------------------------------------------------------
CHAR_W, CHAR_H = 300, 380  # page px at 100 %


def slot_column(x, y0, n, size, gap):
    return "".join(f'<div class="abs" style="left:{x}px;top:{y0 + i * (size + gap)}px;width:{size}px;height:{size}px;'
                   f'background:radial-gradient(circle at 35% 30%,#4a4f57,#1c1f24);border:2px solid #6b5a3a;border-radius:3px"></div>'
                   for i in range(n))


def char_window(lang, x0, y0, scale):
    t = T[lang]
    w, h = CHAR_W * scale, CHAR_H * scale
    k = scale
    tb = 28 * k
    p = [f'<div class="abs" style="left:0;top:0;width:{w}px;height:{tb}px;background:linear-gradient(#5a4523,#3a2c15);border-bottom:2px solid #8c7a55"></div>',
         f'<div class="t" style="left:{w / 2}px;top:{tb / 2}px;transform:translate(-50%,-50%);font-size:{15 * k:.1f}px;color:#ffd100;{OUTLINE}">{esc(t["charTitle"])}</div>',
         f'<div class="abs" style="right:{8 * k}px;top:{5 * k}px;width:{18 * k}px;height:{18 * k}px;border-radius:3px;background:#7a1d12;border:1px solid #c9a35a;'
         f'color:#ffd9a0;font-size:{12 * k:.0f}px;display:flex;align-items:center;justify-content:center">×</div>']
    inner_t, inner_b = tb + 10 * k, h - 52 * k
    p.append(f'<div class="abs" style="left:{10 * k}px;top:{inner_t}px;width:{w - 20 * k}px;height:{inner_b - inner_t}px;'
             f'background:radial-gradient(ellipse at 50% 40%,#2c3440,#11151b);border:1px solid #4b3d24"></div>')
    size, gap = 30 * k, 6 * k
    p.append(slot_column(16 * k, inner_t + 8 * k, 7, size, gap))
    p.append(slot_column(w - 16 * k - size, inner_t + 8 * k, 7, size, gap))
    # simple figure silhouette
    cx, cy = w / 2, inner_t + (inner_b - inner_t) * .45
    p.append(f'<svg class="abs" style="left:{cx - 60 * k}px;top:{cy - 95 * k}px" width="{120 * k}" height="{190 * k}" viewBox="0 0 120 190">'
             '<defs><linearGradient id="fig" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6d7f99"/><stop offset="1" stop-color="#2f3a4a"/></linearGradient></defs>'
             '<circle cx="60" cy="32" r="20" fill="url(#fig)"/>'
             '<path d="M22 74 Q60 52 98 74 L92 132 Q60 142 28 132 Z" fill="url(#fig)"/>'
             '<path d="M30 134 L44 188 H56 L60 146 L64 188 H76 L90 134 Q60 144 30 134 Z" fill="url(#fig)" opacity=".85"/>'
             '<path d="M22 76 L8 126 L18 128 L30 92 Z M98 76 L112 126 L102 128 L90 92 Z" fill="url(#fig)" opacity=".9"/></svg>')
    p.append(f'<div class="t" style="left:{w / 2}px;top:{inner_b + 10 * k}px;transform:translate(-50%,0);font-size:{13 * k:.1f}px;color:#f2e6c4;{SHADOW}">{esc(t["charLine"])}</div>')
    tabw = 82 * k
    for i, name in enumerate(t["charTabs"]):
        p.append(f'<div class="abs" style="left:{14 * k + i * (tabw + 4 * k)}px;top:{h - 27 * k}px;width:{tabw}px;height:{20 * k}px;'
                 f'background:{"#6b4e1f" if i == 0 else "#3b2c14"};border:1px solid #c9a35a;color:#ffd100;font-size:{11 * k:.1f}px;'
                 f'display:flex;align-items:center;justify-content:center;white-space:nowrap">{esc(name)}</div>')
    return (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{w}px;height:{h}px;background:#1d1710;border:3px solid #8c7a55;'
            f'border-radius:6px;box-shadow:0 8px 24px rgba(0,0,0,.6);overflow:hidden">' + "".join(p) + "</div>")


def toast(ctx, lang, cx, y):
    """ns:ShowScaleToast: width = text + 36 (min 200), 32 high, accent border and bottom bar."""
    st, L = ctx["ostyle"], ctx["L"][lang]
    text = L["TOAST_SCALE"].replace("%s", "CharacterFrame").replace("%d%%", "110%")
    return (f'<div class="abs" style="left:{cx}px;top:{y}px;transform:translate(-50%,0);min-width:{px(200)};height:{px(32)};padding:0 {px(18)};'
            f'background:{css(st["bgMain"])};border:1px solid {css(st["accent"])};display:flex;align-items:center;justify-content:center">'
            f'<span style="font-size:{px(12)};color:{css(st["text"])};{SHADOW};white-space:nowrap">{esc(text)}</span>'
            f'<div class="abs" style="left:{px(1)};right:{px(1)};bottom:{px(1)};height:{px(2)};background:{css(st["accent"])}"></div></div>')


def hover_tip(ctx, lang, x, y):
    """ns:UpdateHoverTooltip: title (accent) + scale, separator at 26, body lines (textSub, spacing 3)."""
    st, L, d = ctx["ostyle"], ctx["L"][lang], ctx["defaults"]
    lines = []
    if d.get("enableMove") is not False:
        lines.append(L["TT_CTRL_DRAG_MOVE"] if d.get("requireCtrl") is True else L["TT_DRAG_MOVE"])
        lines.append(L["TT_ALT_DETACH"])
    if d.get("enableScale") is not False:
        lines.append(L["TT_WHEEL_SCALE"].replace("%d%%", "110%"))
    if d.get("quickReset") is not False:
        lines += [L["TT_SHIFT_RCLICK"], L["TT_CTRL_RCLICK"], L["TT_FULL_RESET"]]
    body = "<br>".join("• " + esc(s) for s in lines)
    return (f'<div class="abs" style="left:{x}px;top:{y}px;min-width:{px(210)};background:{css(st["bgMain"])};border:1px solid {css(st["border"])};'
            f'padding:{px(9)} {px(10)} {px(10)} {px(10)}">'
            f'<div class="abs" style="left:{px(1)};right:{px(1)};top:{px(1)};height:{px(2)};background:{css(st["accent"])}"></div>'
            f'<div style="display:flex;justify-content:space-between;gap:{px(22)};font-size:{px(10.5)};line-height:{px(12)};{SHADOW}">'
            f'<span style="color:{css(st["accent"])}">{esc(L["ADDON_TITLE"])}</span><span style="color:{css(st["text"])}">110%</span></div>'
            f'<div style="height:1px;margin:{px(5)} -{px(2)} {px(5)};background:{css(st["border"], .8)}"></div>'
            f'<div style="font-size:{px(10)};line-height:{px(14)};color:{css(st["textSub"])};white-space:nowrap;{SHADOW}">{body}</div></div>')


def chat_box(lang, ctx, x, y, w):
    t, L = T[lang], ctx["L"][lang]
    q = t["q"]
    pre = f'[{t["party"]}] [{t["me"]}]: '
    lines = [
        L["QUEST_ANNOUNCE_ACCEPTED"].replace("%s", q["supply"]),
        L["QUEST_ANNOUNCE_PROGRESS"].replace("%s", q["wolf"], 1).replace("%s", f'{q["wolfObj"]}: 5/8', 1),
        L["QUEST_ANNOUNCE_DONE"].replace("%s", q["mine"]),
        L["QUEST_ANNOUNCE_TURNED_IN"].replace("%s", q["letter"]),
    ]
    chat = "<br>".join(f'{esc(pre)}{esc(s)}' for s in lines)
    return (f'<div class="abs" style="left:{x}px;top:{y}px;width:{w}px;background:rgba(0,0,0,.42);border:1px solid #2b3a45;border-radius:6px;'
            f'padding:10px 14px;font-size:15px;line-height:25px;color:#aaaaff;white-space:nowrap;overflow:hidden;text-shadow:1px 1px 1px #000">{chat}</div>')


MOVE_ICON = ('<svg width="34" height="34" viewBox="0 0 34 34"><g fill="#f2f2f2" stroke="#111" stroke-width="1.6" stroke-linejoin="round">'
             '<path d="M17 2 L23 9 H19 V15 H25 V11 L32 17 L25 23 V19 H19 V25 H23 L17 32 L11 25 H15 V19 H9 V23 L2 17 L9 11 V15 H15 V9 H11 Z"/></g></svg>')


def ui_page(lang, ctx):
    global S
    S = 1.6
    t = T[lang]
    parts = []
    top = 170
    # character window: original spot (dashed) and the moved, 110 % window
    gx, gy = 50, top + 40
    parts.append(f'<div class="abs" style="left:{gx}px;top:{gy}px;width:{CHAR_W}px;height:{CHAR_H}px;border:2px dashed #7d8d98;border-radius:6px;'
                 f'background:rgba(125,141,152,.06)"></div>')
    parts.append(f'<div class="t" style="left:{gx + 190}px;top:{gy + 8}px;font-size:14px;color:#9aa7b0">{esc(t["ghost"])}</div>')
    cx0, cy0 = 120, top + 70
    parts.append(char_window(lang, cx0, cy0, 1.1))
    cw, ch = CHAR_W * 1.1, CHAR_H * 1.1
    # drag arrow from the ghost title to the window title
    parts.append(f'<svg class="abs" style="left:0;top:0;overflow:visible" width="10" height="10"><defs><marker id="ah" markerWidth="10" markerHeight="10" refX="6" refY="5" orient="auto">'
                 f'<path d="M0 0 L10 5 L0 10 Z" fill="{CALL}"/></marker></defs>'
                 f'<path d="M{gx + 70} {gy + 14} Q{gx + 90} {gy - 10} {cx0 + 120} {cy0 + 8}" stroke="{CALL}" stroke-width="3" fill="none" stroke-dasharray="7 5" marker-end="url(#ah)"/></svg>')
    parts.append(f'<div class="abs" style="left:{cx0 + 22}px;top:{cy0 + 4}px">{MOVE_ICON}</div>')
    # toast and hover tooltip
    tx = cx0 + cw + 40
    parts.append(toast(ctx, lang, tx + 210, top - 6))
    parts.append(hover_tip(ctx, lang, tx, top + 90))
    # quest tracker
    ox, oy = PAGE_W - 50 - 270 * S, top
    tr_html, ta, (tw, th) = tracker(ctx, lang, ox, oy)
    parts.append(tr_html)
    # party chat
    chat_y = cy0 + ch - 128
    chat_w = ox - 40 - tx
    parts.append(chat_box(lang, ctx, tx, chat_y, chat_w))

    def P(gy_):
        return oy + gy_ * S

    calls = [
        (cx0 - 26, cy0 + 60),                          # 1 drag
        (tx - 6, top + 10),                            # 2 toast
        (tx - 24, top + 110),                          # 3 tooltip
        (ox - 30, P(12)),                              # 4 tracker header
        (ox - 30, P(ta["quest_wolf"])),                # 5 quest line
        (ox - 30, P(ta["item"])),                      # 6 item button
        (ox + tw * S + 20, P(th - 8)),                 # 7 resize
        (tx - 24, chat_y + 20),                        # 8 party messages
    ]
    for i, (x, y) in enumerate(calls, 1):
        parts.append(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>')

    hand_top = oy + th * S + 30
    parts.append(f'<div class="hand" style="left:50px;top:{hand_top:.0f}px;width:1500px">{esc(t["handover"])}</div>')
    notes_top = hand_top + 72
    half = 4
    parts.append(f'<div class="notes" style="left:50px;top:{notes_top:.0f}px;width:720px">{note_html(1, t["notes"][:half])}</div>')
    parts.append(f'<div class="notes" style="left:820px;top:{notes_top:.0f}px;width:730px">{note_html(half + 1, t["notes"][half:])}</div>')
    nh = max(notes_height(t["notes"][:half], 680), notes_height(t["notes"][half:], 690))
    page_h = notes_top + nh + 70
    parts.append(f'<div class="abs foot" style="left:50px;top:{page_h - 58:.0f}px;width:1500px">{esc(t["foot"])}</div>')
    head = f'<div class="page"><h1>EzWoW - Frame Mover</h1><div class="lead">{esc(t["lead"])}</div></div>'
    return head + "".join(parts), page_h


# ---------------------------------------------------------------------------
# Settings window (UI/OptionsWindow.lua)
# ---------------------------------------------------------------------------
SAMPLE_STATUS = (64, 7, 3)


def settings_page(lang, ctx):
    global S
    S = 1.25
    t, L, st, dflt = T[lang], ctx["L"][lang], ctx["ostyle"], ctx["defaults"]
    o = ctx["options"]
    W, H = o["size"]
    ox, oy = 60, 150
    p = []
    accent, text_c, sub = css(st["accent"]), css(st["text"]), css(st["textSub"])

    def btn(x, y, w, h, label, size=10.5):
        return box(x, y, w, h, f"background:{css(st['bgSub'])};border:1px solid {css(st['border'])};display:flex;align-items:center;justify-content:center",
                   f'<span class="fit" data-fit="{(w - 8) * S:.1f}" style="font-size:{px(size)};color:{text_c};white-space:nowrap;{SHADOW}">{esc(label)}</span>')

    # header (56 high, inset 1)
    p.append(box(1, 1, W - 2, 56, f"background:{css(st['bgSub'])};border:1px solid {css(st['border'])}"))
    p.append(box(1, 55, W - 2, 2, f"background:{accent}"))
    p.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{px(15)};top:{px(15)};width:{px(28)};height:{px(28)}">')
    p.append(f'<div class="t" style="left:{px(53)};top:{px(14)};font-size:{px(14.5)};color:{text_c};{SHADOW}">{esc(L["ADDON_TITLE"])}'
             f'<span style="font-size:{px(10)};color:{sub};margin-left:{px(8)}">v{esc(ctx["version"])}</span></div>')
    p.append(f'<div class="t" style="left:{px(53)};top:{px(32.5)};font-size:{px(10)};color:{sub};{SHADOW}">{esc(L["ADDON_SUBTITLE"])}</div>')
    p.append(btn(W - 1 - 12 - 24, 1 + 16, 24, 24, "X", 11))
    # language
    p.append(f'<div class="t" style="left:{px(20)};top:{px(70)};font-size:{px(11)};color:{sub};{SHADOW}">{esc(L["OPT_LANGUAGE"])}</div>')
    lw = 24 if lang == "ko" else 50
    p.append(btn(20 + lw + 12, 70 + 6 - 11, 160, 22, "Auto  ▾"))

    # sections
    sec_title = {"secGeneral": "SECTION_GENERAL", "secTracker": "SECTION_TRACKER", "secQuest": "SECTION_QUEST_AUTO",
                 "secStatus": "SECTION_STATUS", "secControls": "SECTION_CONTROLS"}
    for name, y in o["sections"].items():
        yy = -y
        p.append(box(18, yy + 3, 3, 14, f"background:{accent}"))
        p.append(f'<div class="t" style="left:{px(28)};top:{px(yy + 10)};transform:translate(0,-50%);font-size:{px(12.5)};color:{accent};{SHADOW}">'
                 f'<span id="sec_{name}">{esc(L[sec_title[name]])}</span></div>')
        p.append(f'<div class="abs sline" data-sec="sec_{name}" style="top:{px(yy + 10)};right:{px(18)};height:1px;background:{css(st["border"], .65)}"></div>')

    # check boxes with default states
    for name, c in o["checks"].items():
        val = dflt.get(c["field"])
        on = (val is not False) if c["op"] == "~= false" else (val is True)
        x, y, w = c["x"], -c["y"], c["w"]
        fill = box(3, 3, 10, 10, f"background:{accent}") if on else ""
        p.append(box(x, y + 2, 18, 18, f"background:{css(st['bgSub'])};border:1px solid {accent if on else css(st['border'])}", fill))
        p.append(f'<div class="t" style="left:{px(x + 27)};top:{px(y + 11)};transform:translate(0,-50%);font-size:{px(10.5)};color:{text_c};{SHADOW}">'
                 f'<span class="fit" data-fit="{(w - 27) * S:.1f}" data-min="{10.5 * 0.7 * S:.1f}">{esc(L[c["label"]])}</span></div>')

    # status box
    sx, sy, sh = o["status"]
    status = L["STATUS_FORMAT"].replace("%d", "{}").format(*SAMPLE_STATUS)
    # guide lines that do not fit the box width are cut with "..." (the box is only 74 high)
    guide = "".join(f'<div style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{esc(s)}</div>'
                    for s in L["GUIDE_TEXT"].split("\n"))
    p.append(box(sx, sy, W - 2 * sx, sh, f"background:{css(st['bgSub'])};border:1px solid {css(st['border'])};padding:{px(10)} {px(12)} {px(8)};overflow:hidden",
                 f'<div style="font-size:{px(10.5)};line-height:{px(12)};color:{accent};white-space:nowrap;{SHADOW}">{esc(status)}</div>'
                 f'<div style="margin-top:{px(6)};font-size:{px(9.5)};line-height:{px(12.5)};color:{sub};{SHADOW}">{guide}</div>'))

    # reset buttons
    for name, b in o["buttons"].items():
        if "side" not in b:
            continue
        x = 18 if b["side"] == "TOPLEFT" else W - 18 - b["w"]
        p.append(btn(x, b["y"], b["w"], b["h"], L[b["label"]]))

    # footer (40 high)
    fy = H - 1 - 40
    p.append(box(1, fy, W - 2, 40, f"background:{css(st['bgSub'])};border:1px solid {css(st['border'])}"))
    bd, bn = o["buttons"]["btnDefaults"], o["buttons"]["btnDonate"]
    p.append(btn(1 + 14, fy + 8, bd["w"], bd["h"], L[bd["label"]]))
    p.append(btn(W - 1 - 14 - bn["w"], fy + 8, bn["w"], bn["h"], L[bn["label"]]))
    p.append(f'<div class="t" style="left:{px(W / 2)};top:{px(fy + 20)};transform:translate(-50%,-50%);font-size:{px(10.5)};color:{sub};{SHADOW}">{esc(L["HINT_FOOTER"])}</div>')

    win = (f'<div class="abs" id="win" style="left:{ox}px;top:{oy}px;width:{px(W)};height:{px(H)};background:{css(st["bgMain"])};'
           f'border:1px solid {css(st["border"])}">' + "".join(p) + "</div>")
    secs = o["sections"]
    spans = [(64, 92), (-secs["secGeneral"], -secs["secTracker"]), (-secs["secTracker"], -secs["secQuest"]),
             (-secs["secQuest"], -secs["secStatus"]), (-secs["secStatus"], -secs["secControls"]),
             (-secs["secControls"], H - 41), (H - 41, H)]
    calls = "".join(f'<div class="call" style="left:{ox + W * S + 18:.0f}px;top:{oy + (a + b_) / 2 * S - 15:.0f}px">{i}</div>'
                    for i, (a, b_) in enumerate(spans, 1))
    nx = ox + W * S + 80
    notes = note_html(1, t["sNotes"]) + note_html(0, [t["sHand"]], info=True)
    page_h = oy + H * S + 80
    js = ("<script>document.querySelectorAll('.sline').forEach(function(l){var s=document.getElementById(l.dataset.sec);"
          "var w=document.getElementById('win').getBoundingClientRect();var r=s.getBoundingClientRect();"
          f"l.style.left=(r.right-w.left+{10 * S})+'px';}});</script>")
    body = (f'<div class="page"><h1>EzWoW - Frame Mover <span class="badge">{esc(t["sTitle"])}</span></h1>'
            f'<div class="lead">{esc(t["sLead"])}</div></div>' + win + calls
            + f'<div class="notes" style="left:{nx:.0f}px;top:{oy + 10}px;width:{PAGE_W - nx - 50:.0f}px">{notes}</div>'
            + f'<div class="abs foot" style="left:50px;top:{page_h - 44:.0f}px">{esc(t["sFoot"])}</div>' + js)
    return body, page_h


# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def stop(proc):
    """Ends Chrome and its child processes."""
    if proc.poll() is None:
        if os.name == "nt":
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            proc.kill()
    proc.wait()


def screenshot(cmd, out_png, timeout=180):
    """Runs headless Chrome until the screenshot file is written (Chrome may not exit by itself)."""
    if out_png.exists():
        out_png.unlink()
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        start, last = time.time(), -1
        while time.time() - start < timeout:
            if out_png.exists():
                size = out_png.stat().st_size
                if size > 0 and size == last:
                    return
                last = size
            elif proc.poll() is not None:
                raise RuntimeError(f"Chrome ended without writing {out_png}")
            time.sleep(0.5)
        raise TimeoutError(f"no screenshot after {timeout}s: {out_png}")
    finally:
        stop(proc)


def render(chrome, html_text, out_png, height, tmp):
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(html_text, encoding="utf-8")
    screenshot([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                f"--user-data-dir={Path(tmp) / 'chrome_profile'}", f"--window-size={PAGE_W},{int(height)}",
                "--virtual-time-budget=2000", f"--screenshot={out_png}", page.as_uri()], out_png)


def main(root: Path):
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    tracker_src = read(root, "UI/QuestTracker.lua")
    options_src = read(root, "UI/OptionsWindow.lua")
    locales = read(root, "Core/Locales.lua")
    ctx = {
        "tstyle": parse_style(tracker_src),
        "tconst": parse_consts(tracker_src),
        "ostyle": parse_style(options_src),
        "options": parse_options(options_src),
        "defaults": parse_defaults(read(root, "Modules/MoverEngine.lua")),
        "L": {"ko": parse_locale(locales, "lKokr", "koKR"), "en": parse_locale(locales, "lEnus", "enUS")},
        "version": parse_version(read(root, "EzWoW-FrameMover.toc")),
        "icon": "data:image/png;base64," + base64.b64encode((root / "Media" / "Icon.png").read_bytes()).decode(),
    }
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezfm_readme_")
    try:
        for lang in ("ko", "en"):
            for name, fn in (("ui", ui_page), ("settings", settings_page)):
                body, h = fn(lang, ctx)
                html_text = (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>'
                             f'<body style="height:{int(h)}px">{body}{FIT_JS}</body></html>')
                png = out / f"{name}_{lang}.png"
                render(chrome, html_text, png, h, tmp)
                print("wrote", png, int(h))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
