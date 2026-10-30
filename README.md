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

**MelodiScan** est un prototype open-source et auto-hébergeable qui envoie une image de partition à un serveur OMR, suit le traitement et récupère un résultat MIDI quand la reconnaissance et la conversion aboutissent. Il ne simule pas de résultat lorsque le traitement échoue.

Dépôt Officiel GitHub : **`https://github.com/pikamatt-discord/MelodiScan`**

---

## 📊 Récapitulatif du Projet & État d'Avancement (Project Status)

### 📌 1. Bilan de ce qui a été Réalisé (Implemented Features)

| Composant | Statut | Fonctionnalités Déployées |
| :--- | :--- | :--- |
| **API Backend (FastAPI)** | Prototype | Envoi d’une image par tâche, suivi SSE, téléchargement MIDI uniquement après succès, statistiques et état de santé des dépendances. |
| **Moteur OMR** | Intégré à l’image | Audiveris 5.10.0 est installé dans l’image Docker du backend/worker. Toute erreur OMR ou de conversion marque la tâche en échec ; aucun moteur de secours ni partition synthétique. |
| **Dashboard serveur** | Opérationnel | Statistiques de numérisation, état API/Redis/worker/Audiveris/générateur APK, historique filtrable, téléchargement MIDI et génération réelle d’un APK Release à la demande. |
| **Client mobile (Flutter)** | Prototype | Capture ou sélection d’une image unique, envoi au serveur, suivi SSE et vérification/récupération du fichier MIDI. La lecture audio intégrée, le multi-pages et le prétraitement d’image ne sont pas implémentés. |
| **Déploiement Docker** | Prototype | `docker-compose.yml` démarre l’API, le worker Celery, Redis et Caddy HTTPS ; l’image backend inclut Audiveris. |
| **Tests automatisés** | En cours | Tests ciblés backend et Flutter ; exécuter les commandes de test ci-dessous dans des environnements munis de leurs dépendances. |

---

### 🛑 2. Ce qu'il Manque Avant le Passage en Production (Pre-Production Roadmap)

Pour transformer l'environnement actuel de développement/démonstration en une infrastructure de production industrielle à grande échelle, les éléments suivants doivent être complétés :

#### A. Sécurité & Authentification (Security Layer)
1. **Configuration de l’authentification :** Les endpoints API acceptent une clé `API_KEY` et le dashboard un identifiant/mot de passe configurables. Ils restent désactivés sans ces variables pour le développement local ; ils doivent être activés avant toute exposition réseau. L’intégration JWT reste à évaluer si des comptes multi-utilisateurs deviennent nécessaires.
2. **Certificat public pour un accès Internet :** Le déploiement fourni utilise Caddy et une CA locale ; un déploiement public devra utiliser un domaine et un certificat reconnu publiquement, par exemple via Let's Encrypt.

#### B. Moteur OMR & Traitement Avancé (OMR Production Integration)
1. **Amélioration du traitement Audiveris :** Ajouter une validation de qualité et une correction manuelle des partitions reconnues. MelodiScan ne bascule pas sur un autre moteur si Audiveris échoue.
2. **Correction Manuelle sur l'Application Mobile :** Ajouter un éditeur interactif permettant à l'utilisateur d'ajuster ou corriger manuellement les notes/mesures mal reconnues sur la partition avant l'exportation finale.

#### C. Performance & Scalabilité (Infrastructure Scaling)
1. **Optimisation Mémoire de la JVM Headless :** Configurer les limites Xmx/Xms du JVM Java pour libérer automatiquement la RAM de la JVM (< 512 Mo au repos) après inactivité.
2. **Gestionnaire de Cache Redis Persistant :** Monter un volume persistant Redis (`appendonly yes`) pour conserver l'historique complet des partitions numérisées au redémarrage du serveur.

#### D. Audio Engine Native Native Binding (SoundFont FFI Engine)
1. **Compilation FFI `libfluidsynth` C++ :** Compiler les bindings natifs FFI C++ de `libfluidsynth` pour Android / iOS afin de jouer directement des banques SoundFont `.sf2` haute fidélité sur le terminal mobile sans passer par le synthétiseur système.

---

## ⚡ Installation & Déploiement 1-Commande (Serveur Ubuntu)

Sur un serveur Ubuntu x86_64 connecté au réseau local, exécutez cette commande depuis n’importe quel terminal :

```bash
curl -sSL https://raw.githubusercontent.com/pikamatt-discord/MelodiScan/main/install.sh | bash
```

Elle clone le dépôt dans `~/MelodiScan` si nécessaire. Pour installer depuis une copie déjà clonée :

```bash
git clone https://github.com/pikamatt-discord/MelodiScan.git
cd MelodiScan
chmod +x install.sh
./install.sh
```

Le script automatise les étapes suivantes :
1. Installe Docker/Compose si nécessaire, puis construit l’image backend avec Audiveris 5.10.0 et l’image Flutter/Android de génération d’APK ; démarre l’API, le worker, Redis, le générateur et Caddy.
2. Détecte l’adresse IPv4 du serveur sur le réseau local et configure HTTPS pour cette adresse, sans réglage DNS.
3. Génère et conserve une clé API et les identifiants du dashboard dans `.env` (permissions privées).
4. Récupère la CA publique Caddy et redémarre le proxy et le générateur pour qu’ils utilisent la configuration et le certificat locaux. Interroge ensuite **l’URL HTTPS exacte du serveur** sur `/health`, valide le certificat avec cette CA et exige HTTP 200 ainsi que Redis, le worker, Audiveris et le générateur opérationnels.
5. Demande au générateur Flutter/Android conteneurisé de compiler un véritable APK Release avec l’adresse vérifiée, la clé API et la CA ; vérifie le paquet et le publie dans `data/apk/app-release.apk`.

À la fin, le script affiche l’URL du dashboard et l’URL API copiables, les identifiants et le chemin de l’APK. Il confirme explicitement que `GET https://<IP-du-serveur>/health` a répondu HTTP 200 avec les dépendances requises en ligne. L’URL API intégrée à l’APK est cette adresse réseau vérifiée, jamais `localhost`. Le téléphone doit être sur le même réseau ; installez l’APK fourni, sans configurer de DNS ni installer de certificat sur le téléphone. La clé API est intégrée à cet APK : elle convient à un usage personnel/familial sur réseau local, mais ne constitue pas une authentification individuelle forte.

Caddy utilise une autorité de certification locale conservée dans son volume Docker. Le certificat racine public est installé dans le magasin de confiance du serveur Linux pour que son navigateur puisse ouvrir le dashboard sans avertissement. Un navigateur sur un autre ordinateur/téléphone peut encore demander d’approuver cette CA ; l’application mobile compilée par le script lui fait déjà confiance. Une réservation DHCP est recommandée afin que l’adresse locale du serveur reste stable.

Le dashboard `/dashboard` permet de consulter les volumes de scans, taux de réussite, échecs, tâches en cours, durée moyenne, services actifs et historique filtrable. Son bouton **Générer l’APK** lance une vraie compilation Flutter Android sur le serveur, avec l’adresse HTTPS, la clé API et la CA du déploiement. La progression et les erreurs sont affichées ; l’APK n’est proposé au téléchargement qu’une fois disponible et validé. Après un changement d’adresse du serveur, relancez `./install.sh` pour mettre à jour la configuration intégrée dans l’APK.

Le script est destiné à Ubuntu x86_64 et nécessite Internet, Docker, `sudo` lorsque nécessaire et une adresse IPv4 accessible sur le réseau local. Le générateur télécharge une image Flutter/Android volumineuse au premier démarrage ; il n’installe plus le SDK Android sur l’hôte. La version Flutter 3.44.0 est fixée pour obtenir des builds reproductibles. Il s’arrête avec une erreur explicite si le contrôle `/health` ou la compilation échoue, et ne fabrique pas d’APK de remplacement. Le certificat racine public est copié dans `data/caddy-root.crt`; la clé privée de l’autorité reste dans le volume Docker `caddy_data` et ne doit pas être partagée ou supprimée.

### Validation complète avant de partager l’installation

Après l’installation, depuis le dossier `MelodiScan`, lancez une seule commande :

```bash
bash test-complet.sh
```

Le rapport vérifie la configuration et le build Docker/Audiveris, lance les tests pytest du backend dans un conteneur isolé, puis exécute l’analyse et les tests Flutter dans le générateur Android conteneurisé. Si les services sont démarrés, il vérifie HTTPS avec la CA et le résultat complet de `/health`, l’authentification et les endpoints ; il déclenche ensuite une vraie compilation APK via le même endpoint que le dashboard, vérifie le ZIP, le manifeste et la signature Android, puis contrôle le téléchargement. Il envoie aussi volontairement une image PNG invalide pour vérifier la propagation de l’échec OMR sans faux MIDI. Ce test peut prendre plusieurs minutes selon le cache Gradle. La tâche de scan d’essai est retirée de l’historique Redis. Le script ne démarre ni n’arrête les services. Copiez toute la sortie affichée ; elle n’inclut pas les secrets du fichier `.env`.

Le script n’évalue pas la qualité de reconnaissance d’une partition valide : le dépôt ne fournit pas de partition de test de référence. Ce contrôle nécessite un vrai scan de partition et une sortie MIDI attendue à comparer.

L’API sur le port 8080 reste accessible uniquement depuis la machine hôte pour le développement ; les appareils du réseau passent par HTTPS sur le port 443. Sans Redis, worker, Audiveris ou générateur APK, `/health` retourne `503` avec le détail des dépendances. Audiveris 5.10.0 est installé pendant la construction de l’image backend ; aucune autre solution n’est utilisée en cas d’échec.

Hors installateur, les endpoints `/api/*` et `/download/*` acceptent une clé `API_KEY`; le dashboard peut être protégé avec `DASHBOARD_USERNAME` et `DASHBOARD_PASSWORD`. Sans configuration, l’authentification est désactivée pour le développement local ; n’exposez pas ce mode sur Internet. Le client Flutter de développement utilise `http://10.0.2.2:8080` par défaut. Pour une compilation personnalisée, définissez `MELODISCAN_API_URL`, `MELODISCAN_API_KEY` et `MELODISCAN_ROOT_CA_BASE64` avec `--dart-define`.

L’endpoint `POST /api/v1/scan` accepte une seule image PNG, JPEG ou WebP, jusqu’à 20 Mio par défaut. Chaque image doit être envoyée dans une tâche séparée.

---

## 🔄 Procédure de Mise à Jour du Serveur et de l'Application

Pour mettre à jour le système vers la dernière version du dépôt officiel :

```bash
git pull origin main
./install.sh
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

Si l’APK a été compilé et copié dans `data/apk/app-release.apk`, le serveur le propose aussi à l'adresse :
👉 **`https://<adresse-ip-du-serveur>/download/app-release.apk`**

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
│   ├── Capture ou sélection d’une image                  │
│   └── Envoi HTTP / suivi SSE / résultat MIDI           │
└──────────────────────────┬──────────────────────────────┘
                           │
             Protocoles :  │ HTTP Multipart (Data)
                           │ SSE (Server-Sent Events)
                           ▼
┌─────────────────────────────────────────────────────────┐
│             CORE PROCESSING (HOME SERVER)               │
│                                                         │
│  [ Docker Container - MelodiScan Engine ]               │
│   ├── API Gateway (FastAPI + AsyncIO + Pydantic v2)    │
│   ├── Task Queue (Celery / Redis)                       │
│   ├── OMR : Audiveris CLI (seul moteur, inclus dans l’image)│
│   ├── Conversion : Partitura vers MIDI                  │
│   └── Dashboard Web & APK (si artefact présent)          │
└─────────────────────────────────────────────────────────┘
                           ▲
                           │ HTTPS, CA locale approuvée
                    ┌──────┴──────┐
                    │ Caddy proxy │
                    └─────────────┘
```

---

### Commandes de Test & Vérification

#### Tests Backend (pytest) :
```bash
python -m pytest backend/tests/test_main.py
```

#### Tests Frontend Mobile (flutter test) :
```bash
cd mobile
flutter test
```
