#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WRhythm.xcodeproj"
IOS_BUNDLE_ID = "com.restivollc.wrhythm"


class HarnessError(RuntimeError):
    pass


def run(args, *, env=None, check=True, timeout=120):
    try:
        completed = subprocess.run(
            args,
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        raise HarnessError(f"{' '.join(args)} timed out after {timeout}s") from error
    if check and completed.returncode != 0:
        raise HarnessError(f"{' '.join(args)} failed with {completed.returncode}\n{(completed.stdout or '')[-4000:]}")
    return completed.stdout or ""


def simctl(*args, **kwargs):
    return run(["xcrun", "simctl", *args], **kwargs)


def run_bounded(args, *, env=None, timeout=90):
    process = subprocess.Popen(
        args,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
        if process.returncode != 0:
            raise HarnessError(f"{' '.join(args)} failed with {process.returncode}\n{(output or '')[-4000:]}")
        return output or ""
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        return ""


def wait_for(callback, description, *, timeout=60, interval=0.25):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            result = callback()
            if result:
                return result
        except Exception as error:
            last_error = error
        time.sleep(interval)
    if last_error:
        raise HarnessError(f"Timed out waiting for {description}: {last_error}") from last_error
    raise HarnessError(f"Timed out waiting for {description}")


def latest_runtime(platform):
    data = json.loads(simctl("list", "-j", "runtimes"))
    candidates = [
        runtime for runtime in data["runtimes"]
        if runtime.get("isAvailable")
        and runtime.get("platform") == platform
        and runtime.get("identifier")
    ]
    if not candidates:
        raise HarnessError(f"No available {platform} runtime")

    def version_tuple(runtime):
        return tuple(int(piece) for piece in re.findall(r"\d+", runtime.get("version", "0")))

    return max(candidates, key=version_tuple)["identifier"]


def choose_ipad_type():
    preferred_names = ["iPad (A16)", "iPad Pro 13-inch (M5)", "iPad Air 11-inch (M4)"]
    data = json.loads(simctl("list", "-j", "devicetypes"))
    devices = [
        device for device in data["devicetypes"]
        if device.get("productFamily") == "iPad" and device.get("identifier")
    ]
    if not devices:
        raise HarnessError("No iPad simulator device types available")
    for preferred_name in preferred_names:
        for device in devices:
            if device.get("name") == preferred_name:
                return device["identifier"]
    return devices[-1]["identifier"]


def build_ios_app(derived_data):
    print("Building iPad-capable iOS app...")
    run([
        "xcodebuild", "build",
        "-project", str(PROJECT),
        "-scheme", "WRhythm iPhone",
        "-configuration", "Debug",
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(derived_data),
    ], timeout=1200)
    app = derived_data / "Build" / "Products" / "Debug-iphonesimulator" / "WRhythm.app"
    if not app.exists():
        raise HarnessError(f"Expected app missing: {app}")
    return app


def create_and_boot_ipad(name):
    device_id = simctl("create", name, choose_ipad_type(), latest_runtime("iOS")).strip()
    simctl("boot", device_id, timeout=120)
    simctl("bootstatus", device_id, "-b", timeout=600)
    return device_id


def launch_harness_app(device_id):
    env = os.environ.copy()
    env.update({
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS": "1",
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DEVICE_ID": "harness-ipad",
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DEVICE_NAME": "Harness iPad",
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DISABLE_REAL_TRANSPORTS": "1",
    })
    run_bounded(
        [
            "xcrun", "simctl",
            "launch",
            "--terminate-running-process",
            "--stdout=/dev/null",
            "--stderr=/dev/null",
            device_id,
            IOS_BUNDLE_ID,
        ],
        env=env,
        timeout=90,
    )
    time.sleep(2)


def app_container(device_id):
    def read_container():
        return simctl("get_app_container", device_id, IOS_BUNDLE_ID, "data", timeout=90).strip()

    return Path(wait_for(read_container, "iPad app data container", timeout=90, interval=2))


class HarnessDevice:
    def __init__(self, container):
        harness_dir = container / "Library" / "Application Support" / "WRhythm" / "SyncHarness"
        self.state_path = harness_dir / "state.json"
        self.command_path = harness_dir / "command.json"
        self.command_counter = 0

    def status(self):
        with self.state_path.open() as handle:
            return json.load(handle)

    def wait_for_status(self):
        return wait_for(lambda: self.status() if self.state_path.exists() else None, "harness status")

    def open(self, command, **params):
        self.command_counter += 1
        command_id = f"ipad-{self.command_counter}"
        self.command_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"id": command_id, "command": command, "parameters": {k: str(v) for k, v in params.items()}}
        self.command_path.write_text(json.dumps(payload), encoding="utf-8")

        def processed():
            status = self.status()
            if status.get("lastProcessedCommandID") == command_id:
                if status.get("lastProcessedCommand") != command:
                    raise HarnessError(
                        f"Processed {status.get('lastProcessedCommand')} for {command_id}, expected {command}"
                    )
                return status
            return None

        return wait_for(processed, f"command {command_id}:{command}", timeout=20, interval=0.1)


def background_with_system_app(device_id):
    for bundle_id in ["com.apple.Preferences", "com.apple.mobilesafari"]:
        try:
            simctl("launch", device_id, bundle_id, timeout=60)
            return bundle_id
        except HarnessError:
            continue
    raise HarnessError("Could not launch a system app to background WRhythm")


def require_playing(status, label):
    player = status.get("player", {})
    if not player.get("isPlaying"):
        raise HarnessError(f"{label}: player is not playing: {player}")
    if player.get("lastPauseReason"):
        raise HarnessError(f"{label}: WRhythm called pause: {player.get('lastPauseReason')}")
    return float(player.get("currentTime") or 0)


def run_background_audio_check(device_id, device):
    print("Starting real local audio fixture...")
    device.open("playLocalFixture", duration=90)

    foreground_status = wait_for(
        lambda: (
            status if (status := device.status()).get("player", {}).get("isPlaying")
            and float(status.get("player", {}).get("currentTime") or 0) > 0.5
            else None
        ),
        "foreground fixture playback to progress",
        timeout=30,
    )
    foreground_time = require_playing(foreground_status, "foreground")
    print(f"  foreground playback reached {foreground_time:.2f}s")

    background_app = background_with_system_app(device_id)
    print(f"Backgrounded WRhythm by launching {background_app}.")
    time.sleep(8)

    background_status = device.status()
    background_time = require_playing(background_status, "background")
    if background_time < foreground_time + 3:
        raise HarnessError(
            "background playback did not keep progressing "
            f"(foreground={foreground_time:.2f}s, background={background_time:.2f}s)"
        )

    print(f"  background playback reached {background_time:.2f}s")
    print("iPad background audio lifecycle test passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test that iPad local audio keeps playing while WRhythm is backgrounded.")
    parser.add_argument("--keep-simulator", action="store_true", help="Leave the temporary iPad simulator around for debugging.")
    args = parser.parse_args()

    temp_dir = Path(tempfile.mkdtemp(prefix="wrhythm-ipad-background-audio."))
    device_id = None
    try:
        app = build_ios_app(temp_dir / "DerivedData")
        device_id = create_and_boot_ipad(f"WRhythm iPad Background Audio {os.getpid()}")
        simctl("install", device_id, str(app), timeout=120)
        launch_harness_app(device_id)
        device = HarnessDevice(app_container(device_id))
        device.wait_for_status()
        run_background_audio_check(device_id, device)
    finally:
        if device_id and not args.keep_simulator:
            simctl("shutdown", device_id, check=False, timeout=90)
            simctl("delete", device_id, check=False, timeout=90)
        if not args.keep_simulator:
            shutil.rmtree(temp_dir, ignore_errors=True)
