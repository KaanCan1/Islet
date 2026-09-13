"""Writes compositions/frames/*.html from STORYBOARD.md's geometry.

The eight frames share one skeleton and differ in a handful of numbers, so they
are generated rather than hand-copied: it is the only way the tour's promise —
that frames 3 to 7 are the same layout with one measurement moved — is actually
true rather than nearly true.

The palette is read out of frame.md's frontmatter, which the design spec calls
the normative layer. Nothing here restates a colour.

    python3 tools/build-frames.py     # from the project root

Then re-assemble: the approved footage element is hoisted into index.html by
assemble-index, which removes it from the frame file, so assembly has to be the
last step before check.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "compositions" / "frames"
OUT.mkdir(parents=True, exist_ok=True)

FONTS = """    @font-face{font-family:"EB Garamond";src:url("assets/fonts/EBGaramond-400.woff2") format("woff2");font-weight:400;font-style:normal;font-display:block}
    @font-face{font-family:"Inter";src:url("assets/fonts/Inter-400.woff2") format("woff2");font-weight:400;font-style:normal;font-display:block}
    @font-face{font-family:"JetBrains Mono";src:url("assets/fonts/JetBrainsMono-400.woff2") format("woff2");font-weight:400;font-style:normal;font-display:block}
    @font-face{font-family:"JetBrains Mono";src:url("assets/fonts/JetBrainsMono-700.woff2") format("woff2");font-weight:700;font-style:normal;font-display:block}"""

# frame.md's frontmatter is the normative layer of the design system, so the
# frames read their palette out of it rather than carrying a second copy that
# can drift from it.
import re as _re

_FRAME = (ROOT / "frame.md").read_text()
def _token(name):
    m = _re.search(rf'^  {name}: "(#[0-9A-Fa-f]{{6}})"', _FRAME, _re.M)
    if not m:
        raise SystemExit(f"frame.md has no colour token {name!r}")
    return m.group(1)

CREAM = _token("cream")
INK = _token("ink")
CORAL = _token("coral")
# Fills take `coral`; glyphs and words take `coral-ink` — see frame.md.
CORAL_INK = _token("coral-ink")


def shell(frame_id, pfx, duration, extra_css, body, script_body):
    # The per-frame extras are plain strings so they can carry braces; the one
    # token they need is spliced in here.
    extra_css = extra_css.replace("CORALINKTOKEN", CORAL_INK).replace("CORALTOKEN", CORAL)
    body = body.replace("CORALINKTOKEN", CORAL_INK).replace("CORALTOKEN", CORAL)
    return f"""<template>
  <style>
{FONTS}

    /* The frame ground is a clip layer, never the root: at assembly the root is
       gated to this frame's window, so a background painted on it is not a
       dependable full-frame ground. */
    #root{{position:absolute;inset:0;overflow:hidden;container-type:size}}

    .{pfx}-ground{{position:absolute;inset:0;background:{CREAM}}}
    .{pfx}-stage{{position:absolute;inset:0}}

    .{pfx}-kicker{{
      position:absolute;font-family:"JetBrains Mono","Courier New",monospace;font-weight:500;
      font-size:28px;letter-spacing:.16em;text-transform:uppercase;color:rgba(20,20,19,.55);
      white-space:nowrap;
    }}
    .{pfx}-kicker .{pfx}-spike{{color:{CORAL_INK};margin-right:.62em}}

    .{pfx}-display{{
      position:absolute;font-family:"EB Garamond","Times New Roman",serif;font-weight:400;
      color:{INK};
    }}
{extra_css}
  </style>

  <div id="root" data-composition-id="{frame_id}" data-width="1920" data-height="1080">
    <div id="{pfx}-ground" class="clip {pfx}-ground" data-start="0" data-duration="{duration}" data-track-index="0"></div>
    <div id="{pfx}-stage" class="clip {pfx}-stage" data-start="0" data-duration="{duration}" data-track-index="1">
{body}
    </div>
  </div>

  <script>
    window.__timelines = window.__timelines || {{}};
    (function () {{
      var tl = gsap.timeline({{ paused: true }});
{script_body}
      window.__timelines["{frame_id}"] = tl;
    }})();
  </script>
</template>
"""


# ---------------------------------------------------------------- frame 1
f1_css = """
    .f01-line{left:120px;width:1680px;font-size:96px;line-height:1.04;letter-spacing:-.018em}
    #f01-line1{top:160px}
    #f01-line2{top:262px}
    #f01-kicker{left:120px;top:100px}"""

f1_body = """      <div class="f01-kicker f01-kicker-x" id="f01-kicker" style="display:none"></div>
      <div class="f01-kicker" id="f01-kicker" hidden></div>"""

# built explicitly below instead
f1_body = """      <div class="f01-kicker f01-chrome" id="f01-kicker" data-layout-allow-overlap><span class="f01-spike" data-layout-allow-overlap>&#10033;</span>macOS &middot; the camera notch</div>
      <div class="f01-display f01-line" id="f01-line1" data-layout-allow-overlap>Hover the notch.</div>
      <div class="f01-display f01-line" id="f01-line2" data-layout-allow-overlap>It becomes a panel.</div>
      <video
        class="clip"
        id="f01-plate"
        src="assets/demo.mp4"
        data-media-start="0"
        data-frame-video="approved"
        data-frame-video-x="0"
        data-frame-video-y="400"
        data-frame-video-width="1920"
        data-frame-video-height="680"
        data-frame-video-fit="cover"
        data-start="0"
        data-duration="4"
        data-track-index="2"
        muted
        playsinline
      ></video>"""

f1_script = """      tl.fromTo("#f01-kicker", { opacity: 0, y: 16 },
        { opacity: 1, y: 0, duration: 0.60, ease: "power2.out" }, 0.15);
      tl.fromTo("#f01-line1", { opacity: 0, y: 22 },
        { opacity: 1, y: 0, duration: 0.80, ease: "power3.out" }, 1.35);
      tl.fromTo("#f01-line2", { opacity: 0, y: 22 },
        { opacity: 1, y: 0, duration: 0.80, ease: "power3.out" }, 2.05);
      tl.to({}, { duration: 4 }, 0);"""

(OUT / "01-hover.html").write_text(
    shell("01-hover", "f01", "4", f1_css.replace(".f01-kicker", ".f01-kicker").replace("#f01-kicker{left:120px;top:100px}", "#f01-kicker{left:120px;top:100px}"), f1_body, f1_script)
)


# ---------------------------------------------------------------- frame 2
f2_css = """
    #f02-word{left:120px;top:286px;font-size:200px;line-height:1;letter-spacing:-.028em}
    #f02-rule{position:absolute;left:120px;top:540px;width:960px;height:1px;background:rgba(20,20,19,.12);transform-origin:0 50%}
    #f02-lead{position:absolute;left:120px;top:596px;width:1240px;font-family:"Inter",system-ui,sans-serif;font-weight:400;font-size:42px;line-height:1.5;color:rgba(20,20,19,.76)}
    #f02-index{position:absolute;left:120px;top:846px;font-family:"JetBrains Mono","Courier New",monospace;font-weight:500;font-size:26px;letter-spacing:.16em;text-transform:uppercase;color:rgba(20,20,19,.5);display:flex;gap:22px;align-items:baseline}
    #f02-index .f02-dot{color:CORALINKTOKEN}"""

f2_body = """      <div class="f02-display" id="f02-word" data-layout-allow-overlap>Islet</div>
      <div id="f02-rule"></div>
      <div id="f02-lead">A panel that lives in your MacBook&rsquo;s camera notch, and nowhere else.</div>
      <div id="f02-index">
        <span class="f02-item">MIT</span><span class="f02-dot f02-item">&middot;</span><span class="f02-item">macOS 14+</span><span class="f02-dot f02-item">&middot;</span><span class="f02-item">one author</span>
      </div>"""

f2_script = """      tl.fromTo("#f02-word", { opacity: 0, y: 26 },
        { opacity: 1, y: 0, duration: 0.80, ease: "power3.out" }, 0);
      tl.fromTo("#f02-rule", { opacity: 1, scaleX: 0 },
        { scaleX: 1, duration: 0.70, ease: "power2.inOut" }, 0.45);
      tl.fromTo("#f02-lead", { opacity: 0, y: 14 },
        { opacity: 1, y: 0, duration: 0.75, ease: "power3.out" }, 0.85);
      tl.fromTo("#f02-index .f02-item", { opacity: 0 },
        { opacity: 1, duration: 0.55, ease: "power2.out", stagger: 0.10 }, 1.55);
      tl.to({}, { duration: 3.6 }, 0);"""

(OUT / "02-islet.html").write_text(shell("02-islet", "f02", "3.6", f2_css, f2_body, f2_script))


# ------------------------------------------------------- frames 3-7 shared
def panel_frame(frame_id, pfx, duration, kicker, headline, asset, panel_top,
                panel_h, sub=None, extra_css="", extra_body="", extra_script=""):
    css = f"""
    #{pfx}-kicker{{left:120px;top:152px}}
    #{pfx}-headline{{left:120px;top:208px;width:1680px;font-size:88px;line-height:1.06;letter-spacing:-.018em}}
    #{pfx}-panel{{position:absolute;left:360px;top:{panel_top}px;width:1200px;height:{panel_h}px;display:block}}
    #{pfx}-sub{{position:absolute;left:360px;top:830px;width:1200px;font-family:"Inter",system-ui,sans-serif;font-weight:400;font-size:34px;line-height:1.45;color:rgba(20,20,19,.68)}}{extra_css}"""

    sub_html = f'\n      <div id="{pfx}-sub">{sub}</div>' if sub else ""
    body = f"""      <div class="{pfx}-kicker" id="{pfx}-kicker" data-layout-allow-overlap><span class="{pfx}-spike" data-layout-allow-overlap>&#10033;</span>{kicker}</div>
      <div class="{pfx}-display" id="{pfx}-headline" data-layout-allow-overlap>{headline}</div>
      <img id="{pfx}-panel" src="assets/{asset}" alt="">{sub_html}{extra_body}"""

    script = f"""      tl.fromTo("#{pfx}-kicker", {{ opacity: 0, y: 14 }},
        {{ opacity: 1, y: 0, duration: 0.60, ease: "power2.out" }}, 0);
      tl.fromTo("#{pfx}-headline", {{ opacity: 0, y: 22 }},
        {{ opacity: 1, y: 0, duration: 0.82, ease: "power3.out" }}, 0.10);
      tl.fromTo("#{pfx}-panel", {{ opacity: 0, y: 30 }},
        {{ opacity: 1, y: 0, duration: 0.87, ease: "power3.out" }}, 0.25);"""
    if sub:
        script += f"""
      tl.fromTo("#{pfx}-sub", {{ opacity: 0, y: 12 }},
        {{ opacity: 1, y: 0, duration: 0.70, ease: "power3.out" }}, 1.25);"""
    script += extra_script
    script += f"""
      tl.to({{}}, {{ duration: {duration} }}, 0);"""
    return shell(frame_id, pfx, duration, css, body, script)


(OUT / "03-music.html").write_text(panel_frame(
    "03-music", "f03", "4", "Music", "Now playing, without a window.",
    "music.png", 367, 415,
    sub="Spotify or Apple Music. Click the artwork to jump to the app it is playing in."))

shelf_extra_css = """
    #f04-ring{position:absolute;left:851px;top:486px;width:217px;height:134px;border:3px solid CORALTOKEN;border-radius:10px;box-sizing:border-box}"""
shelf_extra_body = """
      <div id="f04-ring"></div>"""
shelf_extra_script = """
      tl.fromTo("#f04-ring", { opacity: 0, scale: 1.06 },
        { opacity: 1, scale: 1, duration: 0.75, ease: "power2.out" }, 1.55);"""

(OUT / "04-shelf.html").write_text(panel_frame(
    "04-shelf", "f04", "4.2", "Shelf", "Every screenshot lands here.",
    "shelf.png", 348, 434,
    sub="Click one to open it. Drag it straight into Finder, a chat, a mail draft.",
    extra_css=shelf_extra_css, extra_body=shelf_extra_body, extra_script=shelf_extra_script))

(OUT / "05-timer.html").write_text(panel_frame(
    "05-timer", "f05", "3.6", "Timer", "A pomodoro that never takes a window.",
    "timer.png", 347, 435,
    sub="Focus and Break, battery alerts, and it can stay up on the lock screen."))

(OUT / "06-posture.html").write_text(panel_frame(
    "06-posture", "f06", "4.4", "Posture", "Your AirPods know your head is dropping.",
    "posture.png", 357, 425,
    sub="Measured against the upright you set. If it stays down, the notch says so once &mdash; and then leaves you alone."))

claude_extra_css = """
    #f07-note{position:absolute;left:1000px;top:152px;width:800px;text-align:right;font-family:"JetBrains Mono","Courier New",monospace;font-weight:500;font-size:24px;letter-spacing:.14em;text-transform:uppercase;color:rgba(20,20,19,.55)}"""
claude_extra_body = """
      <div id="f07-note">tab disappears if you don&rsquo;t use it</div>"""
claude_extra_script = """
      tl.fromTo("#f07-note", { opacity: 0 },
        { opacity: 1, duration: 0.55, ease: "power2.out" }, 0.15);"""

(OUT / "07-claude.html").write_text(panel_frame(
    "07-claude", "f07", "4", "Claude Code", "How much of the five-hour block is gone.",
    "claude.png", 370, 523,
    extra_css=claude_extra_css, extra_body=claude_extra_body, extra_script=claude_extra_script))


# ---------------------------------------------------------------- frame 8
f8_css = """
    #f08-kicker{left:120px;top:100px}
    #f08-line{left:120px;top:160px;width:1680px;font-size:128px;line-height:1.02;letter-spacing:-.022em}
    #f08-url{position:absolute;left:120px;top:296px;font-family:"JetBrains Mono","Courier New",monospace;font-weight:500;font-size:38px;letter-spacing:.01em;color:rgba(0,0,0,.78)}
    #f08-urlrule{position:absolute;left:120px;top:354px;width:680px;height:2px;background:CORALTOKEN;transform-origin:0 50%}"""

f8_body = """      <div class="f08-kicker" id="f08-kicker" data-layout-allow-overlap><span class="f08-spike" data-layout-allow-overlap>&#10033;</span>move away</div>
      <div class="f08-display" id="f08-line" data-layout-allow-overlap>And it&rsquo;s gone.</div>
      <div id="f08-url">github.com/KaanCan1/Islet</div>
      <div id="f08-urlrule"></div>
      <video
        class="clip"
        id="f08-plate"
        src="assets/demo.mp4"
        data-media-start="17.4"
        data-frame-video="approved"
        data-frame-video-x="0"
        data-frame-video-y="400"
        data-frame-video-width="1920"
        data-frame-video-height="680"
        data-frame-video-fit="cover"
        data-start="0"
        data-duration="4.1"
        data-track-index="2"
        muted
        playsinline
      ></video>"""

f8_script = """      tl.fromTo("#f08-kicker", { opacity: 0, y: 16 },
        { opacity: 1, y: 0, duration: 0.70, ease: "power2.out" }, 0.30);
      tl.fromTo("#f08-line", { opacity: 0, y: 22 },
        { opacity: 1, y: 0, duration: 0.80, ease: "power3.out" }, 2.20);
      tl.fromTo("#f08-url", { opacity: 0, y: 12 },
        { opacity: 1, y: 0, duration: 0.65, ease: "power3.out" }, 3.60);
      tl.fromTo("#f08-urlrule", { opacity: 1, scaleX: 0 },
        { scaleX: 1, duration: 0.55, ease: "power2.inOut" }, 3.70);
      tl.to({}, { duration: 5.6 }, 0);"""

(OUT / "08-gone.html").write_text(shell("08-gone", "f08", "5.6", f8_css, f8_body, f8_script))

print("wrote", sorted(p.name for p in OUT.glob("*.html")))
