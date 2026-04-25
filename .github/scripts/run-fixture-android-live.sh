#!/usr/bin/env bash
set -euo pipefail

repo_root="${GITHUB_WORKSPACE:-$PWD}"
video_dir="${FIXTURE_ARTIFACT_DIR:?}/videos"
raw_video="$video_dir/android-fixture-raw.mp4"
compressed_video="$video_dir/android-fixture.mp4"
record_started=0

mkdir -p "$video_dir" "${AGENT_DEVICE_STATE_DIR:?}"
cd "$repo_root"

cleanup() {
  status=$?
  trap - EXIT
  set +e

  if [[ "$record_started" == "1" ]]; then
    dart run packages/agent_device/bin/agent_device.dart record stop "$raw_video" --session fixture-android-ci --platform android --serial emulator-5554 --json || true
    if [[ -f "$raw_video" ]]; then
      ffmpeg -y -i "$raw_video" \
        -c:v libx264 -crf 22 -preset fast -profile:v main -level 4.0 \
        -vf "fps=min(30\\,source_fps)" \
        -c:a aac -b:a 128k \
        -movflags +faststart \
        "$compressed_video" || true
      if [[ -f "$compressed_video" ]]; then
        rm -f "$raw_video"
      fi
    fi
  fi

  exit "$status"
}

trap cleanup EXIT

cd test_apps/agent_device_fixture_app
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
cd "$repo_root"

dart run packages/agent_device/bin/agent_device.dart open com.example.agent_device_fixture_app --session fixture-android-ci --platform android --serial emulator-5554 --json
dart run packages/agent_device/bin/agent_device.dart snapshot --session fixture-android-ci --platform android --serial emulator-5554 --json
dart run packages/agent_device/bin/agent_device.dart record start "$raw_video" --session fixture-android-ci --platform android --serial emulator-5554 --json
record_started=1

AGENT_DEVICE_FIXTURE_ANDROID_LIVE=1 \
AGENT_DEVICE_FIXTURE_ANDROID_SERIAL=emulator-5554 \
dart test packages/agent_device/test/platforms/android/fixture_app_live_test.dart