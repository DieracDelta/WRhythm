#!/usr/bin/env python3
import argparse
import atexit
import json
import os
import plistlib
import random
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WRhythm.xcodeproj"
IOS_BUNDLE_ID = "com.restivollc.wrhythm"
WATCH_BUNDLE_ID = "com.restivollc.wrhythm.watchkitapp"
MAC_BUNDLE_ID = "com.restivollc.wrhythm.macos"


class HarnessError(RuntimeError):
    pass


def run(args, *, env=None, capture=True, check=True, timeout=None):
    completed = subprocess.run(
        args,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        timeout=timeout,
    )
    if check and completed.returncode != 0:
        output = completed.stdout or ""
        raise HarnessError(f"{' '.join(args)} failed with {completed.returncode}\n{output[-4000:]}")
    return completed.stdout or ""


def simctl(*args, **kwargs):
    return run(["xcrun", "simctl", *args], **kwargs)


def run_bounded(args, *, env=None, timeout=20):
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
        return tuple(int(part) for part in re.findall(r"\d+", runtime.get("version", "0")))

    return max(candidates, key=version_tuple)["identifier"]


def choose_device_type(product_family, preferred_names):
    data = json.loads(simctl("list", "-j", "devicetypes"))
    devices = [
        device for device in data["devicetypes"]
        if device.get("productFamily") == product_family and device.get("identifier")
    ]
    if not devices:
        raise HarnessError(f"No simulator device type for {product_family}")

    for preferred_name in preferred_names:
        for device in devices:
            if device.get("name") == preferred_name:
                return device["identifier"]
    for preferred_name in preferred_names:
        for device in devices:
            if preferred_name in device.get("name", ""):
                return device["identifier"]
    return devices[-1]["identifier"]


def build_apps(derived_data):
    print("Building iPhone/watch app...")
    run([
        "xcodebuild", "build",
        "-project", str(PROJECT),
        "-scheme", "WRhythm iPhone",
        "-configuration", "Debug",
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(derived_data),
    ])
    print("Built iPhone/watch app.")

    print("Building macOS app...")
    run([
        "xcodebuild", "build",
        "-project", str(PROJECT),
        "-scheme", "WRhythm macOS",
        "-configuration", "Debug",
        "-destination", "platform=macOS",
        "-derivedDataPath", str(derived_data),
    ])
    print("Built macOS app.")

    products = derived_data / "Build" / "Products"
    ios_app = products / "Debug-iphonesimulator" / "WRhythm.app"
    watch_app = ios_app / "Watch" / "WRhythm Watch App.app"
    mac_app = products / "Debug" / "WRhythm.app"
    for app in [ios_app, watch_app, mac_app]:
        if not app.exists():
            raise HarnessError(f"Expected built app missing: {app}")
    return ios_app, watch_app, mac_app


class LiveDevice:
    def __init__(self, name, kind, device_id, bundle_id):
        self.name = name
        self.kind = kind
        self.device_id = device_id
        self.bundle_id = bundle_id
        self.container = None
        self.state_path = None
        self.command_path = None
        self.command_counter = 0

    def open(self, command, **params):
        if self.command_path is None:
            self.refresh_container()
        write_command(self.command_path, self.next_command_id(), command, params)

    def next_command_id(self):
        self.command_counter += 1
        return f"{self.name}-{self.command_counter}"

    def refresh_container(self):
        container = simctl("get_app_container", self.device_id, self.bundle_id, "data").strip()
        self.container = Path(container)
        harness_dir = self.container / "Library" / "Application Support" / "WRhythm" / "SyncHarness"
        self.state_path = harness_dir / "state.json"
        self.command_path = harness_dir / "command.json"

    def status(self):
        if self.state_path is None:
            self.refresh_container()
        with self.state_path.open() as handle:
            return json.load(handle)


class MacDevice:
    def __init__(self, app_path, state_path):
        self.name = "mac"
        self.kind = "mac"
        self.app_path = app_path
        self.state_path = state_path
        self.command_path = state_path.with_name("command.json")
        self.command_counter = 0
        self.process = None

    def launch(self):
        lsregister = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        if lsregister.exists():
            run([str(lsregister), "-f", str(self.app_path)], capture=True, check=False)
        env = os.environ.copy()
        env.update({
            "WRHYTHM_SYNC_HARNESS": "1",
            "WRHYTHM_SYNC_HARNESS_DEVICE_ID": "harness-mac",
            "WRHYTHM_SYNC_HARNESS_DEVICE_NAME": "Harness Mac",
            "WRHYTHM_SYNC_HARNESS_STATE_PATH": str(self.state_path),
            "WRHYTHM_SYNC_HARNESS_COMMAND_PATH": str(self.command_path),
        })
        executable = self.app_path / "Contents" / "MacOS" / "WRhythm"
        self.process = subprocess.Popen(
            [str(executable)],
            cwd=ROOT,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def terminate(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def open(self, command, **params):
        self.command_counter += 1
        write_command(self.command_path, f"{self.name}-{self.command_counter}", command, params)

    def status(self):
        with self.state_path.open() as handle:
            return json.load(handle)


def write_command(path, command_id, command, params):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "id": command_id,
        "command": command,
        "parameters": {key: str(value) for key, value in params.items()},
    }
    temp_path = path.with_suffix(f".{command_id}.tmp")
    temp_path.write_text(json.dumps(payload), encoding="utf-8")
    os.replace(temp_path, path)


def wait_for(predicate, description, timeout=30, interval=0.5):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as error:  # noqa: BLE001 - this is a polling harness.
            last_error = error
        time.sleep(interval)
    if last_error:
        raise HarnessError(f"Timed out waiting for {description}: {last_error}")
    raise HarnessError(f"Timed out waiting for {description}")


def wait_for_statuses(devices, timeout=45):
    def read_all():
        statuses = {}
        for device in devices:
            statuses[device.name] = device.status()
        return statuses
    return wait_for(read_all, "all harness status files", timeout=timeout)


def session_signature(status):
    session = status.get("sharedSession")
    if not session:
        return None
    return (
        session.get("currentSongID"),
        session.get("currentIndex"),
        session.get("isPlaying"),
        session.get("outputDeviceID"),
        tuple(session.get("queueIDs", [])),
    )


def wait_for_convergence(devices, expected=None, timeout=20):
    last_signatures = {}

    def converged():
        nonlocal last_signatures
        statuses = wait_for_statuses(devices, timeout=2)
        signatures = {name: session_signature(status) for name, status in statuses.items()}
        last_signatures = signatures
        if any(signature is None for signature in signatures.values()):
            return None
        unique = set(signatures.values())
        if len(unique) != 1:
            return None
        signature = next(iter(unique))
        if expected is not None and signature != expected:
            return None
        return statuses
    try:
        return wait_for(converged, "playback session convergence", timeout=timeout)
    except HarnessError as error:
        raise HarnessError(f"{error}\nLast signatures: {last_signatures}") from error


def print_status_snapshot(devices):
    print("Status snapshot:")
    for device in devices:
        try:
            status = device.status()
            session = status.get("sharedSession") or {}
            print(
                " ",
                device.name,
                "device=", status.get("deviceID"),
                "peers=", status.get("peerIDs"),
                "connected=", status.get("connectedDeviceNames"),
                "wc=", status.get("watchConnectivity"),
                "cmd=", status.get("lastProcessedCommandID"),
                status.get("lastProcessedCommand"),
                "song=", session.get("currentSongID"),
                "index=", session.get("currentIndex"),
                "playing=", session.get("isPlaying"),
                "output=", session.get("outputDeviceID"),
                "lastError=", status.get("lastError"),
            )
        except Exception as error:  # noqa: BLE001 - diagnostic path.
            print(" ", device.name, "status unavailable:", error)


def create_and_boot_pair():
    ios_runtime = latest_runtime("iOS")
    watch_runtime = latest_runtime("watchOS")
    iphone_type = os.environ.get("WRHYTHM_HARNESS_IPHONE_TYPE") or choose_device_type(
        "iPhone",
        ["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 15 Pro"],
    )
    watch_type = os.environ.get("WRHYTHM_HARNESS_WATCH_TYPE") or choose_device_type(
        "Apple Watch",
        ["Apple Watch SE 3 (40mm)", "Apple Watch Ultra 3 (49mm)", "Apple Watch Series 11 (46mm)"],
    )

    phone = simctl("create", "WRhythm Live Sync iPhone", iphone_type, ios_runtime).strip()
    watch = simctl("create", "WRhythm Live Sync Watch", watch_type, watch_runtime).strip()

    simctl("pair", watch, phone)
    pair_id = find_pair_id(phone, watch)
    if pair_id:
        simctl("pair_activate", pair_id, check=False)
        simctl("boot", pair_id, check=False)
    else:
        simctl("boot", phone, check=False)
        simctl("boot", watch, check=False)

    print("Waiting for iPhone simulator boot/data migration...")
    simctl("bootstatus", phone, "-b", timeout=600)
    print("Waiting for watch simulator boot/data migration...")
    simctl("bootstatus", watch, "-b", timeout=600)
    return phone, watch


def find_pair_id(phone, watch):
    pairs = json.loads(simctl("list", "-j", "pairs")).get("pairs", {})
    for pair_id, pair in pairs.items():
        if pair.get("phone", {}).get("udid") == phone and pair.get("watch", {}).get("udid") == watch:
            return pair_id
    return None


def install_sim_app(device, app_path):
    simctl("install", device.device_id, str(app_path))


def launch_sim_app(device, harness_id, harness_name):
    env = os.environ.copy()
    env.update({
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS": "1",
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DEVICE_ID": harness_id,
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DEVICE_NAME": harness_name,
    })
    run_bounded(
        [
            "xcrun", "simctl",
            "launch",
            "--terminate-running-process",
            "--stdout=/dev/null",
            "--stderr=/dev/null",
            device.device_id,
            device.bundle_id,
        ],
        env=env,
        timeout=20,
    )
    device.refresh_container()


def fuzz(devices, iterations, seed):
    rng = random.Random(seed)
    actors = list(devices)

    print("Searching/resyncing peers...")
    for device in devices:
        device.open("sync")
    time.sleep(4)

    print("Publishing seed playback session from mac...")
    mac = next(device for device in devices if device.name == "mac")
    mac.open("publish", prefix="seed", count=8, index=0, position=0, playing="true", output="local")
    expected_seed = ("seed-0", 0, True, "harness-mac", tuple(f"seed-{index}" for index in range(8)))
    statuses = wait_for_convergence(devices, expected=expected_seed, timeout=45)
    print("Initial convergence:", {name: status["sharedSession"]["currentSongID"] for name, status in statuses.items()})
    expected_signature = expected_seed

    for index in range(iterations):
        actor = rng.choice(actors)
        operation = rng.choice(["publish", "play", "pause", "seek", "next", "previous"])
        if operation == "publish":
            count = rng.randint(3, 12)
            current_index = rng.randint(0, min(2, count - 1))
            is_playing = rng.choice([True, False])
            prefix = f"fuzz{index}-{actor.name}"
            actor_device_id = actor.status()["deviceID"]
            actor.open(
                "publish",
                prefix=prefix,
                count=count,
                index=current_index,
                position=rng.randint(0, 80),
                playing=str(is_playing).lower(),
                output="local",
            )
            expected_signature = (
                f"{prefix}-{current_index}",
                current_index,
                is_playing,
                actor_device_id,
                tuple(f"{prefix}-{queue_index}" for queue_index in range(count)),
            )
        elif operation == "seek":
            actor.open("seek", position=rng.randint(0, 240))
        else:
            actor.open(operation)
            song_id, current_index, is_playing, output_device_id, queue_ids = expected_signature
            if operation == "play":
                is_playing = True
            elif operation == "pause":
                is_playing = False
            elif operation == "next":
                current_index = min(current_index + 1, len(queue_ids) - 1)
                song_id = queue_ids[current_index]
            elif operation == "previous":
                current_index = max(current_index - 1, 0)
                song_id = queue_ids[current_index]
            expected_signature = (song_id, current_index, is_playing, output_device_id, queue_ids)

        statuses = wait_for_convergence(devices, expected=expected_signature, timeout=30)
        signature = session_signature(next(iter(statuses.values())))
        print(f"{index + 1:03d}/{iterations} {actor.name}:{operation} -> {signature[:4]}")


def main():
    parser = argparse.ArgumentParser(description="Run live WRhythm sync fuzzing across iPhone, Watch, and macOS app processes.")
    parser.add_argument("--iterations", type=int, default=int(os.environ.get("WRHYTHM_LIVE_FUZZ_ITERATIONS", "30")))
    parser.add_argument("--seed", type=int, default=int(os.environ.get("WRHYTHM_LIVE_FUZZ_SEED", "20260525")))
    parser.add_argument("--keep-simulators", action="store_true")
    parser.add_argument(
        "--allow-unreachable-watch",
        action="store_true",
        help="Continue fuzzing the mac/iPhone sync cluster if the watch simulator cannot establish WatchConnectivity.",
    )
    args = parser.parse_args()

    temp_dir = Path(tempfile.mkdtemp(prefix="wrhythm-live-sync."))
    derived_data = temp_dir / "DerivedData"
    created_sims = []
    mac_device = None

    def cleanup():
        if mac_device is not None:
            mac_device.terminate()
        if not args.keep_simulators:
            for device_id in created_sims:
                simctl("shutdown", device_id, check=False)
                simctl("delete", device_id, check=False)
        shutil.rmtree(temp_dir, ignore_errors=True)

    atexit.register(cleanup)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(130))

    ios_app, watch_app, mac_app = build_apps(derived_data)
    phone_id, watch_id = create_and_boot_pair()
    created_sims.extend([phone_id, watch_id])

    iphone = LiveDevice("iphone", "ios", phone_id, IOS_BUNDLE_ID)
    watch = LiveDevice("watch", "watchos", watch_id, WATCH_BUNDLE_ID)
    install_sim_app(iphone, ios_app)
    install_sim_app(watch, watch_app)
    launch_sim_app(iphone, "harness-iphone", "Harness iPhone")
    launch_sim_app(watch, "harness-watch", "Harness Watch")

    mac_device = MacDevice(mac_app, temp_dir / "mac-state.json")
    mac_device.launch()

    devices = [iphone, watch, mac_device]
    wait_for_statuses(devices, timeout=60)
    if args.allow_unreachable_watch:
        print("Watch simulator launched; fuzzing mac/iPhone sync cluster while watch transport remains observable.")
        print_status_snapshot(devices)
        devices = [iphone, mac_device]
    try:
        fuzz(devices, args.iterations, args.seed)
    except Exception:
        print_status_snapshot(devices)
        raise
    print("Live sync fuzz passed.")


if __name__ == "__main__":
    main()
