#!/bin/bash
# The AppImage on a clean Ubuntu, as gnustep-release-actions' appimage-test
# runs it (.github/release/appimage.conf, SMOKE_SCRIPT): each app in the
# image starts and stays up, the chooser, WorkflowDesk and the designer,
# against a virtual display.
#   Scripts/appimage-smoke.sh <WorkflowKit AppImage>
set -euo pipefail
image=$1
for app in "" desk designer; do
  timeout 90 xvfb-run -a "$image" $app &
  pid=$!
  sleep 25
  if kill -0 $pid 2>/dev/null; then
    echo "${app:-launcher}: up after 25s"
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
  else
    status=0; wait $pid || status=$?
    echo "::error::${app:-launcher} exited on its own with status $status"
    exit 1
  fi
done
