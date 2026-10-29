# 🎵 MelodiScan Enterprise & Self-Hosted Open-Source Ecosystem

<p align="center">
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="220" height="220">
    <defs>
      <linearGradient id="purpleGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#9D4EDD" />
        <stop offset="100%" stop-color="#4A00E0" />
      </linearGradient>
      <linearGradient id="cyanGrad" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stop-color="#00F2FE" />
        <stop offset="100%" stop-color="#4FACFE" />
      </linearGradient>
    </defs>
    <rect width="512" height="512" rx="115" fill="#0D0E15" />
    <g stroke="url(#cyanGrad)" stroke-width="10" stroke-linecap="round" fill="none">
      <path d="M 116 176 L 116 136 Q 116 116 136 116 L 176 116" />
      <path d="M 336 116 L 376 116 Q 396 116 396 136 L 396 176" />
      <path d="M 116 336 L 116 376 Q 116 396 136 396 L 176 396" />
      <path d="M 336 396 L 376 396 Q 396 396 396 376 L 396 336" />
    </g>
    <g fill="url(#purpleGrad)">
      <rect x="160" y="226" width="18" height="60" rx="9" />
      <rect x="196" y="186" width="18" height="140" rx="9" />
      <rect x="232" y="156" width="18" height="200" rx="9" />
      <rect x="268" y="136" width="18" height="240" rx="9" fill="url(#cyanGrad)" />
      <rect x="304" y="176" width="18" height="160" rx="9" />
      <rect x="340" y="206" width="18" height="100" rx="9" />
    </g>
  </svg>
</p>

**MelodiScan** est un écosystème logiciel open-source, auto-hébergeable et décentralisé conçu pour numériser, analyser et synthétiser des partitions musicales physiques ou numériques en flux interactifs audio et visuels.

---

## ⚡ Installation Ultra-Simple sur Serveur Ubuntu (1-Command Install)

Pour installer et démarrer l'ensemble du serveur domestique (Docker Compose + Dashboard local + génération d'APK), exécutez simplement :

```bash
curl -sSL https://raw.githubusercontent.com/melodiscan/melodiscan/main/install.sh | bash
```

Ou en clonant le dépôt :

```bash
git clone https://github.com/melodiscan/melodiscan.git
cd melodiscan
chmod +x install.sh
./install.sh
```

Le script installe automatiquement Docker, configure les conteneurs et lance le serveur. Accédez ensuite au **Dashboard Web local** à l'adresse :
👉 **`http://localhost:8080/dashboard`**

---

## 📱 Guide de Génération de l'APK & Tests sur Émulateur Android

### 1. Génération de l'APK Release
Pour compiler le paquet Android APK de l'application Flutter :

```bash
cd mobile
flutter build apk --release
```
Le fichier généré se situe dans `mobile/build/app/outputs/flutter-apk/app-release.apk`.

Sur le serveur, ce fichier est également disponible au téléchargement direct via :
`http://localhost:8080/download/app-release.apk`

### 2. Configuration et Lancement de l'Émulateur Android
Pour tester l'application sur un émulateur Android (AVD) :

```bash
# Lister les émulateurs disponibles
flutter emulators

# Démarrer un émulateur spécifique
flutter emulators --launch <emulator_id>
```

### 3. Installation et Exécution de l'APK sur l'Émulateur (ADB)
Une fois l'émulateur Android démarré :

```bash
# Vérifier les appareils/émulateurs connectés
adb devices

# Installer l'APK sur l'émulateur
adb install -r mobile/build/app/outputs/flutter-apk/app-release.apk

# Exécuter l'application en mode développement/debug interactif
cd mobile
flutter run -d emulator-5554
```

---

## 🚀 Architecture Logicielle & Spécifications Techniques

### 📚 Table des Matières

1. [Vision du Projet & Topologie Système](#1-vision-du-projet--topologie-système)
2. [Back-End Engine (FastAPI & OMR Failover)](#2-back-end-engine-fastapi--omr-failover)
3. [Spécification des API REST & SSE Stream](#3-spécification-des-api-rest--sse-stream)
4. [Front-End Client Mobile (Flutter cross-platform)](#4-front-end-client-mobile-flutter)
5. [Conteneurisation & Déploiement Docker Compose](#5-conteneurisation--déploiement-docker-compose)
6. [Commandes de Test & Vérification](#6-commandes-de-test--vérification)

---

### 1. Vision du Projet & Topologie Système

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
│   └── Dashboard & Local APK Download Server            │
└─────────────────────────────────────────────────────────┘
```

---

### 2. Back-End Engine (FastAPI & OMR Failover)

Le backend Python est situé dans le répertoire `backend/` :
* **FastAPI + Uvicorn :** Gateway REST pour la réception des fichiers, la diffusion d'événements SSE et l'affichage du Dashboard HTML local.
* **Celery & Redis :** Traitement de tâches OMR en arrière-plan avec état synchronisé.
* **Moteur OMR à Tolérance aux Pannes (Failover) :**
  1. **Audiveris CLI (Primary) :** Exécution headless en Java 17 pour la reconnaissance des portées et des notes, produisant un fichier `.musicxml`.
  2. **HOMR Engine (Fallback) :** Bascule automatique si le score de confiance d'Audiveris est $< 70\%$.
* **Partitura Pipeline :** Validation syntaxique et conversion du fichier MusicXML vers un fichier MIDI (`.mid`) optimisé.

---

### 3. Spécification des API REST & SSE Stream

| Méthode | Route | Description |
| :--- | :--- | :--- |
| `GET` | `/health` | Statut de santé de l'API. |
| `GET` | `/dashboard` | Dashboard Web HTML local d'administration du serveur. |
| `GET` | `/download/app-release.apk` | Téléchargement du paquet APK Android. |
| `POST` | `/api/v1/scan` | Téléversement de l'image (PNG 1-bit/Couleur) + titre. Retourne un `task_id`. |
| `GET` | `/api/v1/stream/{task_id}` | Stream SSE (`text/event-stream`) diffusant la progression en temps réel. |
| `GET` | `/api/v1/result/{task_id}` | Téléchargement du fichier MIDI résultant (`.mid`). |

---

### 4. Front-End Client Mobile (Flutter)

L'application Flutter est située dans `mobile/` et offre une expérience moderne en **Theme Sombre (Dark Theme)** avec 3 écrans principaux :

1. **`ScanScreen` (`mobile/lib/screens/scan_screen.dart`) :**
   * Prétraitement d'image Edge (Binarisation de Sauvola, correction de perspective 2D).
   * Envoi `http.MultipartRequest` vers l'API Gateway `/api/v1/scan`.
2. **`StatusScreen` (`mobile/lib/screens/status_screen.dart`) :**
   * Suivi du flux SSE en temps réel avec barre de progression et timeline visuelle des étapes du serveur.
3. **`PlayerScreen` (`mobile/lib/screens/player_screen.dart`) :**
   * Canvas interactif style Verovio.
   * Time-stretching sans altération de pitch ($0.25x \to 2.0x$).
   * Pitch-shifting (Transposition par demi-tons de $-12$ à $+12$).
   * Bouclage A/B sur mesures spécifiques.
   * Gestion multi-pistes/instruments (SoundFont2).

---

### 5. Conteneurisation & Déploiement Docker Compose

Le déploiement s'effectue via le fichier root `docker-compose.yml` :

```bash
docker compose up -d
```

Services conteneurisés :
* `melodiscan-api` : Gateway FastAPI + Dashboard sur le port `8080`.
* `melodiscan-worker` : Worker Celery pour le traitement OMR & Partitura.
* `melodiscan-redis` : Courtier Redis 7-alpine.

---

### 6. Commandes de Test & Vérification

#### Backend (Python / FastAPI / pytest) :
```bash
/app/venv/bin/python3 -m pytest backend/tests/test_main.py
```

#### Mobile (Flutter / Dart) :
```bash
cd mobile
flutter test
```
