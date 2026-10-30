#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
ENV_FILE="${MELODISCAN_TEST_ENV_FILE:-$ROOT/.env}"
COMPOSE_ENV_ARGS=()
if [[ -f "$ENV_FILE" ]]; then
  COMPOSE_ENV_ARGS=(--env-file "$ENV_FILE")
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
BLOCKED=0

pass() {
  printf '[PASS] %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  local label="$1"
  local log_file="$2"
  printf '[FAIL] %s\n' "$label"
  if [[ -s "$log_file" ]]; then
    tail -n 25 "$log_file" | sed -E \
      's/(API_KEY|DASHBOARD_PASSWORD)=([^[:space:]]+)/\1=[REDACTED]/g'
  fi
  FAIL_COUNT=$((FAIL_COUNT + 1))
  BLOCKED=1
}

skip() {
  printf '[SKIP] %s\n' "$1"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

run_check() {
  local label="$1"
  shift
  local log_file
  log_file="$(mktemp)"
  printf '\n== %s ==\n' "$label"
  if "$@" >"$log_file" 2>&1; then
    pass "$label"
    grep -E '([0-9]+ passed|All tests passed|No issues found|issue(s)? found|BUILD SUCCESSFUL|Successfully built|^[[:space:]]*(info|warning|error) -)' \
      "$log_file" | tail -n 3 | sed -E \
      's/(API_KEY|DASHBOARD_PASSWORD)=([^[:space:]]+)/\1=[REDACTED]/g' || true
  else
    fail "$label" "$log_file"
  fi
  rm -f "$log_file"
}

run_flutter() {
  if [[ "$FLUTTER_MODE" == "container-exec" ]]; then
    docker compose "${COMPOSE_ENV_ARGS[@]}" exec -T --workdir /workspace/mobile \
      melodiscan-apk-builder flutter "$@"
  elif [[ "$FLUTTER_MODE" == "container-run" ]]; then
    docker compose "${COMPOSE_ENV_ARGS[@]}" run --build --rm --no-deps \
      --workdir /workspace/mobile --entrypoint flutter melodiscan-apk-builder "$@"
  elif [[ "$FLUTTER_MODE" == "host" ]]; then
    (
      cd mobile || exit 1
      "$FLUTTER_BIN" "$@"
    )
  fi
}

printf 'MelodiScan — validation complète\n'
printf 'Répertoire : %s\n' "$ROOT"
printf 'Aucun secret ne doit être copié dans le rapport.\n'

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  skip "Docker Compose indisponible : build image, tests backend conteneurisés et tests API omis."
  DOCKER_READY=0
elif ! docker info >/dev/null 2>&1; then
  skip "Daemon Docker arrêté/inaccessible : build image, tests backend conteneurisés et tests API omis."
  DOCKER_READY=0
else
  DOCKER_READY=1
fi

if command -v bash >/dev/null 2>&1; then
  run_check "syntaxe de l’installateur" bash -n install.sh
else
  skip "bash indisponible : syntaxe de install.sh non vérifiée."
fi

if [[ "$DOCKER_READY" -eq 1 ]]; then
  run_check "configuration Docker Compose" docker compose "${COMPOSE_ENV_ARGS[@]}" config --quiet
  PREVIOUS_FAIL_COUNT="$FAIL_COUNT"
  run_check "build backend + Audiveris + tests pytest" \
    docker compose "${COMPOSE_ENV_ARGS[@]}" --profile test run --build --rm melodiscan-test-runner
  [[ "$FAIL_COUNT" -eq "$PREVIOUS_FAIL_COUNT" ]] && BACKEND_TESTS_OK=1 || BACKEND_TESTS_OK=0
else
  BACKEND_TESTS_OK=0
  skip "Configuration Compose non validée sans daemon Docker."
  skip "Image Audiveris et suite pytest backend non validées sans daemon Docker."
  skip "Parcours HTTPS/API/Celery/Redis/OMR non validé sans daemon Docker."
  BLOCKED=1
fi

FLUTTER_BIN=""
FLUTTER_MODE=""
if [[ "$DOCKER_READY" -eq 1 ]]; then
  if docker compose "${COMPOSE_ENV_ARGS[@]}" ps --status running --services 2>/dev/null |
    grep -Fxq "melodiscan-apk-builder"; then
    FLUTTER_MODE="container-exec"
  else
    FLUTTER_MODE="container-run"
  fi
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
elif [[ -x "$HOME/.local/share/flutter/bin/flutter" ]]; then
  FLUTTER_BIN="$HOME/.local/share/flutter/bin/flutter"
fi
if [[ -n "$FLUTTER_BIN" && -z "$FLUTTER_MODE" ]]; then
  FLUTTER_MODE="host"
fi

if [[ -n "$FLUTTER_MODE" ]]; then
  run_check "dépendances Flutter verrouillées" run_flutter pub get --enforce-lockfile
  run_check "analyse statique Flutter" run_flutter analyze --no-pub --no-fatal-infos
  run_check "tests Flutter" run_flutter test --no-pub --reporter expanded
else
  skip "Flutter hôte absent et conteneur générateur arrêté : analyse/tests Flutter omis."
  BLOCKED=1
fi

if [[ "$DOCKER_READY" -eq 1 && "$BACKEND_TESTS_OK" -eq 1 ]]; then
  running_services="$(docker compose "${COMPOSE_ENV_ARGS[@]}" ps --status running --services 2>/dev/null || true)"
  required_services=(melodiscan-api melodiscan-worker melodiscan-redis melodiscan-https melodiscan-apk-builder)
  missing_services=()
  for service in "${required_services[@]}"; do
    if ! grep -Fxq "$service" <<<"$running_services"; then
      missing_services+=("$service")
    fi
  done
  if [[ "${#missing_services[@]}" -eq 0 ]]; then
    run_check "API, HTTPS, auth, génération et signature APK, distribution et worker OMR (E2E)" \
      python3 scripts/test-e2e.py
  else
    skip "Stack pas entièrement démarrée (${missing_services[*]}) : tests E2E non exécutés."
    BLOCKED=1
  fi
elif [[ "$DOCKER_READY" -eq 1 ]]; then
  skip "Tests E2E non exécutés car le build ou les tests backend ont échoué."
  BLOCKED=1
fi

printf '\n========== RÉSUMÉ À COPIER ==========\n'
printf 'PASS=%s  FAIL=%s  SKIP=%s\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
if [[ "$FAIL_COUNT" -eq 0 && "$BLOCKED" -eq 0 && "$SKIP_COUNT" -eq 0 ]]; then
  printf 'RÉSULTAT=COMPLET\n'
  exit 0
fi
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  printf 'RÉSULTAT=ÉCHEC — copiez ce rapport complet.\n'
  exit 1
fi
printf 'RÉSULTAT=INCOMPLET — prérequis ou services manquants; copiez ce rapport complet.\n'
exit 2
