#!/usr/bin/env python3

import argparse
from collections import deque
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parent.parent
GST_PLUGINS = """
adaptivedemux2 app audioconvert audiomixer audioparsers audioresample autodetect
coreelements d3d11 directsound faad flv gio hls id3demux isomp4 libav matroska
mpegtsdemux openh264 playback soup subparse tcp typefindfunctions videoconvertscale
videoparsersbad volume wasapi wasapi2
""".split()
DLL_IMPORT = re.compile(r"DLL Name: (\S+)")


def windows_path(path):
    if os.name == "nt":
        return str(path)

    return subprocess.check_output(["winepath", "-w", path], text=True).strip()


def copy_runtime_dependencies(runtime, sdk_bin, objdump):
    available = {path.name.lower(): path for path in sdk_bin.glob("*.dll")}
    copied = {path.name.lower() for path in runtime.glob("*.dll")}
    pending = deque(path for path in runtime.rglob("*") if path.suffix.lower() in {".dll", ".exe"})
    while pending:
        binary = pending.popleft()
        imports = subprocess.check_output([objdump, "-p", binary], text=True, encoding="utf-8", errors="replace")
        for name in DLL_IMPORT.findall(imports):
            key = name.lower()
            if key in copied or key not in available:
                continue

            dependency = available[key]
            target = runtime / dependency.name
            shutil.copy2(dependency, target)
            copied.add(key)
            pending.append(target)


def package(executable, sdk, output):
    sdk_bin = sdk / "bin"
    env = os.environ.copy()
    launcher = []
    objdump = sdk_bin / "objdump.exe"

    if os.name != "nt":
        launcher = ["wine"]
        objdump = "objdump"
        env["WINEDEBUG"] = "-all"
        env["WINEPATH"] = windows_path(sdk_bin)

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="anixart-package-", dir=output.parent) as directory:
        runtime = Path(directory) / "Anixart"
        runtime.mkdir()
        app = runtime / "Anixart.exe"
        shutil.copy2(executable, app)
        subprocess.run([
            *launcher, sdk_bin / "windeployqt.exe", "--release", "--no-compiler-runtime",
            "--force-openssl", "--include-plugins", "qwebp",
            "--no-translations", "--qmldir", windows_path(PROJECT / "src/qml"), windows_path(app),
        ], env=env, check=True)
        (runtime / "qt.conf").write_text("[Paths]\nPrefix=.\nPlugins=.\nQmlImports=qml\n", encoding="utf-8")
        for library in (*sdk_bin.glob("libssl-*-x64.dll"), *sdk_bin.glob("libcrypto-*-x64.dll")):
            shutil.copy2(library, runtime)

        plugins_dir = runtime / "gstreamer-1.0"
        plugins_dir.mkdir()
        for name in GST_PLUGINS:
            plugin = sdk / "lib/gstreamer-1.0" / f"libgst{name}.dll"
            shutil.copy2(plugin, plugins_dir)

        gio_dir = runtime / "gio"
        gio_dir.mkdir()
        shutil.copy2(sdk / "lib/gio/modules/libgiognutls.dll", gio_dir)
        shutil.copy2(sdk / "etc/ssl/certs/ca-bundle.crt", runtime)
        shutil.copytree(sdk / "share/licenses", runtime / "licenses")
        copy_runtime_dependencies(runtime, sdk_bin, objdump)

        archive = shutil.make_archive(str(Path(directory) / "portable"), "zip", directory, runtime.name)
        Path(archive).replace(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Package a Windows Anixart build using an MSYS2 UCRT64 SDK.")
    parser.add_argument("executable", type=Path)
    parser.add_argument("sdk", type=Path, help="Path to the ucrt64 directory")
    parser.add_argument("output", type=Path, help="Output ZIP archive")
    args = parser.parse_args()
    package(args.executable.resolve(), args.sdk.resolve(), args.output.resolve())
