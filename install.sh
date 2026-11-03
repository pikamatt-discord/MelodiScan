#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY_URL="https://github.com/pikamatt-discord/MelodiScan.git"
DEFAULT_REPOSITORY="$HOME/MelodiScan"
CURRENT_STEP="initialisation"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_ACCENT=$'\033[38;5;141m'
  COLOR_SUCCESS=$'\033[38;5;114m'
  COLOR_INFO=$'\033[38;5;110m'
  COLOR_WARNING=$'\033[38;5;221m'
  COLOR_ERROR=$'\033[38;5;203m'
  COLOR_MUTED=$'\033[38;5;245m'
else
  COLOR_RESET=""
  COLOR_ACCENT=""
  COLOR_SUCCESS=""
  COLOR_INFO=""
  COLOR_WARNING=""
  COLOR_ERROR=""
  COLOR_MUTED=""
fi

section() {
  CURRENT_STEP="$*"
  printf '\n%b%s%b\n' "$COLOR_ACCENT" "  ━━ $* ━━" "$COLOR_RESET"
}

success() {
  printf '  %b✓%b %s\n' "$COLOR_SUCCESS" "$COLOR_RESET" "$*"
}

info() {
  printf '  %b›%b %s\n' "$COLOR_INFO" "$COLOR_RESET" "$*"
}

warning() {
  printf '  %b!%b %s\n' "$COLOR_WARNING" "$COLOR_RESET" "$*"
}

fail() {
  printf '  %b✕ Erreur :%b %s\n' "$COLOR_ERROR" "$COLOR_RESET" "$*" >&2
  exit 1
}

on_error() {
  local status=$?
  printf '  %b✕ Installation interrompue%b · étape « %s », ligne %s.\n' \
    "$COLOR_ERROR" "$COLOR_RESET" "$CURRENT_STEP" "$1" >&2
  exit "$status"
}
trap 'on_error "$LINENO"' ERR

printf '%b' "$COLOR_ACCENT"
cat <<'BANNER'
  ♫  MELODISCAN
     Installation du serveur
BANNER
printf '%b' "$COLOR_RESET"
printf '  %bConfiguration sécurisée · Déploiement HTTPS · Application Android%b\n' \
  "$COLOR_MUTED" "$COLOR_RESET"

resolve_repository() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  elif [[ -f "$DEFAULT_REPOSITORY/docker-compose.yml" ]]; then
    printf '%s\n' "$DEFAULT_REPOSITORY"
  else
    return 1
  fi
}

ACTION="install"
if [[ -r /dev/tty && -w /dev/tty ]]; then
  printf '\n  Que souhaitez-vous faire ?\n' >/dev/tty
  printf '  %b1%b  Installation complète / redéploiement\n' "$COLOR_ACCENT" "$COLOR_RESET" >/dev/tty
  printf '  %b2%b  Voir l’état des services\n' "$COLOR_ACCENT" "$COLOR_RESET" >/dev/tty
  printf '  %b3%b  Démarrer les services\n' "$COLOR_ACCENT" "$COLOR_RESET" >/dev/tty
  printf '  %b4%b  Arrêter les services\n' "$COLOR_ACCENT" "$COLOR_RESET" >/dev/tty
  printf '  %b5%b  Redémarrer les services\n' "$COLOR_ACCENT" "$COLOR_RESET" >/dev/tty
  printf '  %b6%b  Consulter les logs en direct\n' "$COLOR_ACCENT" "$COLOR_RESET" >/dev/tty
  printf '  %bq%b  Quitter\n\n' "$COLOR_ACCENT" "$COLOR_RESET" >/dev/tty

  while true; do
    printf '  Votre choix [1] : ' >/dev/tty
    menu_choice=""
    IFS= read -r menu_choice </dev/tty || true
    menu_choice="${menu_choice:-1}"
    case "$menu_choice" in
      1) ACTION="install"; break ;;
      2) ACTION="status"; break ;;
      3) ACTION="start"; break ;;
      4) ACTION="stop"; break ;;
      5) ACTION="restart"; break ;;
      6) ACTION="logs"; break ;;
      q|Q) printf '  À bientôt.\n' >/dev/tty; exit 0 ;;
      *) warning "Choix invalide. Saisissez un nombre de 1 à 6 ou q." ;;
    esac
  done
fi

if [[ "$ACTION" != "install" ]]; then
  REPOSITORY_ROOT="$(resolve_repository)" ||
    fail "Dépôt introuvable. Placez-vous dans MelodiScan ou installez-le d’abord avec l’option 1."
  cd "$REPOSITORY_ROOT"
  command -v docker >/dev/null 2>&1 || fail "Docker est introuvable. Lancez d’abord l’installation complète."
  SUDO=()
  DOCKER=(docker)
  if ! docker info >/dev/null 2>&1; then
    if [[ "${EUID}" -ne 0 ]] && sudo docker info >/dev/null 2>&1; then
      SUDO=(sudo)
      DOCKER=("${SUDO[@]}" docker)
    else
      fail "Docker ne répond pas. Vérifiez que le service Docker est démarré."
    fi
  fi
  docker compose version >/dev/null 2>&1 ||
    "${DOCKER[@]}" compose version >/dev/null 2>&1 ||
    fail "Docker Compose v2 est introuvable. Lancez d’abord l’installation complète."
  compose() {
    "${DOCKER[@]}" compose "$@"
  }

  case "$ACTION" in
    status)
      section "État des services"
      compose ps
      ;;
    start)
      section "Démarrage des services"
      compose up -d
      success "Services démarrés"
      ;;
    stop)
      section "Arrêt des services"
      compose stop
      success "Services arrêtés. Les données sont conservées."
      ;;
    restart)
      section "Redémarrage des services"
      compose restart
      success "Services redémarrés"
      ;;
    logs)
      section "Logs en direct · Ctrl+C pour quitter"
      compose logs --tail=100 --follow || {
        status=$?
        [[ "$status" -eq 130 ]] || exit "$status"
      }
      ;;
  esac
  exit 0
fi

section "1 / 5 · Vérification de l’environnement"
for command in curl git openssl python3; do
  command -v "$command" >/dev/null 2>&1 || {
    if command -v apt-get >/dev/null 2>&1; then
      info "Installation des prérequis système…"
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

if REPOSITORY_ROOT="$(resolve_repository)"; then
  :
else
  info "Téléchargement de MelodiScan dans $DEFAULT_REPOSITORY…"
  git clone "$REPOSITORY_URL" "$DEFAULT_REPOSITORY"
  REPOSITORY_ROOT="$DEFAULT_REPOSITORY"
fi

cd "$REPOSITORY_ROOT"
[[ -f docker-compose.yml ]] || fail "docker-compose.yml est introuvable dans $REPOSITORY_ROOT."
success "Dépôt prêt : $REPOSITORY_ROOT"

section "2 / 5 · Installation et démarrage de Docker"
SUDO=()
if [[ "${EUID}" -ne 0 ]]; then SUDO=(sudo); fi

if ! command -v docker >/dev/null 2>&1; then
  command -v apt-get >/dev/null 2>&1 || fail "Docker est absent et apt-get n'est pas disponible."
  info "Installation du moteur Docker et de Compose v2…"
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
  info "Activation du service Docker au démarrage…"
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
success "Docker et Compose sont opérationnels"

compose() {
  "${DOCKER[@]}" compose "$@"
}

command -v ip >/dev/null 2>&1 || "${SUDO[@]}" apt-get install -y iproute2
section "3 / 5 · Réseau et configuration sécurisée"
LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(("192.0.2.1",80)); print(s.getsockname()[0]); s.close()')"
fi
[[ "$LAN_IP" != 127.* ]] || fail "Impossible de détecter une adresse IPv4 du réseau local."
success "Adresse du serveur détectée : $LAN_IP"

mkdir -p data/temp data/apk data/firebase
chmod 700 data/firebase
if [[ ! -e data/firebase/google-services.json ]]; then
  touch data/firebase/google-services.json
fi
chmod 600 data/firebase/google-services.json
if [[ -f data/firebase/service-account.json ]]; then
  chmod 600 data/firebase/service-account.json
fi
if [[ -s data/firebase/google-services.json && -s data/firebase/service-account.json ]]; then
  success "Configuration des notifications Firebase détectée"
else
  info "Notifications facultatives : placez google-services.json et service-account.json dans data/firebase/ puis relancez install.sh."
fi
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
DASHBOARD_SESSION_SECRET="$(get_env DASHBOARD_SESSION_SECRET)"
[[ -n "$DASHBOARD_SESSION_SECRET" ]] || DASHBOARD_SESSION_SECRET="$(openssl rand -hex 32)"
DASHBOARD_PASSWORD="$(get_env DASHBOARD_PASSWORD)"
[[ -n "$DASHBOARD_PASSWORD" ]] || DASHBOARD_PASSWORD="$(openssl rand -hex 16)"
DASHBOARD_USERNAME="$(get_env DASHBOARD_USERNAME)"
[[ -n "$DASHBOARD_USERNAME" ]] || DASHBOARD_USERNAME=admin
[[ "$DASHBOARD_USERNAME" =~ ^[A-Za-z0-9._-]+$ ]] ||
  fail "DASHBOARD_USERNAME doit contenir uniquement lettres, chiffres, point, tiret ou souligné."
set_env API_KEY "$API_KEY"
set_env DASHBOARD_SESSION_SECRET "$DASHBOARD_SESSION_SECRET"
set_env DASHBOARD_USERNAME "$DASHBOARD_USERNAME"
set_env DASHBOARD_PASSWORD "$DASHBOARD_PASSWORD"
set_env MELODISCAN_HOST "$LAN_IP"
MELODISCAN_VERSION="$(git rev-parse --short=12 HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
  MELODISCAN_VERSION="${MELODISCAN_VERSION}+local"
fi
set_env MELODISCAN_VERSION "$MELODISCAN_VERSION"

GEMINI_API_KEY="${GEMINI_API_KEY:-$(get_env GEMINI_API_KEY)}"
if [[ -r /dev/tty && -w /dev/tty ]]; then
  if [[ -n "$GEMINI_API_KEY" ]]; then
    printf '  Une clé Gemini existe. Nouvelle clé, Entrée pour conserver ou - pour désactiver : ' >/dev/tty
  else
    printf '  Clé API Gemini pour la détection des titres (facultatif, Entrée pour ignorer) : ' >/dev/tty
  fi
  IFS= read -r -s GEMINI_API_KEY_INPUT </dev/tty || true
  printf '\n' >/dev/tty
  if [[ "${GEMINI_API_KEY_INPUT:-}" == "-" ]]; then
    GEMINI_API_KEY=""
  elif [[ -n "${GEMINI_API_KEY_INPUT:-}" ]]; then
    GEMINI_API_KEY="$GEMINI_API_KEY_INPUT"
  fi
  unset GEMINI_API_KEY_INPUT
fi
set_env GEMINI_API_KEY "$GEMINI_API_KEY"
chmod 600 .env

mkdir -p data/android-config
chmod 700 data/android-config
if [[ ! -s data/android-config/debug.keystore ]]; then
  if "${DOCKER[@]}" cp melodiscan_apk_builder:/root/.android/debug.keystore \
    data/android-config/debug.keystore >/dev/null 2>&1; then
    chmod 600 data/android-config/debug.keystore
    success "Clé de signature APK existante conservée pour les prochaines mises à jour"
  else
    info "Aucune clé APK précédente : une clé sera conservée pour les prochaines compilations"
  fi
fi

section "4 / 5 · Déploiement des services"
info "Construction et démarrage des services sur https://$LAN_IP…"
compose up -d --build

info "Attente du certificat HTTPS local de Caddy…"
ca_ready=false
for attempt in $(seq 1 30); do
  if "${DOCKER[@]}" cp melodiscan_https:/data/caddy/pki/authorities/local/root.crt \
    data/caddy-root.crt >/dev/null 2>&1 && [[ -s data/caddy-root.crt ]]; then
    ca_ready=true
    break
  fi
  if (( attempt % 10 == 0 )); then
    info "Caddy initialise son certificat (${attempt}/30 s)…"
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
success "Certificat HTTPS récupéré"
info "Redémarrage de Caddy et du générateur avec le certificat…"
compose up -d --force-recreate melodiscan-https melodiscan-apk-builder
success "Services HTTPS rechargés"
info "Vérification de l’API, de Redis, du worker, d’Oemer et du générateur APK…"

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
required=("redis","celery_worker","oemer","apk_builder")
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
    info "Démarrage en cours ($((attempt * 2))/120 s) · HTTP $health_status · $health_summary"
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

success "Tous les services répondent sur HTTPS"
fingerprint_response="$(curl --cacert data/caddy-root.crt --silent --show-error \
  --connect-timeout 5 --write-out $'\n%{http_code}' \
  -H "X-API-Key: ${API_KEY}" "${BASE_URL}/api/v1/apk/fingerprint")" ||
  fail "Impossible de vérifier si l’APK existant correspond à cette version de l’application."
fingerprint_http_status="${fingerprint_response##*$'\n'}"
fingerprint_body="${fingerprint_response%$'\n'*}"
[[ "$fingerprint_http_status" == 200 ]] ||
  fail "Impossible de calculer l’empreinte de l’APK (HTTP ${fingerprint_http_status})."

section "5 / 5 · Préparation de l’application Android"
if printf '%s' "$fingerprint_body" | python3 -c '
import json,sys
data=json.load(sys.stdin)
apk=data.get("apk", {})
fingerprint=data.get("input_fingerprint")
sys.exit(0 if fingerprint and apk.get("available") is True
         and apk.get("signature_verified") is True
         and apk.get("input_fingerprint") == fingerprint else 1)
'; then
  success "APK déjà à jour · sources et configuration inchangées"
else
  info "Génération de l’APK Android Release…"
  info "La première compilation après une modification peut prendre plusieurs minutes."
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
      info "$build_progress · $((attempt * 2)) s écoulées"
    fi
    sleep 2
  done
  [[ "$apk_ready" == true ]] || fail "La génération de l’APK n’a pas abouti en 60 minutes."
fi
[[ -s data/apk/app-release.apk ]] ||
  fail "L’APK est déclaré disponible, mais data/apk/app-release.apk est absent."

success "APK Android Release disponible"

section "Installation terminée"
printf '  Tableau de bord   %s/dashboard\n' "$BASE_URL"
printf '  API vérifiée      %s  %bHTTP 200%b\n' "$BASE_URL" "$COLOR_SUCCESS" "$COLOR_RESET"
printf '  Identifiant       %s\n' "$DASHBOARD_USERNAME"
printf '  Mot de passe      %s\n' "$DASHBOARD_PASSWORD"
if [[ -n "$GEMINI_API_KEY" ]]; then
  printf '  Détection du titre Gemini configurée sur le worker\n'
else
  printf '  Détection du titre Gemini désactivée\n'
fi
printf '  Application       %s/download/app-release.apk\n' "$BASE_URL"
printf '  Fichier APK       %s/data/apk/app-release.apk\n' "$REPOSITORY_ROOT"
printf '\n  %bL’application est préconfigurée. Aucun DNS ni certificat à installer sur le téléphone.%b\n' \
  "$COLOR_MUTED" "$COLOR_RESET"
warning "Conservez vos identifiants en lieu sûr et ne partagez pas cette sortie."
