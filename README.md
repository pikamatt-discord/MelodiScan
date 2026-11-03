# MelodiScan

MelodiScan convertit des photos et des PDF de partitions en fichiers MusicXML et MIDI. La reconnaissance s’exécute sur un serveur auto-hébergé ; l’application Android affiche la partition et permet de l’écouter.

Le projet utilise Flutter, FastAPI, Celery, Redis, Oemer, music21 et Verovio. Le traitement continue côté serveur si l’application est fermée. Les notifications de fin d’analyse sont facultatives.

> Projet en développement : la reconnaissance dépend du document et peut échouer. Aucun résultat de remplacement n’est créé.

## Installation

Déploiement automatisé pour **Ubuntu x86_64** sur un réseau local :

```bash
git clone https://github.com/pikamatt-discord/MelodiScan.git
cd MelodiScan
chmod +x install.sh
./install.sh
```

Le script configure Docker, déploie les services, vérifie l’API et génère l’APK. Il affiche les adresses et identifiants à conserver. Une réservation DHCP est recommandée pour stabiliser l’adresse du serveur.

Le dashboard affiche la version déployée sous forme d’identifiant Git court. Le suffixe `+local` indique que l’installation a été construite avec des modifications locales non enregistrées dans Git.

- Dashboard : `https://<adresse-ip>/dashboard`
- Documentation API : `https://<adresse-ip>/docs`
- État de santé : `https://<adresse-ip>/health`

L’APK se télécharge depuis le dashboard après authentification. Le déploiement utilise le certificat local Caddy et est prévu pour un réseau de confiance, pas pour une exposition directe sur Internet. La clé API intégrée à l’APK ne fournit pas une authentification individuelle.

## Notifications Android (facultatif)

Pour recevoir une notification lorsque l’application est en arrière-plan :

1. Dans la [console Firebase](https://console.firebase.google.com/), créez un projet, activez **Firebase Cloud Messaging** et ajoutez une application Android avec l’identifiant `com.melodiscan.melodiscan_mobile`. Téléchargez son `google-services.json`.
2. Dans **Paramètres du projet → Comptes de service → Firebase Admin SDK**, cliquez sur **Générer une nouvelle clé privée** et confirmez. Un fichier JSON est téléchargé : renommez-le `service-account.json`. Si l’envoi FCM est refusé pour permissions insuffisantes, dans la console Google Cloud du même projet, accordez au compte de service le rôle **Firebase Cloud Messaging Admin**.
3. Depuis le dossier `MelodiScan`, ouvrez [`data/firebase/`](data/firebase/) et déposez-y les deux fichiers : `google-services.json` et `service-account.json`.
4. Relancez `./install.sh`.

Le fichier téléchargé contient une clé privée : ne le partagez pas, ne l’envoyez pas par courriel et ne l’ajoutez jamais à Git. Seul le worker y accède ; le générateur APK reçoit uniquement `google-services.json`. Sans ces deux fichiers, le scan fonctionne mais aucune notification push n’est envoyée.

## Traitement des partitions

Formats acceptés : PNG, JPEG, WebP et PDF, jusqu’à **20 Mio** par défaut. Les PDF sont rasterisés à 300 DPI. Oemer dispose d’un maximum d’**une heure par page** ; c’est une limite, pas une estimation. La durée réelle dépend du document et du serveur.

Les résultats réussis (source, MusicXML et MIDI) sont conservés dans `data/library`. Sauvegardez ce dossier. Les échecs sont signalés dans l’application et les diagnostics ; aucun MIDI fictif n’est produit.

## Configuration

L’installateur crée `.env` et génère les identifiants. Variables principales :

| Variable | Description |
| --- | --- |
| `API_KEY` | Protection des endpoints API et téléchargements. |
| `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD` | Connexion au dashboard ; à définir ensemble. |
| `DASHBOARD_SESSION_SECRET` | Signature des sessions du dashboard. |
| `MELODISCAN_HOST` | Adresse du serveur utilisée par HTTPS et l’APK. |
| `MAX_UPLOAD_BYTES` | Taille maximale des fichiers (20 Mio par défaut). |
| `GEMINI_API_KEY` | Extraction facultative du titre imprimé. |

Gemini traite le document d’origine pour proposer un titre. Sa clé reste dans `.env` et n’est pas intégrée à l’application. Sans Gemini, le titre saisi ou un titre générique est utilisé.

Ne publiez jamais `.env`, `data/firebase/service-account.json`, les clés de signature Android ni les fichiers privés de Caddy.

## Mise à jour

```bash
git pull origin main
./install.sh
```

L’APK est recompilé si ses sources ou sa configuration ont changé. La clé de signature est conservée dans `data/android-config` pour permettre les mises à jour de l’application installée.

## Développement et tests

Tests backend :

```bash
backend/.venv/bin/python -m pytest backend/tests -q
```

Tests et compilation Flutter :

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

La suite de validation du déploiement s’exécute depuis la racine :

```bash
bash test-complet.sh
```

## Architecture

```text
Application Flutter ── HTTPS / SSE ── Caddy ── FastAPI ── Redis / Celery
                                                        └── Worker Oemer / music21
                                                             ├── Bibliothèque
                                                             └── FCM (facultatif)

Dashboard web ── API et générateur APK Android
```

Voir le [cahier des charges technique](cahier_des_charges_technique_melodiscan_industrialis.md) pour les détails.
