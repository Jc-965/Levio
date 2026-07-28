#!/usr/bin/env python3
"""Composes App Store marketing images (1320x2868) from the raw simulator
screenshots in marketing/raw/, adding a headline and a device frame.

The raw shots are lossless WebP so the sources stay small; the frames written
to marketing/appstore/ are PNG because App Store Connect only takes PNG/JPEG.

Usage: python3 marketing/generate_frames.py
Requires Google Chrome (used headless to render each frame).
"""

import pathlib
import subprocess
import tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ROOT = pathlib.Path(__file__).resolve().parent
RAW = ROOT / "raw"
OUT = ROOT / "appstore"

SLIDES = [
    {
        "shot": "01-onboarding.webp",
        "out": "01-welcome.png",
        "headline": "Meet ParkiWell",
        "sub": "Your everyday Parkinson’s care companion.",
        "dark": False,
    },
    {
        "shot": "02-home.webp",
        "out": "02-home.png",
        "headline": "Your whole day at a glance",
        "sub": "Symptom trends and medication routines, together.",
        "dark": False,
    },
    {
        "shot": "03-manage.webp",
        "out": "03-manage.png",
        "headline": "Log symptoms in seconds",
        "sub": "Keep every detail in one clear timeline.",
        "dark": False,
    },
    {
        "shot": "04-recovery.webp",
        "out": "04-recovery.png",
        "headline": "Practice with a plan",
        "sub": "Guided speech and movement sessions, at your pace.",
        "dark": False,
    },
    {
        "shot": "06-community.webp",
        "out": "05-community.png",
        "headline": "Guidance you can trust",
        "sub": "Research, videos, specialists, and support in one place.",
        "dark": False,
    },
    {
        "shot": "auth-signin.webp",
        "out": "06-sync.png",
        "headline": "Your care, on every device",
        "sub": "Sign in to sync securely, or keep everything on device.",
        "dark": False,
    },
    {
        "shot": "05-home-dark.webp",
        "out": "07-dark-mode.png",
        "headline": "Gentle by design",
        "sub": "Calm colors, large touch targets, and full dark mode.",
        "dark": True,
    },
    {
        "shot": "07-manage-dark.webp",
        "out": "08-dark-manage.png",
        "headline": "Easy on tired eyes",
        "sub": "The same clear tools, dimmed for evenings and low light.",
        "dark": True,
    },
    {
        "shot": "08-recovery-dark.webp",
        "out": "09-dark-recovery.png",
        "headline": "Practice any time of day",
        "sub": "Wind-down sessions that stay comfortable after dark.",
        "dark": True,
    },
    {
        "shot": "09-community-dark.webp",
        "out": "10-dark-community.png",
        "headline": "Support whenever you need it",
        "sub": "Trusted resources and a 24/7 helpline, day or night.",
        "dark": True,
    },
]

TEMPLATE = """<!doctype html>
<html><head><meta charset="utf-8"><style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  html, body {{ width: 1320px; height: 2868px; overflow: hidden; }}
  body {{
    background: {background};
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display",
                 "Helvetica Neue", sans-serif;
    display: flex; flex-direction: column; align-items: center;
  }}
  h1 {{
    margin-top: 170px; padding: 0 100px;
    font-size: 96px; font-weight: 800; letter-spacing: -3px;
    line-height: 1.08; text-align: center; color: {headline_color};
  }}
  p {{
    margin-top: 34px; padding: 0 150px;
    font-size: 44px; font-weight: 500; line-height: 1.4;
    text-align: center; color: {sub_color};
  }}
  .device {{
    margin-top: 96px; width: 1010px; flex: none;
    background: #0d1117; border-radius: 152px; padding: 20px;
    box-shadow: 0 70px 140px {shadow_color};
  }}
  .device img {{
    display: block; width: 100%; border-radius: 132px;
  }}
</style></head><body>
  <h1>{headline}</h1>
  <p>{sub}</p>
  <div class="device"><img src="{shot}" alt=""></div>
</body></html>
"""


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for slide in SLIDES:
        html = TEMPLATE.format(
            background=(
                "linear-gradient(165deg, #0b1120 0%, #101828 55%, #16213a 100%)"
                if slide["dark"]
                else "linear-gradient(165deg, #dce8fa 0%, #edf3fc 48%, #f8fafd 100%)"
            ),
            headline_color="#f4f7fd" if slide["dark"] else "#0f1c33",
            sub_color="#9fb0c8" if slide["dark"] else "#4a5872",
            shadow_color=(
                "rgba(0, 0, 0, 0.55)" if slide["dark"] else "rgba(23, 43, 77, 0.28)"
            ),
            headline=slide["headline"],
            sub=slide["sub"],
            shot=(RAW / slide["shot"]).as_uri(),
        )
        with tempfile.NamedTemporaryFile(
            "w", suffix=".html", delete=False, dir=ROOT
        ) as handle:
            handle.write(html)
            page = pathlib.Path(handle.name)
        try:
            subprocess.run(
                [
                    CHROME,
                    "--headless=new",
                    "--disable-gpu",
                    "--hide-scrollbars",
                    "--force-device-scale-factor=1",
                    "--window-size=1320,2868",
                    f"--screenshot={OUT / slide['out']}",
                    page.as_uri(),
                ],
                check=True,
                capture_output=True,
            )
        finally:
            page.unlink()
        print(f"wrote {OUT / slide['out']}")


if __name__ == "__main__":
    main()
