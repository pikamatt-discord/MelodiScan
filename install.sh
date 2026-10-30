#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY_URL="https://github.com/pikamatt-discord/MelodiScan.git"
DEFAULT_REPOSITORY="$HOME/MelodiScan"

fail() {
  printf 'Erreur : %s\n' "$*" >&2
  exit 1
}

for command in curl git openssl python3; do
  command -v "$command" >/dev/null 2>&1 || {
    if command -v apt-get >/dev/null 2>&1; then
      SUDO=()
      if [[ "${EUID}" -ne 0 ]]; then SUDO=(sudo); fi
      "${SUDO[@]}" apt-get update
      "${SUDO[@]}" apt-get install -y ca-certificates curl git openssl python3
    else
      fail "La commande $command est requise."
    fi
    break
  }
done

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
elif [[ -d "$DEFAULT_REPOSITORY/.git" ]]; then
  REPOSITORY_ROOT="$DEFAULT_REPOSITORY"
else
  git clone "$REPOSITORY_URL" "$DEFAULT_REPOSITORY"
  REPOSITORY_ROOT="$DEFAULT_REPOSITORY"
fi

cd "$REPOSITORY_ROOT"
[[ -f docker-compose.yml ]] || fail "docker-compose.yml est introuvable dans $REPOSITORY_ROOT."

SUDO=()
if [[ "${EUID}" -ne 0 ]]; then SUDO=(sudo); fi

if ! command -v docker >/dev/null 2>&1; then
  command -v apt-get >/dev/null 2>&1 || fail "Docker est absent et apt-get n'est pas disponible."
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y ca-certificates curl
  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
    "${SUDO[@]}" tee /etc/apt/keyrings/docker.asc >/dev/null
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  [[ "${ID:-}" == ubuntu || "${ID_LIKE:-}" == *ubuntu* ]] ||
    fail "L'installation automatique de Docker est prévue pour Ubuntu."
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
    "$(dpkg --print-architecture)" "${UBUNTU_CODENAME:-$VERSION_CODENAME}" |
    "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
if ! docker compose version >/dev/null 2>&1; then
  "${SUDO[@]}" apt-get install -y docker-compose-plugin ||
    fail "Docker Compose v2 est introuvable. Installez le plugin Docker Compose puis relancez."
fi

if command -v systemctl >/dev/null 2>&1; then
  "${SUDO[@]}" systemctl enable --now docker ||
    fail "Impossible d'activer et démarrer Docker avec systemd."
else
  fail "systemctl est requis pour activer le démarrage automatique de Docker sur Ubuntu."
fi

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif "${SUDO[@]}" docker info >/dev/null 2>&1; then
  DOCKER=("${SUDO[@]}" docker)
else
  fail "Docker ne répond pas. Vérifiez que le service Docker est démarré."
fi

compose() {
  "${DOCKER[@]}" compose "$@"
}

command -v ip >/dev/null 2>&1 || "${SUDO[@]}" apt-get install -y iproute2
LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(("192.0.2.1",80)); print(s.getsockname()[0]); s.close()')"
fi
[[ "$LAN_IP" != 127.* ]] || fail "Impossible de détecter une adresse IPv4 du réseau local."

mkdir -p data/temp data/apk
touch .env
touch data/caddy-root.crt
chmod 600 .env

get_env() {
  local value
  value="$(sed -n "s/^$1=//p" .env | tail -n 1)"
  printf '%s' "$value"
}

set_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >>.env
  fi
}

API_KEY="$(get_env API_KEY)"
[[ -n "$API_KEY" ]] || API_KEY="$(openssl rand -hex 32)"
DASHBOARD_PASSWORD="$(get_env DASHBOARD_PASSWORD)"
[[ -n "$DASHBOARD_PASSWORD" ]] || DASHBOARD_PASSWORD="$(openssl rand -hex 16)"
DASHBOARD_USERNAME="$(get_env DASHBOARD_USERNAME)"
[[ -n "$DASHBOARD_USERNAME" ]] || DASHBOARD_USERNAME=admin
[[ "$DASHBOARD_USERNAME" =~ ^[A-Za-z0-9._-]+$ ]] ||
  fail "DASHBOARD_USERNAME doit contenir uniquement lettres, chiffres, point, tiret ou souligné."
set_env API_KEY "$API_KEY"
set_env DASHBOARD_USERNAME "$DASHBOARD_USERNAME"
set_env DASHBOARD_PASSWORD "$DASHBOARD_PASSWORD"
set_env MELODISCAN_HOST "$LAN_IP"

mkdir -p data/android-config
chmod 700 data/android-config
if [[ ! -s data/android-config/debug.keystore ]]; then
  if "${DOCKER[@]}" cp melodiscan_apk_builder:/root/.android/debug.keystore \
    data/android-config/debug.keystore >/dev/null 2>&1; then
    chmod 600 data/android-config/debug.keystore
    printf 'Clé de signature APK existante conservée pour permettre les mises à jour de l’application.\n'
  else
    printf 'Aucune clé APK précédente détectée; la clé de signature sera conservée pour les prochaines compilations.\n'
  fi
fi

printf 'Démarrage des services MelodiScan sur https://%s ...\n' "$LAN_IP"
compose up -d --build

printf 'Attente du certificat HTTPS local de Caddy...\n'
ca_ready=false
for attempt in $(seq 1 30); do
  if "${DOCKER[@]}" cp melodiscan_https:/data/caddy/pki/authorities/local/root.crt \
    data/caddy-root.crt >/dev/null 2>&1 && [[ -s data/caddy-root.crt ]]; then
    ca_ready=true
    break
  fi
  if (( attempt % 10 == 0 )); then
    printf 'Caddy initialise encore son certificat (%s/30 s)...\n' "$attempt"
  fi
  sleep 1
done
if [[ "$ca_ready" != true ]]; then
  printf 'État des conteneurs :\n' >&2
  compose ps >&2 || true
  printf 'Derniers logs Caddy :\n' >&2
  compose logs --tail=40 melodiscan-https >&2 || true
  fail "Le certificat racine Caddy n'a pas été généré après 30 secondes."
fi
printf 'Certificat HTTPS récupéré. Rechargement de Caddy et du générateur avec la CA...\n'
compose up -d --force-recreate melodiscan-https melodiscan-apk-builder
printf 'Caddy et le générateur redémarrés. Vérification des services...\n'

BASE_URL="https://${LAN_IP}"
HEALTH_URL="${BASE_URL}/health"
ready=false
health_status="aucune réponse"
health_body=""
for attempt in $(seq 1 60); do
  health_response="$(curl --cacert data/caddy-root.crt --silent --show-error \
    --connect-timeout 2 --write-out $'\n%{http_code}' "$HEALTH_URL" 2>/dev/null || true)"
  health_status="${health_response##*$'\n'}"
  health_body="${health_response%$'\n'*}"
  if [[ "$health_status" == 200 ]] &&
    printf '%s' "$health_body" |
      python3 -c '
import json,sys
data=json.load(sys.stdin)
required=("redis","celery_worker","audiveris","apk_builder")
sys.exit(0 if data.get("status") == "ok" and all(data.get("dependencies",{}).get(k) is True for k in required) else 1)
' 2>/dev/null; then
    ready=true
    break
  fi
  if (( attempt % 5 == 0 )); then
    health_summary="$(printf '%s' "$health_body" | python3 -c '
import json,sys
try:
 data=json.load(sys.stdin)
 print(", ".join(f"{name}={state}" for name,state in data.get("dependencies",{}).items()) or "état des dépendances indisponible")
except (json.JSONDecodeError, AttributeError):
 print("réponse HTTPS ou JSON indisponible")
' 2>/dev/null || printf 'réponse HTTPS ou JSON indisponible')"
    printf 'En attente de /health (%s/120 s) : HTTP %s; %s\n' \
      "$((attempt * 2))" "$health_status" "$health_summary"
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  health_summary="$(printf '%s' "$health_body" | python3 -c '
import json,sys
try:
 data=json.load(sys.stdin)
 print(", ".join(f"{name}={state}" for name,state in data.get("dependencies",{}).items()) or "état des dépendances indisponible")
except (json.JSONDecodeError, AttributeError):
 print("réponse HTTPS ou JSON indisponible")
' 2>/dev/null || printf 'réponse HTTPS ou JSON indisponible')"
  printf 'Dernier contrôle : HTTP %s; %s\n' "$health_status" "$health_summary" >&2
  printf 'État des conteneurs :\n' >&2
  compose ps >&2 || true
  printf 'Derniers logs des services concernés :\n' >&2
  compose logs --tail=40 melodiscan-https melodiscan-api melodiscan-worker melodiscan-apk-builder >&2 || true
  fail "Le contrôle réel de ${HEALTH_URL} (HTTPS avec la CA Caddy, HTTP 200 et tous les services) a échoué."
fi

if command -v update-ca-certificates >/dev/null 2>&1; then
  "${SUDO[@]}" install -m 0644 data/caddy-root.crt /usr/local/share/ca-certificates/melodiscan-caddy.crt
  "${SUDO[@]}" update-ca-certificates
fi

printf 'URL HTTPS vérifiée : %s (GET /health : HTTP 200, Redis/worker/Audiveris/générateur APK opérationnels)\n' "$BASE_URL"
printf 'Génération de l’APK Android Release dans le conteneur Flutter (le premier build peut prendre plusieurs minutes)...\n'
build_response="$(curl --cacert data/caddy-root.crt --silent --show-error \
  --connect-timeout 5 --write-out $'\n%{http_code}' \
  -X POST -H "X-API-Key: ${API_KEY}" "${BASE_URL}/api/v1/apk/build")" ||
  fail "Impossible de démarrer la génération de l’APK via ${BASE_URL}."
build_http_status="${build_response##*$'\n'}"
build_body="${build_response%$'\n'*}"
if [[ "$build_http_status" != 202 && "$build_http_status" != 409 ]]; then
  fail "Le générateur d’APK a refusé la demande (HTTP ${build_http_status})."
fi
BUILD_ID="$(printf '%s' "$build_body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("build_id",""))')"
[[ "$BUILD_ID" =~ ^[0-9a-fA-F-]{36}$ ]] ||
  fail "Le générateur n’a pas retourné un identifiant de build valide."

apk_ready=false
for attempt in $(seq 1 1800); do
  build_response="$(curl --cacert data/caddy-root.crt --silent --show-error \
    --connect-timeout 5 --write-out $'\n%{http_code}' \
    -H "X-API-Key: ${API_KEY}" "${BASE_URL}/api/v1/apk/build/${BUILD_ID}" 2>/dev/null || true)"
  build_http_status="${build_response##*$'\n'}"
  build_body="${build_response%$'\n'*}"
  build_status="$(printf '%s' "$build_body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)"
  if [[ "$build_http_status" != 200 ]]; then
    fail "Impossible de vérifier le build APK via ${BASE_URL} (HTTP ${build_http_status})."
  fi
  if [[ "$build_status" == completed ]]; then
    apk_ready=true
    break
  elif [[ "$build_status" == failed ]]; then
    build_error="$(printf '%s' "$build_body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error","erreur inconnue"))' 2>/dev/null || true)"
    fail "La génération de l’APK a échoué : ${build_error}"
  fi
  if (( attempt % 15 == 0 )); then
    build_progress="$(printf '%s' "$build_body" | python3 -c \
      'import json,sys; print(json.load(sys.stdin).get("progress","Compilation toujours en cours"))' \
      2>/dev/null || printf 'Compilation toujours en cours')"
    printf '%s (%.0f s)...\n' "$build_progress" "$((attempt * 2))"
  fi
  sleep 2
done
[[ "$apk_ready" == true ]] || fail "La génération de l’APK n’a pas abouti en 60 minutes."
[[ -s data/apk/app-release.apk ]] ||
  fail "Le build est déclaré terminé, mais data/apk/app-release.apk est absent."

printf '\nInstallation terminée.\n'
printf 'Dashboard : %s/dashboard\n' "$BASE_URL"
printf 'URL API préconfigurée et vérifiée : %s (GET %s/health = HTTP 200)\n' "$BASE_URL" "$BASE_URL"
printf 'Identifiant dashboard : %s\n' "$DASHBOARD_USERNAME"
printf 'Mot de passe dashboard : %s\n' "$DASHBOARD_PASSWORD"
printf 'APK Android : %s/data/apk/app-release.apk\n' "$REPOSITORY_ROOT"
printf 'Téléchargement APK : %s/download/app-release.apk\n' "$BASE_URL"
printf 'L’application mobile est préconfigurée ; aucun DNS ni certificat à installer sur le téléphone.\n'
