#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY_URL="https://github.com/pikamatt-discord/MelodiScan.git"
DEFAULT_REPOSITORY="$HOME/MelodiScan"
ANDROID_COMMAND_LINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"

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

mkdir -p data
touch .env
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

printf 'Démarrage des services MelodiScan sur https://%s ...\n' "$LAN_IP"
compose up -d --build

ready=false
for attempt in $(seq 1 60); do
  health_response="$(curl --insecure --silent --show-error --connect-timeout 2 \
    "https://${LAN_IP}/health" 2>/dev/null || true)"
  if [[ -n "$health_response" ]] &&
    printf '%s' "$health_response" |
      python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("status") == "ok" else 1)' 2>/dev/null; then
    ready=true
    break
  fi
  sleep 2
done
[[ "$ready" == true ]] || fail "L’API, Redis, le worker ou Audiveris n’est pas opérationnel après 120 secondes. Consultez : docker compose logs"

"${DOCKER[@]}" cp melodiscan_https:/data/caddy/pki/authorities/local/root.crt data/caddy-root.crt
[[ -s data/caddy-root.crt ]] || fail "Le certificat racine Caddy n'a pas été généré."

if command -v update-ca-certificates >/dev/null 2>&1; then
  "${SUDO[@]}" install -m 0644 data/caddy-root.crt /usr/local/share/ca-certificates/melodiscan-caddy.crt
  "${SUDO[@]}" update-ca-certificates
fi

if ! command -v flutter >/dev/null 2>&1; then
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y git curl unzip xz-utils zip libglu1-mesa openjdk-17-jdk
  FLUTTER_ROOT="$HOME/.local/share/flutter"
  if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
    mkdir -p "$(dirname "$FLUTTER_ROOT")"
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
  fi
  export PATH="$FLUTTER_ROOT/bin:$PATH"
fi

if ! command -v java >/dev/null 2>&1; then
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y openjdk-17-jdk
fi

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$SDKMANAGER" ]]; then
  "${SUDO[@]}" apt-get install -y unzip
  SDK_TEMP="$(mktemp -d)"
  curl -fsSL "$ANDROID_COMMAND_LINE_TOOLS_URL" -o "$SDK_TEMP/android-tools.zip"
  mkdir -p "$SDK_TEMP/extracted" "$ANDROID_SDK_ROOT/cmdline-tools"
  unzip -q "$SDK_TEMP/android-tools.zip" -d "$SDK_TEMP/extracted"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  cp -a "$SDK_TEMP/extracted/cmdline-tools/." "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
  rm -rf "$SDK_TEMP"
fi

export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
FLUTTER_ROOT="$(cd "$(dirname "$(readlink -f "$(command -v flutter)")")/.." && pwd)"
FLUTTER_GRADLE_EXTENSION="$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
[[ -f "$FLUTTER_GRADLE_EXTENSION" ]] ||
  fail "Impossible de déterminer les prérequis Android depuis le SDK Flutter : $FLUTTER_GRADLE_EXTENSION"
COMPILE_SDK="$(sed -n 's/.*val compileSdkVersion: Int = \([0-9][0-9]*\).*/\1/p' "$FLUTTER_GRADLE_EXTENSION" | head -n 1)"
NDK_VERSION="$(sed -n 's/.*val ndkVersion: String = "\([^"]*\)".*/\1/p' "$FLUTTER_GRADLE_EXTENSION" | head -n 1)"
[[ -n "$COMPILE_SDK" && -n "$NDK_VERSION" ]] ||
  fail "Impossible d’extraire les versions Android requises par Flutter."
set +o pipefail
yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null
set -o pipefail
"$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" \
  "platform-tools" "platforms;android-${COMPILE_SDK}" \
  "build-tools;${COMPILE_SDK}.0.0" "ndk;${NDK_VERSION}"

flutter config --android-sdk "$ANDROID_SDK_ROOT"
flutter config --no-analytics
CA_BASE64="$(base64 -w 0 data/caddy-root.crt)"
(
  cd mobile
  flutter pub get
  flutter build apk --release \
    --dart-define="MELODISCAN_API_URL=https://${LAN_IP}" \
    --dart-define="MELODISCAN_API_KEY=${API_KEY}" \
    --dart-define="MELODISCAN_ROOT_CA_BASE64=${CA_BASE64}"
)

APK_SOURCE="mobile/build/app/outputs/flutter-apk/app-release.apk"
[[ -s "$APK_SOURCE" ]] || fail "La compilation s'est terminée sans produire l'APK attendu."
mkdir -p data/apk
install -m 0644 "$APK_SOURCE" data/apk/app-release.apk

printf '\nInstallation terminée.\n'
printf 'Adresse MelodiScan : https://%s\n' "$LAN_IP"
printf 'URL API préconfigurée dans l’APK : https://%s\n' "$LAN_IP"
printf 'Identifiant dashboard : %s\n' "$DASHBOARD_USERNAME"
printf 'Mot de passe dashboard : %s\n' "$DASHBOARD_PASSWORD"
printf 'APK Android : %s/data/apk/app-release.apk\n' "$REPOSITORY_ROOT"
printf 'Téléchargement APK : https://%s/download/app-release.apk\n' "$LAN_IP"
printf 'L’application mobile est préconfigurée ; aucun DNS ni certificat à installer sur le téléphone.\n'
