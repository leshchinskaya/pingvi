"""Build full-bleed iOS icons without changing the roomier macOS artwork."""

from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Mobile/iOS/Assets.xcassets"
OUTPUT_SIZE = 1024
PREVIEW_SIZE = 256
# The source artwork includes breathing room suited to the macOS Dock. Cropping
# its 1254 px canvas to 1120 px makes the iOS rendition about 12% larger before
# iOS applies its own rounded-square mask.
IOS_CROP_SIZE = 1120

ICONS = {
    "Ice": (
        ROOT / "Assets/Ice.png",
        CATALOG / "AppIcon.appiconset/AppIcon.png",
        CATALOG / "IconIce.imageset/IconIce.png",
    ),
    "Night": (
        ROOT / "Assets/Night.png",
        CATALOG / "Night.appiconset/Night.png",
        CATALOG / "IconNight.imageset/IconNight.png",
    ),
    "Aurora": (
        ROOT / "Assets/Aurora.png",
        CATALOG / "Aurora.appiconset/Aurora.png",
        CATALOG / "IconAurora.imageset/IconAurora.png",
    ),
    "Orbit": (
        ROOT / "Assets/Orbit.png",
        CATALOG / "Orbit.appiconset/Orbit.png",
        CATALOG / "IconOrbit.imageset/IconOrbit.png",
    ),
    "Classic": (
        ROOT / "Assets/Pingvi.png",
        CATALOG / "Classic.appiconset/Classic.png",
        CATALOG / "IconClassic.imageset/IconClassic.png",
    ),
}


def render(source: Path, app_icon: Path, preview_icon: Path, temporary: Path) -> None:
    cropped = temporary / f"{source.stem}-cropped.png"
    rendered = temporary / f"{source.stem}-ios.png"
    preview = temporary / f"{source.stem}-preview.png"
    subprocess.run(
        ["sips", "--cropToHeightWidth", str(IOS_CROP_SIZE), str(IOS_CROP_SIZE), str(source), "--out", str(cropped)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run(
        ["sips", "--resampleHeightWidth", str(OUTPUT_SIZE), str(OUTPUT_SIZE), str(cropped), "--out", str(rendered)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run(
        ["sips", "--resampleHeightWidth", str(PREVIEW_SIZE), str(PREVIEW_SIZE), str(rendered), "--out", str(preview)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    app_icon.parent.mkdir(parents=True, exist_ok=True)
    preview_icon.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(rendered, app_icon)
    shutil.copyfile(preview, preview_icon)


with tempfile.TemporaryDirectory(prefix="pingvi-ios-icons-") as directory:
    temporary = Path(directory)
    for source, app_icon, preview_icon in ICONS.values():
        render(source, app_icon, preview_icon, temporary)
