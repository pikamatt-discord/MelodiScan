# 🎵 MelodiScan Enterprise & Self-Hosted Open-Source Ecosystem

<p align="center">
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="220" height="220">
    <defs>
      <!-- Dégradés -->
      <linearGradient id="purpleGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#9D4EDD" />
        <stop offset="100%" stop-color="#4A00E0" />
      </linearGradient>
      
      <linearGradient id="cyanGrad" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stop-color="#00F2FE" />
        <stop offset="100%" stop-color="#4FACFE" />
      </linearGradient>
    </defs>

    <!-- Arrière-plan style App Icon (Squircle) -->
    <rect width="512" height="512" rx="115" fill="#0D0E15" />

    <!-- Viseur de Scan Optique (Coins) -->
    <g stroke="url(#cyanGrad)" stroke-width="10" stroke-linecap="round" fill="none">
      <!-- Haut-Gauche -->
      <path d="M 116 176 L 116 136 Q 116 116 136 116 L 176 116" />
      <!-- Haut-Droite -->
      <path d="M 336 116 L 376 116 Q 396 116 396 136 L 396 176" />
      <!-- Bas-Gauche -->
      <path d="M 116 336 L 116 376 Q 116 396 136 396 L 176 396" />
      <!-- Bas-Droite -->
      <path d="M 336 396 L 376 396 Q 396 396 396 376 L 396 336" />
    </g>

    <!-- Onde Sonore / Égaliseur centré -->
    <g fill="url(#purpleGrad)">
      <rect x="160" y="226" width="18" height="60" rx="9" />
      <rect x="196" y="186" width="18" height="140" rx="9" />
      <rect x="232" y="156" width="18" height="200" rx="9" />
      <!-- Barre centrale -->
      <rect x="268" y="136" width="18" height="240" rx="9" fill="url(#cyanGrad)" />
      <rect x="304" y="176" width="18" height="160" rx="9" />
      <rect x="340" y="206" width="18" height="100" rx="9" />
    </g>
  </svg>
</p>

**MelodiScan** est un écosystème logiciel open-source, auto-hébergeable et décentralisé conçu pour numériser, analyser et synthétiser des partitions musicales physiques ou numériques en flux interactifs audio et visuels.

Dépôt Officiel GitHub : **`https://github.com/pikamatt-discord/MelodiScan`**

---

## ⚡ Installation & Déploiement 1-Commande (Serveur Ubuntu)

Pour installer et démarrer l'ensemble du serveur domestique (Docker Compose + Dashboard local + compilation/hébergement de l'APK), exécutez la commande suivante :

```bash
curl -sSL https://raw.githubusercontent.com/pikamatt-discord/MelodiScan/main/install.sh | bash
```

Ou en clonant le dépôt :

```bash
git clone https://github.com/pikamatt-discord/MelodiScan.git
cd MelodiScan
chmod +x install.sh
./install.sh
```

Le script s'occupe de tout :
1. Installation de Docker et Docker Compose.
2. Clonnage / Mise à jour du dépôt GitHub.
3. Compilation du paquet Android Release APK (`mobile/build/app/outputs/flutter-apk/app-release.apk`).
4. Lancement des conteneurs Docker (`melodiscan-api`, `melodiscan-worker`, `melodiscan-redis`).

Accédez ensuite au **Dashboard Web d'Administration Local** :
👉 **`http://localhost:8080/dashboard`**

---

## 🔄 Procédure de Mise à Jour du Serveur et de l'Application

Pour mettre à jour le système vers la dernière version du dépôt officiel :

```bash
# Relancer simplement le script d'installation auto-update
./install.sh

# Ou manuellement via Docker :
git pull origin main
docker compose up -d --build
```

---

## 📱 Guide de Compilation de l'APK & Tests sur Émulateur Android

### 1. Compilation du Paquet APK Release
Pour compiler l'application Flutter localement :

```bash
cd mobile
flutter pub get
flutter build apk --release
```

Le fichier compilé est généré dans `mobile/build/app/outputs/flutter-apk/app-release.apk` (taille ~48 Mo).

Le serveur MelodiScan héberge également ce fichier en téléchargement direct à l'adresse :
👉 **`http://localhost:8080/download/app-release.apk`**

### 2. Configuration & Lancement de l'Émulateur Android (AVD)
Pour tester l'application sur un émulateur Android :

```bash
# Lister les émulateurs disponibles sur votre machine
flutter emulators

# Démarrer un émulateur spécifique
flutter emulators --launch <emulator_id>
```

### 3. Installation et Exécution de l'APK via ADB
Une fois l'émulateur démarré :

```bash
# Lister les appareils et émulateurs connectés
adb devices

# Installer l'APK généré sur l'émulateur
adb install -r mobile/build/app/outputs/flutter-apk/app-release.apk

# Ou lancer l'application en mode debug/interactif
cd mobile
flutter run
```

---

## 🚀 Architecture Logicielle & Spécifications Techniques

```
┌─────────────────────────────────────────────────────────┐
│              SIGHT / CAPTURE (CLIENT)                   │
│                                                         │
│  [ Flutter Mobile Application ]                         │
│   ├── Edge OpenCV Processing (Binarization Sauvola)    │
│   ├── Client SoundFont Synthesizer (FluidSynth Engine)  │
│   └── Interactive Canvas Viewport (Tempo, Transposition)│
└──────────────────────────┬──────────────────────────────┘
                           │
             Protocoles :  │ HTTP/2 / Multipart (Data)
                           │ SSE (Server-Sent Events)
                           ▼
┌─────────────────────────────────────────────────────────┐
│             CORE PROCESSING (HOME SERVER)               │
│                                                         │
│  [ Docker Container - MelodiScan Engine ]               │
│   ├── API Gateway (FastAPI + AsyncIO + Pydantic v2)    │
│   ├── Task Queue (Celery / Redis)                       │
│   ├── OMR Pipeline Layer                                │
│   │    ├── Primary: Audiveris CLI Engine (Headless JVM) │
│   │    └── Fallback: HOMR Deep Learning Pipeline        │
│   ├── Structural Music Engine (Partitura Pipeline)      │
│   └── Dashboard Web & Serveur d'APK Mobile              │
└─────────────────────────────────────────────────────────┘
```

---

### Spécification des Routes API REST & Stream SSE

| Méthode | Route | Description |
| :--- | :--- | :--- |
| `GET` | `/health` | Vérification de santé du serveur API |
| `GET` | `/dashboard` | Dashboard Web interactif d'administration du serveur |
| `GET` | `/download/app-release.apk` | Téléchargement direct du paquet Android APK |
| `POST` | `/api/v1/scan` | Téléversement de l'image de partition + métadonnées |
| `GET` | `/api/v1/stream/{task_id}` | Flux SSE (`text/event-stream`) diffusant la progression OMR |
| `GET` | `/api/v1/result/{task_id}` | Téléchargement de la partition synthétisée en fichier MIDI (`.mid`) |

---

### Commandes de Test & Vérification

#### Tests Backend (pytest) :
```bash
/app/venv/bin/python3 -m pytest backend/tests/test_main.py
```

#### Tests Frontend Mobile (flutter test) :
```bash
cd mobile
flutter test
```
