#!/usr/bin/env bash
set -euo pipefail

repo_root="${GITHUB_WORKSPACE:-$PWD}"
video_dir="${FIXTURE_ARTIFACT_DIR:?}/videos"
udid="${FIXTURE_IOS_UDID:?}"

mkdir -p "$video_dir" "${AGENT_DEVICE_STATE_DIR:?}"
cd "$repo_root"

compress_video() {
  local raw="$1"
  local out="$2"
  if [[ ! -f "$raw" ]]; then return; fi
  ffmpeg -y -i "$raw" \
    -c:v libx264 -crf 22 -preset fast -profile:v main -level 4.0 \
    -vf "fps=min(30\\,source_fps)" \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    "$out" || true
  if [[ -f "$out" ]]; then rm -f "$raw"; fi
}

dart run packages/agent_device/bin/agent_device.dart open com.example.agentDeviceFixtureApp --session fixture-ios-ci --platform ios --serial "$udid" --json
dart run packages/agent_device/bin/agent_device.dart snapshot --session fixture-ios-ci --platform ios --serial "$udid" --json

# TestRecorder inside the Dart test handles record start/stop + chapter
# markers. AD_RECORD_TESTS tells it where to write the raw MP4.
AGENT_DEVICE_FIXTURE_IOS_LIVE=1 \
AGENT_DEVICE_FIXTURE_IOS_UDID="$udid" \
AD_RECORD_TESTS="$video_dir" \
dart test packages/agent_device/test/platforms/ios/fixture_app_live_test.dart || true

# Compress the chaptered recording for upload.
compress_video "$video_dir/fixture-ios.mp4" "$video_dir/fixture-ios-compressed.mp4"
