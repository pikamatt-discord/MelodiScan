# 🎵 Spécifications Techniques & Cahier des Charges
## **MelodiScan Enterprise & Self-Hosted Open-Source Ecosystem**

---

## 1. Vision du Projet & Architecture Globale

### 1.1 Objectif
**MelodiScan** est un écosystème logiciel open-source, auto-hébergeable et décentralisé, conçu pour numériser, analyser et synthétiser des partitions musicales physiques ou numériques en flux interactifs audio et visuels. 

Le système s'articule autour d'une architecture **Edge-Server / Client Mobile**, optimisée pour le traitement local sur des infrastructures domestiques (Raspberry Pi 4/5, Home Lab, serveur local Ubuntu, NAS Docker) avec une latence réseau nulle et une confidentialité totale des données.

### 1.2 Topologie Système

```
┌─────────────────────────────────────────────────────────┐
│              SIGHT / CAPTURE (CLIENT)                   │
│                                                         │
│  [ Flutter Mobile Application ]                         │
│   ├── Edge OpenCV Processing (Binarization & Perspective)│
│   ├── Client SoundFont Synthesizer (FluidSynth Engine)  │
│   └── Interactive Canvas Viewport (Tempo, Transposition)│
└──────────────────────────┬──────────────────────────────┘
                           │
             Protocoles :  │ HTTP/2 / gRPC (Data)
                           │ SSE (Server-Sent Events)
                           ▼
┌─────────────────────────────────────────────────────────┐
│             CORE PROCESSING (HOME SERVER)               │
│                                                         │
│  [ Docker Container - MelodiScan Engine ]               │
│   ├── API Gateway (FastAPI + AsyncIO + Pydantic v2)    │
│   ├── Task Queue (Celery / Redis / RabbitMQ)            │
│   ├── OMR Pipeline Layer                                │
│   │    ├── Primary: Audiveris CLI Engine (Headless JVM) │
│   │    └── Fallback: Homr Deep Learning Pipeline        │
│   ├── Structural Music Engine (Partitura Pipeline)      │
│   └── Cache Layer (Redis / Vector Metadata)             │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Spécifications du Client Mobile (Front-End)

### 2.1 Stack Technique Client
* **Framework :** Flutter (Dart) cross-platform (Android / iOS).
* **Traitement d'image Edge :** `edge_detection` + bindings natifs OpenCV C++ (`flutter_vision`).
* **Synthétiseur Audio :** Audio engine natif C++ compilé via FFI (`libfluidsynth` / `c звуковой synth` custom) lisant des banques `.sf2` (SoundFont2) compressées.
* **Gestion d'état :** Riverpod / Bloc.

### 2.2 Prétraitement d'Image sur le Terminal (Edge-OCR/OMR Pre-flight)
Pour décharger le serveur et garantir un taux d'erreur minimum d'OMR :
1. **Détection Automatique de Contours :** Algorithme de Hough Transform et détection de quadrilatère pour isoler la feuille de musique du fond.
2. **Correction de Perspective (Warp Perspective) :** Rectification géométrique 2D automatique avec grille visuelle ajustable par l'utilisateur.
3. **Binarisation Adaptative Localisée :** Thresholding de Sauvola/Otsu pour supprimer les ombres directes et maximiser le contraste encre/papier.
4. **Compression Lossless :** Conversion en format PNG 1-bit monochrome pour réduire l'empreinte réseau à < 500 Ko par page.

### 2.3 Moteur Interactif Client (Player & Inspector)
* **Visualisation Dynamique :** Rendu vectoriel du morceau (Piano Roll et affichage dynamique de la partition via `verovio` ou Canvas custom).
* **Contrôles Audio Temps Réel :**
  * Time-Stretching sans altération de pitch ($0.25x \to 2.0x$).
  * Pitch-Shifting (Transposition temps réel par demi-tons).
  * Mute / Solo de pistes (si multi-voix reconnue).
  * Bouclage A/B sur des mesures spécifiques pour la répétition d'instruments (Flûte, Xylophone, Saxophone).

---

## 3. Spécifications du Serveur Domestique (Back-End)

### 3.1 Conteneurisation & Compatibilité Hardware
Le serveur doit pouvoir tourner sous forme de conteneurs **Docker Orchestrés (Docker Compose / Kubernetes)** supportant deux architectures cibles :
* `linux/amd64` (Serveurs Ubuntu, NAS Synology/Unraid, PC réutilisés).
* `linux/arm64` (Raspberry Pi 4/5, Apple Silicon SBCs).

### 3.2 Framework API & Traitement Asynchrone
* **API Core :** FastAPI (Python 3.11+) s'appuyant sur Uvicorn/Gunicorn.
* **Gestion des Tâches Asynchrones :** Celery adossé à un courtier Redis. Les fichiers volumineux ou les analyses multi-pages sont traitées en arrière-plan sans bloquer les requêtes réseau.
* **Streaming d'État (Server-Sent Events) :** Publication en temps réel des événements de traitement :
  * `STATUS_PROCESSING_IMAGE`
  * `STATUS_RUNNING_OMR`
  * `STATUS_BUILDING_MUSICXML`
  * `STATUS_EXPORTING_MIDI`
  * `STATUS_COMPLETED`

### 3.3 Moteur de Reconnaissance Optique (OMR Pipeline)
Le serveur implémente un système d'OMR tolérant aux pannes (*Failover Architecture*) :
1. **Moteur Principal (Audiveris Headless) :**
   * Exécution d'Audiveris v5.3+ dans un environnement Java 17 headless isolé.
   * Extraction des symboles complexes, portées, altérations, armatures et métriques.
   * Génération d'un fichier intermédiaire `.musicxml`.
2. **Moteur Secondaire de Secours (`homr` Engine) :**
   * Si le score de confiance d'Audiveris est $< 70\%$, basculement automatique sur le pipeline de Deep Learning `homr`.
3. **Optimisation d'Empreinte Mémoire :** Gestion dynamique du cycle de vie du JVM pour libérer la RAM ($< 512$ Mo au repos) lorsque aucune requête n'est active.

### 3.4 Pipeline de Traitement Musical (`partitura` Core)
Le fichier `.musicxml` généré est injecté dans le module Python `partitura` pour :
* La validation syntaxique de la structure musicale.
* La correction automatique des incohérences de durée de mesure (ex: notes manquantes sur la métrique).
* L'exportation en fichier MIDI `.mid` optimisé avec gestion précise des messages `Note-On`, `Note-Off`, et des événements `Set Tempo`.

---

## 4. Flux de Données & Protocole de Communication

```
[ App Mobile ]                      [ FastAPI / Redis ]                 [ Audiveris / Partitura ]
      │                                     │                                     │
      ├──── 1. POST /api/v1/scan ──────────►│                                     │
      │    (PNG binarisé + métadonnées)    ├──── 2. Push Tâche dans Redis ───────►│
      │                                     │                                     │
      ├──── 3. SSE /api/v1/stream/{id} ────►│                                     │
      │ ◄── 4. Event: RUNNING_OMR ─────────┤                                     │
      │                                     │                                     ├─ 5. OMR & XML Process
      │                                     │ ◄── 6. Conversion Partitura ────────┤
      │ ◄── 7. Event: COMPLETED ────────────┤                                     │
      │                                     │                                     │
      ├──── 8. GET /api/v1/result/{id} ────►│                                     │
      │ ◄── 9. Fichier MIDI (.mid) ─────────┤                                     │
```

---

## 5. Exigences Non-Fonctionnelles & Performance

| Critère | Cible / Spécification |
| :--- | :--- |
| **Temps de traitement global** | $< 8$ secondes sur AMD64 / $< 18$ secondes sur Raspberry Pi 4. |
| **Poids de l'image transmise** | $< 500$ Ko grâce à la binarisation locale. |
| **Disponibilité Serveur** | Auto-healing Docker (redémarrage automatique en cas de crash JVM). |
| **Sécurité & Confidentialité** | 100% Hors-ligne / Aucune télémétrie externe / Authentification via API Key locale. |
| **Consommation Mémoire Client** | $< 120$ Mo RAM sur Android durant la restitution SoundFont. |

---

## 6. Architecture de Déploiement Open-Source (Docker Compose)

Un fichier `docker-compose.yml` standardisé est fourni aux utilisateurs de la communauté pour un déploiement en une commande :

```yaml
version: '3.8'

services:
  melodiscan-api:
    image: melodiscan/core-engine:latest
    container_name: melodiscan_api
    restart: always
    ports:
      - "8080:8080"
    environment:
      - REDIS_URL=redis://melodiscan-redis:6379/0
      - OMR_ENGINE_PRIMARY=audiveris
      - OMR_ENGINE_FALLBACK=homr
    volumes:
      - ./data/temp:/app/temp
    depends_on:
      - melodiscan-redis

  melodiscan-worker:
    image: melodiscan/core-engine:latest
    container_name: melodiscan_worker
    command: celery -A app.tasks worker --loglevel=info
    restart: always
    environment:
      - REDIS_URL=redis://melodiscan-redis:6379/0
    volumes:
      - ./data/temp:/app/temp
    depends_on:
      - melodiscan-redis

  melodiscan-redis:
    image: redis:7-alpine
    container_name: melodiscan_redis
    restart: always
```

---

## 7. Roadmap de Développement

* **Phase 1 (MVP Industrialisé) :** Pipeline Flutter (avec OpenCV Edge) + FastAPI + Audiveris CLI + Partitura.
* **Phase 2 (Scalabilité) :** Intégration de Celery/Redis, streaming SSE et support Docker multi-arch (ARM/AMD).
* **Phase 3 (Fonctionnalités Avancées) :** Polyphonie simplifiée (portées multiples), édition corrective manuelle sur l'application mobile et synchronisation multi-appareils locaux.