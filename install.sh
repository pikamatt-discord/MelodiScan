#!/usr/bin/env bash
set -e

echo "======================================================="
echo " 🎵 MelodiScan Enterprise - Serveur Domestique Auto-Installer"
echo "======================================================="

REPO_URL="https://github.com/pikamatt-discord/MelodiScan.git"

# 1. Verification/Installation de Docker & Docker Compose
if ! command -v docker &> /dev/null; then
    echo "[1/5] Installation de Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# 2. Clonnage / Mise à jour du dépôt
if [ ! -d ".git" ]; then
    echo "[2/5] Clonnage du dépôt officiel ($REPO_URL)..."
    git clone $REPO_URL melodiscan_temp
    mv melodiscan_temp/* . 2>/dev/null || true
    rm -rf melodiscan_temp
else
    echo "[2/5] Mise à jour du dépôt local (git pull)..."
    git pull origin main 2>/dev/null || git pull || true
fi

# 3. Preparation des répertoires de stockage
echo "[3/5] Initialisation des volumes et données..."
mkdir -p data/temp data/apk

# 4. Compilation de l'APK Android Flutter si Flutter est présent
echo "[4/5] Compilation du paquet Android APK..."
if command -v flutter &> /dev/null; then
    (cd mobile && flutter build apk --release)
    if [ -f "mobile/build/app/outputs/flutter-apk/app-release.apk" ]; then
        cp mobile/build/app/outputs/flutter-apk/app-release.apk data/apk/app-release.apk
    fi
fi

# 5. Déploiement des conteneurs Docker Compose
echo "[5/5] Démarrage des services MelodiScan Docker Compose..."
docker compose up -d --build

echo "======================================================="
echo " 🎉 Installation & Mise à jour terminées avec succès !"
echo " 🌐 Dashboard Local : http://localhost:8080/dashboard"
echo " 📱 Téléchargement APK : http://localhost:8080/download/app-release.apk"
echo "======================================================="
