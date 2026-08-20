#!/usr/bin/env python3
"""Sync motion-coach reference assets from the motion-coach-cv engine repo.

The Dart engine is data-driven: `RoutineSession` needs the same
`exercise-template.v1` documents the Python reference engine uses, and the
guided routine UI draws its demonstration avatar from the committed
`pose-stream.v1` reference loops. Both are generated artifacts of the engine
repo, so they are copied rather than hand-maintained here.

Templates are copied verbatim (minified). Reference loops are reduced to a
front-view 2D demonstration loop: the app only ever draws a stick figure, so
depth, visibility, and every second frame are dropped and coordinates are
quantised to 1 mm. Nothing about the analysis path reads these loops.

Usage:
    python3 scripts/sync-motion-assets.py [path-to-motion-coach-cv] [--check]

--check compares what would be written against the committed assets and
fails on drift, so a stale vendored asset cannot ship silently.
"""

from __future__ import annotations

import glob
import json
import os
import sys

DEFAULT_ENGINE_REPO = os.path.expanduser(
    "~/Downloads/Coding/motion-coach-cv"
)
APP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_FPS = 12.0
COORDINATE_DECIMALS = 3


_OUTPUTS: dict[str, str] = {}


def _write(path: str, document: object) -> int:
    rendered = json.dumps(document, separators=(",", ":"), sort_keys=True)
    _OUTPUTS[path] = rendered
    return len(rendered.encode("utf-8"))


def sync_templates(engine_repo: str) -> None:
    source = os.path.join(engine_repo, "fixtures", "references")
    for path in sorted(glob.glob(f"{source}/*.template.v1.json")):
        size = _write(
            os.path.join(
                APP_ROOT, "assets", "motion", "templates", os.path.basename(path)
            ),
            json.load(open(path, encoding="utf-8")),
        )
        print(f"template  {os.path.basename(path):<52} {size:>7} B")


def sync_routines(engine_repo: str) -> None:
    source = os.path.join(engine_repo, "specs", "routines")
    for path in sorted(glob.glob(f"{source}/*.json")):
        size = _write(
            os.path.join(
                APP_ROOT, "assets", "motion", "routines", os.path.basename(path)
            ),
            json.load(open(path, encoding="utf-8")),
        )
        print(f"routine   {os.path.basename(path):<52} {size:>7} B")


def sync_demonstrations(engine_repo: str) -> None:
    source = os.path.join(engine_repo, "fixtures", "references")
    for path in sorted(glob.glob(f"{source}/*.reference-loop.v1.json")):
        exercise_id = os.path.basename(path).split(".")[0]
        loop = json.load(open(path, encoding="utf-8"))
        # Measured loops may contain the odd untracked frame; the stick
        # figure has nothing to draw for those, so they are dropped before
        # the stride is chosen.
        frames = [
            frame for frame in loop["frames"] if frame["landmarks"] is not None
        ]
        if len(frames) < 2:
            raise SystemExit(f"{exercise_id}: reference loop is too short")

        span_ms = frames[-1]["timestamp_ms"] - frames[0]["timestamp_ms"]
        source_fps = (len(frames) - 1) / (span_ms / 1000)
        stride = max(1, round(source_fps / TARGET_FPS))

        kept = frames[::stride]
        points: list[float] = []
        for frame in kept:
            for landmark in frame["landmarks"]:
                points.append(round(landmark["x"], COORDINATE_DECIMALS))
                points.append(round(landmark["y"], COORDINATE_DECIMALS))

        document = {
            "schema_version": "demonstration-loop.v1",
            "exercise_id": exercise_id,
            "source_schema_version": loop["schema_version"],
            "source_engine_version": loop["engine_version"],
            "frame_count": len(kept),
            "landmark_count": 33,
            "frame_interval_ms": round(span_ms / (len(frames) - 1) * stride),
            # Flat [x0, y0, x1, y1, ...] in metres, frame-major.
            "points_xy": points,
        }
        size = _write(
            os.path.join(
                APP_ROOT,
                "assets",
                "motion",
                "demonstrations",
                f"{exercise_id}.demonstration-loop.v1.json",
            ),
            document,
        )
        print(
            f"demo      {exercise_id:<52} {size:>7} B "
            f"({len(kept)} frames @ {1000 / document['frame_interval_ms']:.0f} fps)"
        )


def main() -> int:
    arguments = [argument for argument in sys.argv[1:] if argument != "--check"]
    check = "--check" in sys.argv[1:]
    engine_repo = arguments[0] if arguments else DEFAULT_ENGINE_REPO
    if not os.path.isdir(engine_repo):
        print(f"engine repo not found: {engine_repo}", file=sys.stderr)
        return 1
    sync_templates(engine_repo)
    sync_routines(engine_repo)
    sync_demonstrations(engine_repo)

    if check:
        stale = []
        for path, rendered in _OUTPUTS.items():
            try:
                with open(path, encoding="utf-8") as handle:
                    current = handle.read()
            except FileNotFoundError:
                current = None
            if current != rendered:
                stale.append(os.path.relpath(path, APP_ROOT))
        if stale:
            print("stale motion assets:", ", ".join(sorted(stale)), file=sys.stderr)
            return 1
        print(f"{len(_OUTPUTS)} motion assets are current")
        return 0

    for path, rendered in _OUTPUTS.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
