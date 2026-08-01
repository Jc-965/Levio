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
    python3 scripts/sync-motion-assets.py [path-to-motion-coach-cv]
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


def _write(path: str, document: object) -> int:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, separators=(",", ":"), sort_keys=True)
    return os.path.getsize(path)


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
        frames = loop["frames"]
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
    engine_repo = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ENGINE_REPO
    if not os.path.isdir(engine_repo):
        print(f"engine repo not found: {engine_repo}", file=sys.stderr)
        return 1
    sync_templates(engine_repo)
    sync_routines(engine_repo)
    sync_demonstrations(engine_repo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
