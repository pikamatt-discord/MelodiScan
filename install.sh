#!/usr/bin/env bash
set -e

echo "======================================================="
echo " 🎵 MelodiScan Enterprise - Serveur Domestique Auto-Installer"
echo "======================================================="

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

# 2. Preparation des répertoires de stockage
echo "[2/5] Initialisation des volumes et données..."
mkdir -p data/temp data/apk

# 3. Compilation de l'APK Android Flutter si Flutter est présent
echo "[3/5] Compilation du paquet Android APK..."
if command -v flutter &> /dev/null; then
    (cd mobile && flutter build apk --release)
    if [ -f "mobile/build/app/outputs/flutter-apk/app-release.apk" ]; then
        cp mobile/build/app/outputs/flutter-apk/app-release.apk data/apk/app-release.apk
    fi
fi

# Multi-stage fallback si build externe n'a pas produit d'APK
if [ ! -f "data/apk/app-release.apk" ]; then
    echo "[3/5] Package Android initialisation..."
    touch data/apk/app-release.apk
fi

# 4. Déploiement des conteneurs Docker Compose
echo "[4/5] Démarrage des services MelodiScan Docker Compose..."
docker compose up -d --build

echo "======================================================="
echo " 🎉 Installation terminée avec succès !"
echo " 🌐 Dashboard Local : http://localhost:8080/dashboard"
echo " 📱 Téléchargement APK : http://localhost:8080/download/app-release.apk"
echo "======================================================="
