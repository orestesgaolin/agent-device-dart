#!/usr/bin/env bash
set -euo pipefail

repo_root="${GITHUB_WORKSPACE:-$PWD}"
video_dir="${FIXTURE_ARTIFACT_DIR:?}/videos"
raw_video="$video_dir/ios-fixture-raw.mp4"
compressed_video="$video_dir/ios-fixture.mp4"
udid="${FIXTURE_IOS_UDID:?}"
record_started=0

mkdir -p "$video_dir" "${AGENT_DEVICE_STATE_DIR:?}"
cd "$repo_root"

cleanup() {
  status=$?
  trap - EXIT
  set +e

  if [[ "$record_started" == "1" ]]; then
    dart run packages/agent_device/bin/agent_device.dart record stop "$raw_video" --session fixture-ios-ci --platform ios --serial "$udid" --json || true
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

dart run packages/agent_device/bin/agent_device.dart open com.example.agentDeviceFixtureApp --session fixture-ios-ci --platform ios --serial "$udid" --json
dart run packages/agent_device/bin/agent_device.dart snapshot --session fixture-ios-ci --platform ios --serial "$udid" --json
dart run packages/agent_device/bin/agent_device.dart record start "$raw_video" --session fixture-ios-ci --platform ios --serial "$udid" --json
record_started=1

AGENT_DEVICE_FIXTURE_IOS_LIVE=1 \
AGENT_DEVICE_FIXTURE_IOS_UDID="$udid" \
dart test packages/agent_device/test/platforms/ios/fixture_app_live_test.dart