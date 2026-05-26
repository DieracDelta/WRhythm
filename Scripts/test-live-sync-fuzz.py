#!/usr/bin/env python3
import argparse
import atexit
import base64
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
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WRhythm.xcodeproj"
IOS_BUNDLE_ID = "com.restivollc.wrhythm"
WATCH_BUNDLE_ID = "com.restivollc.wrhythm.watchkitapp"
MAC_BUNDLE_ID = "com.restivollc.wrhythm.macos"


class HarnessError(RuntimeError):
    pass


def run(args, *, env=None, capture=True, check=True, timeout=None):
    try:
        completed = subprocess.run(
            args,
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.STDOUT if capture else None,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        raise HarnessError(f"{' '.join(args)} timed out after {timeout}s") from error
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

    def apply_session(self, session):
        self.open("applySession", session=encode_session(session))

    def next_command_id(self):
        self.command_counter += 1
        return f"{self.name}-{self.command_counter}"

    def refresh_container(self):
        def container_path():
            return simctl("get_app_container", self.device_id, self.bundle_id, "data", timeout=15).strip()

        container = wait_for(
            container_path,
            f"{self.name} app data container",
            timeout=90,
            interval=2,
        )
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
    def __init__(self, app_path, state_path, disable_real_transports):
        self.name = "mac"
        self.kind = "mac"
        self.app_path = app_path
        self.state_path = state_path
        self.command_path = state_path.with_name("command.json")
        self.command_counter = 0
        self.disable_real_transports = disable_real_transports
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
        if self.disable_real_transports:
            env["WRHYTHM_SYNC_HARNESS_DISABLE_REAL_TRANSPORTS"] = "1"
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

    def apply_session(self, session):
        self.open("applySession", session=encode_session(session))

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


def encode_session(session):
    data = json.dumps(session, separators=(",", ":")).encode("utf-8")
    return base64.b64encode(data).decode("ascii")


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


def wait_for_convergence(
    devices,
    expected=None,
    timeout=20,
    host_relay=False,
    relay_model=None,
    included_names=None,
    position_tolerance=None,
):
    last_signatures = {}
    included_names = set(included_names or [device.name for device in devices])

    def converged():
        nonlocal last_signatures
        statuses = wait_for_statuses(devices, timeout=2)
        if host_relay:
            if relay_model is not None:
                relay_model.relay(devices, statuses, expected)
            else:
                relay_best_session(devices, statuses, expected)
        signatures = {
            name: session_signature(status)
            for name, status in statuses.items()
            if name in included_names
        }
        last_signatures = signatures
        if any(signature is None for signature in signatures.values()):
            return None
        unique = set(signatures.values())
        if len(unique) != 1:
            return None
        signature = next(iter(unique))
        if expected is not None and signature != expected:
            return None
        if position_tolerance is not None and not positions_are_close(statuses, included_names, position_tolerance):
            return None
        return statuses
    try:
        return wait_for(converged, "playback session convergence", timeout=timeout)
    except HarnessError as error:
        raise HarnessError(f"{error}\nLast signatures: {last_signatures}") from error


def positions_are_close(statuses, included_names, tolerance):
    positions = []
    for name in included_names:
        session = statuses.get(name, {}).get("sharedSession")
        if not session:
            return False
        position = session.get("estimatedPosition")
        if position is None:
            return False
        positions.append(float(position))
    return max(positions) - min(positions) <= tolerance


class RelayFaultModel:
    def __init__(
        self,
        seed,
        min_latency_ms=0,
        max_latency_ms=0,
        drop_rate=0,
        duplicate_rate=0,
    ):
        self.rng = random.Random(seed)
        self.min_latency = min_latency_ms / 1000
        self.max_latency = max_latency_ms / 1000
        self.drop_rate = drop_rate
        self.duplicate_rate = duplicate_rate
        self.online = {}
        self.pending = []
        self.pending_keys = set()

    def register(self, devices):
        for device in devices:
            self.online.setdefault(device.name, True)

    def is_online(self, device_name):
        return self.online.get(device_name, True)

    def included_names(self, devices):
        return [device.name for device in devices if self.is_online(device.name)]

    def disconnect(self, device_name):
        self.online[device_name] = False
        self.pending = [
            delivery
            for delivery in self.pending
            if delivery["source"] != device_name and delivery["destination"] != device_name
        ]
        self.pending_keys = {delivery["key"] for delivery in self.pending}

    def reconnect(self, device_name):
        self.online[device_name] = True

    def relay(self, devices, statuses, expected=None):
        self.deliver_due(devices)
        candidate_name, candidate_session, candidate_signature = self.choose_candidate(statuses, expected)
        if candidate_session is None:
            return

        for device in devices:
            if device.name == candidate_name:
                continue
            if not self.can_deliver(candidate_name, device.name):
                continue
            if session_signature(statuses.get(device.name, {})) != candidate_signature:
                self.schedule(candidate_name, device, candidate_session, candidate_signature)

    def choose_candidate(self, statuses, expected=None):
        candidate_name = None
        candidate_session = None
        candidate_signature = None

        if expected is not None:
            for name, status in statuses.items():
                if not self.is_online(name):
                    continue
                if session_signature(status) == expected and status.get("sharedSessionPayload"):
                    return name, status["sharedSessionPayload"], expected
            return None, None, None

        for name, status in statuses.items():
            if not self.is_online(name):
                continue
            session = status.get("sharedSessionPayload")
            signature = session_signature(status)
            if session is None or signature is None:
                continue
            if candidate_session is None or self.session_key(session) > self.session_key(candidate_session):
                candidate_name = name
                candidate_session = session
                candidate_signature = signature

        return candidate_name, candidate_session, candidate_signature

    def session_key(self, session):
        return (
            session.get("revision", 0),
            session.get("updatedAt", ""),
            session.get("updatedByDeviceID", ""),
        )

    def can_deliver(self, source_name, destination_name):
        return self.is_online(source_name) and self.is_online(destination_name)

    def schedule(self, source_name, destination, session, signature, force=False):
        key = (
            source_name,
            destination.name,
            signature,
            session.get("updatedAt"),
            session.get("updatedByDeviceID"),
        )
        if key in self.pending_keys:
            return
        if not force and self.drop_rate > 0 and self.rng.random() < self.drop_rate:
            return

        delay = self.rng.uniform(self.min_latency, self.max_latency)
        self.pending.append({
            "due": time.monotonic() + delay,
            "source": source_name,
            "destination": destination.name,
            "device": destination,
            "session": session,
            "key": key,
        })
        self.pending_keys.add(key)

        if not force and self.duplicate_rate > 0 and self.rng.random() < self.duplicate_rate:
            duplicate_key = (*key, "duplicate")
            self.pending.append({
                "due": time.monotonic() + delay + self.rng.uniform(0, max(self.max_latency, 0.2)),
                "source": source_name,
                "destination": destination.name,
                "device": destination,
                "session": session,
                "key": duplicate_key,
            })
            self.pending_keys.add(duplicate_key)

    def deliver_due(self, devices):
        now = time.monotonic()
        still_pending = []
        for delivery in self.pending:
            if delivery["due"] > now:
                still_pending.append(delivery)
                continue
            self.pending_keys.discard(delivery["key"])
            if self.can_deliver(delivery["source"], delivery["destination"]):
                delivery["device"].apply_session(delivery["session"])
        self.pending = still_pending

    def force_deliver(self, source_name, devices, session, signature, destinations=None):
        destinations = set(destinations or [device.name for device in devices])
        for device in devices:
            if device.name == source_name or device.name not in destinations:
                continue
            if self.can_deliver(source_name, device.name):
                self.schedule(source_name, device, session, signature, force=True)


def relay_best_session(devices, statuses, expected=None):
    candidate_name = None
    candidate_session = None
    candidate_signature = None

    if expected is not None:
        for name, status in statuses.items():
            if session_signature(status) == expected and status.get("sharedSessionPayload"):
                candidate_name = name
                candidate_session = status["sharedSessionPayload"]
                candidate_signature = expected
                break
    else:
        for name, status in statuses.items():
            session = status.get("sharedSessionPayload")
            signature = session_signature(status)
            if session is None or signature is None:
                continue
            if candidate_session is None:
                candidate_name = name
                candidate_session = session
                candidate_signature = signature
                continue
            candidate_key = (
                session.get("revision", 0),
                session.get("updatedAt", ""),
                session.get("updatedByDeviceID", ""),
            )
            best_key = (
                candidate_session.get("revision", 0),
                candidate_session.get("updatedAt", ""),
                candidate_session.get("updatedByDeviceID", ""),
            )
            if candidate_key > best_key:
                candidate_name = name
                candidate_session = session
                candidate_signature = signature

    if candidate_session is None:
        return

    for device in devices:
        if device.name == candidate_name:
            continue
        if session_signature(statuses.get(device.name, {})) != candidate_signature:
            device.apply_session(candidate_session)


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


def iso_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def session_signature_from_payload(session):
    queue = session.get("queue", [])
    current_index = session.get("currentIndex")
    current_song_id = None
    if isinstance(current_index, int) and 0 <= current_index < len(queue):
        current_song_id = queue[current_index].get("id")
    return (
        current_song_id,
        current_index,
        session.get("isPlaying"),
        session.get("outputDeviceID"),
        tuple(song.get("id") for song in queue),
    )


def clone_session(session, **updates):
    cloned = json.loads(json.dumps(session))
    cloned.update(updates)
    return cloned


def paused_session_for_disconnect(status, updated_by_device_id):
    session = status.get("sharedSessionPayload")
    if not session:
        raise HarnessError("Cannot pause disconnected output without a shared session payload")
    return clone_session(
        session,
        revision=session.get("revision", 0) + 1,
        position=status.get("sharedSession", {}).get("estimatedPosition", session.get("position", 0)),
        isPlaying=False,
        updatedAt=iso_now(),
        updatedByDeviceID=updated_by_device_id,
    )


def run_transport_scenarios(devices, relay_model):
    print("Running deterministic disconnect/reconnect transport scenarios...")
    relay_model.register(devices)
    mac = next(device for device in devices if device.name == "mac")
    iphone = next(device for device in devices if device.name == "iphone")
    watch = next(device for device in devices if device.name == "watch")

    mac.open("publish", prefix="dc-mac", count=6, index=1, position=12, playing="true", output="local")
    mac_playing = ("dc-mac-1", 1, True, "harness-mac", tuple(f"dc-mac-{index}" for index in range(6)))
    statuses = wait_for_convergence(
        devices,
        expected=mac_playing,
        timeout=45,
        host_relay=True,
        relay_model=relay_model,
        included_names=relay_model.included_names(devices),
        position_tolerance=6,
    )

    relay_model.disconnect("mac")
    paused = paused_session_for_disconnect(statuses["mac"], updated_by_device_id="harness-iphone")
    paused_signature = session_signature_from_payload(paused)
    for device in [iphone, watch]:
        device.apply_session(paused)
    wait_for_convergence(
        devices,
        expected=paused_signature,
        timeout=30,
        host_relay=True,
        relay_model=relay_model,
        included_names=relay_model.included_names(devices),
        position_tolerance=6,
    )
    print("  disconnected active mac -> iPhone/watch paused")

    relay_model.reconnect("mac")
    wait_for_convergence(
        devices,
        expected=mac_playing,
        timeout=45,
        host_relay=True,
        relay_model=relay_model,
        included_names=relay_model.included_names(devices),
        position_tolerance=8,
    )
    print("  reconnected still-playing mac -> all devices adopted mac session")

    relay_model.disconnect("watch")
    iphone.open("next")
    iphone_next = ("dc-mac-2", 2, True, "harness-mac", tuple(f"dc-mac-{index}" for index in range(6)))
    wait_for_convergence(
        devices,
        expected=iphone_next,
        timeout=30,
        host_relay=True,
        relay_model=relay_model,
        included_names=relay_model.included_names(devices),
        position_tolerance=8,
    )
    print("  watch partitioned -> iPhone/mac still converged on next")

    relay_model.reconnect("watch")
    wait_for_convergence(
        devices,
        expected=iphone_next,
        timeout=45,
        host_relay=True,
        relay_model=relay_model,
        included_names=relay_model.included_names(devices),
        position_tolerance=8,
    )
    print("  watch reconnected -> caught up to latest online state")


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


def launch_sim_app(device, harness_id, harness_name, disable_real_transports):
    env = os.environ.copy()
    env.update({
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS": "1",
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DEVICE_ID": harness_id,
        "SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DEVICE_NAME": harness_name,
    })
    if disable_real_transports:
        env["SIMCTL_CHILD_WRHYTHM_SYNC_HARNESS_DISABLE_REAL_TRANSPORTS"] = "1"
    last_error = None
    for attempt in range(1, 4):
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
            timeout=45,
        )
        try:
            device.refresh_container()
            return
        except HarnessError as error:
            last_error = error
            print(f"Retrying {device.name} app launch after container discovery failed (attempt {attempt}/3)...")
            simctl("terminate", device.device_id, device.bundle_id, check=False, timeout=15)
            time.sleep(3)
    raise HarnessError(f"Unable to discover {device.name} app data container after launch: {last_error}")


def fuzz(devices, iterations, seed, host_relay, relay_model=None, include_partitions=False):
    rng = random.Random(seed)
    actors = list(devices)
    if relay_model is not None:
        relay_model.register(devices)

    print("Searching/resyncing peers...")
    for device in devices:
        device.open("sync")
    time.sleep(4)

    print("Publishing seed playback session from mac...")
    mac = next(device for device in devices if device.name == "mac")
    mac.open("publish", prefix="seed", count=8, index=0, position=0, playing="true", output="local")
    expected_seed = ("seed-0", 0, True, "harness-mac", tuple(f"seed-{index}" for index in range(8)))
    statuses = wait_for_convergence(
        devices,
        expected=expected_seed,
        timeout=45,
        host_relay=host_relay,
        relay_model=relay_model,
        included_names=relay_model.included_names(devices) if relay_model is not None else None,
        position_tolerance=6,
    )
    print("Initial convergence:", {name: status["sharedSession"]["currentSongID"] for name, status in statuses.items()})
    expected_signature = expected_seed
    expected_position_tolerance = 6

    for index in range(iterations):
        online_actors = [
            actor for actor in actors
            if relay_model is None or relay_model.is_online(actor.name)
        ]
        if not online_actors:
            raise HarnessError("All devices are disconnected")

        actor = rng.choice(online_actors)
        operations = ["publish", "play", "pause", "seek", "next", "previous"]
        if include_partitions:
            operations += ["disconnect", "reconnect"]
        operation = rng.choice(operations)

        if operation == "disconnect":
            online_names = [device.name for device in devices if relay_model.is_online(device.name)]
            if len(online_names) <= 1:
                operation = "reconnect"
            else:
                disconnect_name = rng.choice(online_names)
                actor = next(device for device in devices if device.name == disconnect_name)
                statuses = wait_for_statuses(devices, timeout=5)
                active_output = expected_signature[3]
                actor_device_id = actor.status()["deviceID"]
                relay_model.disconnect(actor.name)
                if active_output == actor_device_id and expected_signature[2]:
                    remaining = relay_model.included_names(devices)
                    if not remaining:
                        relay_model.reconnect(actor.name)
                    else:
                        applier = next(device for device in devices if device.name == remaining[0])
                        paused = paused_session_for_disconnect(statuses[actor.name], applier.status()["deviceID"])
                        expected_signature = session_signature_from_payload(paused)
                        for device in devices:
                            if device.name in remaining:
                                device.apply_session(paused)
                statuses = wait_for_convergence(
                    devices,
                    expected=expected_signature,
                    timeout=30,
                    host_relay=host_relay,
                    relay_model=relay_model,
                    included_names=relay_model.included_names(devices),
                    position_tolerance=expected_position_tolerance,
                )
                signature = session_signature(next(iter(statuses.values())))
                print(f"{index + 1:03d}/{iterations} {actor.name}:disconnect -> {signature[:4]}")
                continue

        if operation == "reconnect":
            offline = [device for device in devices if not relay_model.is_online(device.name)]
            if not offline:
                operation = rng.choice(["publish", "play", "pause", "seek", "next", "previous"])
            else:
                actor = rng.choice(offline)
                relay_model.reconnect(actor.name)
                actor_signature = session_signature(actor.status())
                if actor_signature is not None and actor_signature[2] and not expected_signature[2]:
                    expected_signature = actor_signature
                statuses = wait_for_convergence(
                    devices,
                    expected=expected_signature,
                    timeout=45,
                    host_relay=host_relay,
                    relay_model=relay_model,
                    included_names=relay_model.included_names(devices),
                    position_tolerance=expected_position_tolerance,
                )
                signature = session_signature(next(iter(statuses.values())))
                print(f"{index + 1:03d}/{iterations} {actor.name}:reconnect -> {signature[:4]}")
                continue

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
            expected_position_tolerance = 6
        elif operation == "seek":
            actor.open("seek", position=rng.randint(0, 240))
            expected_position_tolerance = 10
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
            expected_position_tolerance = 8 if is_playing else 6

        statuses = wait_for_convergence(
            devices,
            expected=expected_signature,
            timeout=45,
            host_relay=host_relay,
            relay_model=relay_model,
            included_names=relay_model.included_names(devices) if relay_model is not None else None,
            position_tolerance=expected_position_tolerance,
        )
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
    parser.add_argument(
        "--watchconnectivity-only",
        action="store_true",
        help="Use native app transports only. By default the simulator harness uses a host relay because CLI-installed standalone watch apps do not reliably appear as installed companions to WCSession.",
    )
    parser.add_argument("--min-latency-ms", type=int, default=0)
    parser.add_argument("--max-latency-ms", type=int, default=750)
    parser.add_argument("--drop-rate", type=float, default=0.15)
    parser.add_argument("--duplicate-rate", type=float, default=0.10)
    parser.add_argument(
        "--skip-transport-scenarios",
        action="store_true",
        help="Skip deterministic disconnect/reconnect scenarios in host-relay mode.",
    )
    parser.add_argument(
        "--no-partition-fuzz",
        action="store_true",
        help="Do not include random disconnect/reconnect operations in the fuzz loop.",
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
    host_relay = not args.watchconnectivity_only

    iphone = LiveDevice("iphone", "ios", phone_id, IOS_BUNDLE_ID)
    watch = LiveDevice("watch", "watchos", watch_id, WATCH_BUNDLE_ID)
    install_sim_app(iphone, ios_app)
    install_sim_app(watch, watch_app)
    launch_sim_app(watch, "harness-watch", "Harness Watch", disable_real_transports=host_relay)
    launch_sim_app(iphone, "harness-iphone", "Harness iPhone", disable_real_transports=host_relay)

    mac_device = MacDevice(mac_app, temp_dir / "mac-state.json", disable_real_transports=host_relay)
    mac_device.launch()

    devices = [iphone, watch, mac_device]
    wait_for_statuses(devices, timeout=60)
    relay_model = None
    if host_relay:
        print("Using simulator host relay for iPhone/watch sync transport.")
        relay_model = RelayFaultModel(
            seed=args.seed + 17,
            min_latency_ms=args.min_latency_ms,
            max_latency_ms=args.max_latency_ms,
            drop_rate=args.drop_rate,
            duplicate_rate=args.duplicate_rate,
        )
        relay_model.register(devices)
    elif args.allow_unreachable_watch:
        print("Watch simulator launched; fuzzing mac/iPhone sync cluster while watch transport remains observable.")
        print_status_snapshot(devices)
        devices = [iphone, mac_device]
    try:
        if host_relay and not args.skip_transport_scenarios:
            run_transport_scenarios(devices, relay_model)
        fuzz(
            devices,
            args.iterations,
            args.seed,
            host_relay=host_relay,
            relay_model=relay_model,
            include_partitions=host_relay and not args.no_partition_fuzz,
        )
    except Exception:
        print_status_snapshot(devices)
        raise
    print("Live sync fuzz passed.")


if __name__ == "__main__":
    main()
