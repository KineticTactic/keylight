#!/usr/bin/env python3
"""Build the Fabric 26.3 companion against a locally installed copy of the game."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--minecraft-dir", type=Path,
                    default=Path.home() / "Library/Application Support/minecraft")
parser.add_argument("--game-jar", type=Path, help="Override the Minecraft 26.3 client JAR")
parser.add_argument("--profile", type=Path, help="Override the Fabric 26.3 launcher version JSON")
args = parser.parse_args()
versions = args.minecraft_dir / "versions"
candidates = [versions / name / f"{name}.jar" for name in ("26.3", "Fabric 26.3")]
game = args.game_jar or next((path for path in candidates if path.is_file()), None)
if not game or not game.is_file():
    parser.error("Install Minecraft 26.3 or supply its client JAR with --game-jar.")
profiles = sorted(versions.glob("*26.3/*.json"))
profile = args.profile or next((p for p in profiles if "fabric" in p.stem.lower()), None)
if not profile:
    parser.error("Supply the installed Fabric 26.3 version JSON with --profile.")
deps = [game]
while profile:
    metadata = json.loads(profile.read_text())
    for library in metadata["libraries"]:
        group, name, version, *classifier = library["name"].split(":")
        filename = "-".join([name, version, *classifier]) + ".jar"
        path = args.minecraft_dir / "libraries" / group.replace(".", "/") / name / version / filename
        if path.is_file():
            deps.append(path)
    parent = metadata.get("inheritsFrom")
    profile = versions / parent / f"{parent}.json" if parent else None

source = root / "companions/minecraft"
out = root / "dist/keylight-damage-26.3.jar"
out.parent.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as classes:
    subprocess.run(["javac", "--release", "25", "-proc:none", "-cp", os.pathsep.join(map(str, deps)),
                    "-d", classes, *sorted((source / "src").rglob("*.java"))], check=True)
    subprocess.run(["jar", "--create", "--file", out, "-C", classes, ".",
                    "-C", source / "resources", "."], check=True)
print(out)
