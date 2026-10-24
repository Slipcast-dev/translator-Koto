#!/bin/bash
# Единая точка сборки и запуска; никаких системных Gatekeeper/quarantine изменений.
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${KOTO_CONFIGURATION:-Debug}"
BUILD_ROOT="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_ROOT/DerivedData/Build/Products/$CONFIGURATION/Koto.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Koto"

case "$MODE" in
    run|--verify|--build-only|--debug|--logs|--telemetry) ;;
    *) echo "Использование: $0 [--verify|--build-only|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
case "$CONFIGURATION" in
    Debug|Release) ;;
    *) echo "Неизвестная конфигурация: $CONFIGURATION" >&2; exit 2 ;;
esac

# Останавливаем только экземпляр из данного build output, не чужое одноимённое приложение.
if [[ "$MODE" != "--build-only" ]]; then
    while IFS= read -r app_pid; do
        [[ -n "$app_pid" ]] || continue
        executable="$(/bin/ps -p "$app_pid" -o comm= || true)"
        if [[ "$executable" == "$BUILD_ROOT/DerivedData/Build/Products/Debug/Koto.app/Contents/MacOS/Koto" ||
              "$executable" == "$BUILD_ROOT/DerivedData/Build/Products/Release/Koto.app/Contents/MacOS/Koto" ]]; then
            /bin/kill "$app_pid" 2>/dev/null || true
            # Ждём только свой процесс, чтобы при переключении Debug/Release не оставить два экземпляра.
            for wait_step in {1..30}; do
                /bin/kill -0 "$app_pid" 2>/dev/null || break
                /bin/sleep 0.1
            done
            if /bin/kill -0 "$app_pid" 2>/dev/null; then
                echo "Предыдущий Koto ещё завершается; повторите запуск." >&2
                exit 1
            fi
        fi
    done < <(/usr/bin/pgrep -x Koto || true)
fi

mkdir -p "$BUILD_ROOT/logs"
echo "Сборка Koto ($CONFIGURATION)…"
/usr/bin/xcodebuild \
    -project "$ROOT_DIR/Koto.xcodeproj" \
    -scheme Koto \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$BUILD_ROOT/DerivedData" \
    build 2>&1 | /usr/bin/tee "$BUILD_ROOT/logs/build-$CONFIGURATION.log"

echo "Приложение: $APP_BUNDLE"
[[ "$MODE" != "--build-only" ]] || exit 0

case "$MODE" in
    --debug) exec /usr/bin/xcrun lldb -- "$APP_BINARY" ;;
    *) /usr/bin/open -n "$APP_BUNDLE" ;;
esac

if [[ "$MODE" == "--verify" ]]; then
    # Проверка процесса ограничена по времени; GUI-приёмка выполняется отдельно.
    for attempt in {1..40}; do
        while IFS= read -r app_pid; do
            [[ -n "$app_pid" ]] || continue
            executable="$(/bin/ps -p "$app_pid" -o comm= || true)"
            if [[ "$executable" == "$APP_BINARY" ]]; then
                echo "Koto запущен, PID=$app_pid"
                exit 0
            fi
        done < <(/usr/bin/pgrep -x Koto || true)
        /bin/sleep 0.25
    done
    echo "Не удалось подтвердить запуск Koto." >&2
    exit 1
elif [[ "$MODE" == "--logs" ]]; then
    exec /usr/bin/log stream --info --style compact --predicate 'process == "Koto"'
elif [[ "$MODE" == "--telemetry" ]]; then
    exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "dev.slipcast.koto"'
fi
