#!/usr/bin/env bash
set -euo pipefail
pkg=io.srtristesad.mooio.beta
on_error() {
  echo "MOOIO_LIFECYCLE_EMULATOR_FAILED"
  adb logcat -d -v time -s MooIO-Host:V MooIO-HostControl:V MooIO-Node:V AndroidRuntime:E libc:F | tail -125 || true
  adb shell dumpsys activity services "$pkg" | tail -55 || true
}
trap on_error ERR

adb install -r dist/Moo-IO-Android-Beta-Instalavel.apk
adb shell am start -n "$pkg/org.love2d.android.MooIOActivity"
adb forward tcp:28082 tcp:8082
adb forward tcp:28081 tcp:8081
echo "MENU: NO NODE PROCESS OR FOREGROUND SERVER"
sleep 3
if adb shell pidof "$pkg:mooio_node"; then
  echo "FAIL: server auto-started without user opening a room" >&2; exit 1
fi
echo "MOOIO_ANDROID_IDLE_HOST_NOT_RUNNING_PASS"
token=$(adb shell run-as "$pkg" cat files/mooio-control-token.txt | tr -d '\r\n')
test "$(printf '%s' "$token" | wc -c)" -eq 48
if [ "$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:28082/start)" != 404 ]; then
  echo "FAIL: remote app can start server without private token" >&2; exit 1
fi
start() {
  local value
  value=$(curl -fsS --max-time 4 "http://127.0.0.1:28082/start/$token")
  test "$value" = started
  for _ in $(seq 1 25); do
    if curl -fsS --max-time 2 http://127.0.0.1:28081/status 2>/dev/null | grep -q '"project":"Moo-IO"'; then
      adb shell pidof "$pkg:mooio_node"
      echo "MOOIO_ANDROID_HOST_STARTED_PASS"
      return
    fi
    sleep 2
  done
  echo "FAIL: real integrated Node never responded" >&2; return 1
}
stop() {
  local value
  value=$(curl -fsS --max-time 4 "http://127.0.0.1:28082/stop/$token")
  test "$value" = stopped
  for _ in $(seq 1 20); do
    if ! adb shell pidof "$pkg:mooio_node" >/dev/null 2>&1; then
      echo "MOOIO_ANDROID_HOST_STOPPED_RAM_RELEASED_PASS"
      return
    fi
    sleep 1
  done
  echo "FAIL: Node process survived stopping the room" >&2
  return 1
}
start
stop
start
stop
adb shell pidof "$pkg"
adb shell am force-stop "$pkg"
echo "MOOIO_ANDROID_SERVER_LIFECYCLE_PASS"
