# 🎵 MelodiScan — Notice Technique & Manuel de A à Z

<p align="center">
  <img src="logo.svg" width="160" height="160" alt="MelodiScan Logo" />
</p>

**MelodiScan** est une application personnelle d'**OMR** (*Optical Music Recognition*) domestique. Elle permet de numériser une partition musicale monophonique à partir d'un smartphone Android, d'analyser la partition via un serveur local Ubuntu Linux (FastAPI + OMR engine), puis d'écouter et de contrôler la mélodie de manière interactive directement sur le téléphone.

---

## 📐 1. Architecture Globale du Système

```
 [ Smartphone Android / iOS ]  ───────── (Réseau Local Wi-Fi) ─────────►  [ Serveur Local Ubuntu ]
   ├── Appareil photo / Galerie        • POST /scan (Photo multipart)        ├── FastAPI (`backend/main.py`)
   └── Lecteur Interactif              ◄───────────────────────────────┤  ├── Moteur OMR (`oemer` CLI)
       (Contrôle Tempo, Transpose,       Fichier MIDI (`.mid`)               └── Conversion MusicXML (`music21`)
        Visualisation des notes)
```

1. **Prise de photo :** L'utilisateur photographie une partition monophonique (flûte, xylophone, saxophone, chant).
2. **Transfert HTTP :** L'image est transmise en réseau local via un POST multipart (`/scan`) avec un timeout réseau de 60s.
3. **Traitement OMR Server :** Le serveur exécute `oemer` pour extraire la structure musicale en `.musicxml`, puis utilise `music21` pour convertir le résultat au format standard `.mid`.
4. **Lecteur Interactif Local :** Le smartphone reçoit le fichier MIDI et synthétise le son en temps réel avec latence zéro, permettant de régler la vitesse (tempo BPM) et la transposition sans altérer la hauteur du son.

---

## 🛠️ 2. Prérequis & Installation du Serveur (Back-End)

### Prérequis Système
* **Système d'exploitation :** Ubuntu 20.04 / 22.04 LTS (ou tout système Linux compatible)
* **Python :** Python 3.10 ou supérieur
* **Outil OMR (Optionnel recommandé) :** `oemer` (`pip install oemer`)

### Étape 1 : Cloner le dépôt et créer l'environnement virtuel
```bash
git clone <URL_DU_DEPOT>
cd melodiscan

# Création du venv Python
python3 -m venv venv
source venv/bin/activate
```

### Étape 2 : Installer les dépendances backend
```bash
pip install -r backend/requirements.txt
```

### Étape 3 : Lancer le serveur FastAPI
```bash
# Démarrage sur toutes les interfaces locales du réseau (port 8000)
uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

*Le serveur est prêt dès que la console affiche : `INFO: Uvicorn running on http://0.0.0.0:8000`.*

---

## 📱 3. Installation et Lancement de l'Application Mobile (Front-End)

### Prérequis Mobile
* **Flutter SDK :** Version 3.22.0+ / 3.41.0+
* **Dart SDK :** Version 3.4.0+
* **Appareil cible :** Smartphone Android ou Émulateur Android Studio

### Étape 1 : Récupérer les dépendances Flutter
```bash
cd mobile
flutter pub get
```

### Étape 2 : Lancer les tests unitaires & widgets
```bash
flutter test
```

### Étape 3 : Lancer l'application sur un terminal connecté
```bash
# Lancer sur appareil connecté ou émulateur
flutter run
```

### Étape 4 : Compiler le fichier APK Android (Release)
```bash
flutter build apk --release
```
*L'APK généré se trouvera dans `mobile/build/app/outputs/flutter-apk/app-release.apk`.*

---

## 📖 4. Guide d'Utilisation de A à Z (Notice Utilisateur)

### ⚙️ Phase 1 : Configuration du Serveur
1. Déterminez l'adresse IP locale de votre machine Ubuntu (ex: `192.168.1.50`) en exécutant `ip a` ou `hostname -I`.
2. Lancez le serveur FastAPI (`uvicorn backend.main:app --host 0.0.0.0 --port 8000`).

### 📸 Phase 2 : Scan d'une Partition
1. Ouvrez l'application **MelodiScan** sur le téléphone.
2. Saisissez l'adresse de votre serveur dans le champ dédié (ex: `192.168.1.50:8000`) ou appuyez sur l'un des raccourcis IP prédéfinis.
3. Vous pouvez tester la connexion au serveur en appuyant sur le bouton **Rafraîchir/Test** (badge vert "En ligne").
4. Appuyez sur **"Prendre une photo"** ou **"Galerie"** pour sélectionner une partition.
5. Une prévisualisation de la photo s'affiche. Appuyez sur **"Lancer l'analyse OMR"**.
6. L'indicateur de chargement *"Analyse OMR de la partition en cours..."* s'affiche pendant que l'IA du serveur numérise la musique.

### 🎼 Phase 3 : Mode Lecteur Interactif
Dès réception du fichier MIDI, l'interface bascule en mode **Lecteur Interactif** :
* **Carte de Note Actuelle :** Affiche la note exacte jouée en temps réel (ex: `C4`, `G4`, `F#4`) avec un effet d'impulsion visuelle.
* **Boutons de Lecture :** Play / Pause et Stop.
* **Barre de Recherche (Seeking) :** Glissez pour sauter directement à un instant précis de la partition.
* **Contrôle du Tempo (50% à 150%) :** Ajustez la vitesse de lecture sans modifier la hauteur des notes (affichage dynamique en BPM).
* **Transposition (Hauteur) :** Ajustez la hauteur globale de la mélodie de -6 à +6 demis-tons.
* **Séquence des Notes :** Déroulez l'accordéon en bas pour visualiser l'enchaînement de toutes les notes détectées.

### 🎨 Phase 4 : Personnalisation
* Appuyez sur l'icône **Palette** dans l'en-tête de l'application pour basculer en **Mode Sombre** ou sélectionner une couleur de thème (Violet, Indigo, Teal, Orange, Rose).

---

## 🌐 5. Spécifications de l'API REST (`backend/main.py`)

| Méthode | Endpoint | Description | Format d'entrée | Format de sortie |
|---|---|---|---|---|
| `GET` | `/` | Test d'état du serveur | Aucun | `{"message": "MelodiScan API is running"}` |
| `POST` | `/scan` | Numérisation OMR d'une partition | `multipart/form-data` (`file`: image) | Fichier binaire `audio/midi` (`partition.mid`) |

### Codes Erreurs HTTP API :
* `200 OK` : Succès, le fichier `.mid` est renvoyé.
* `422 Unprocessable Entity` : Format d'image invalide ou illisible.
* `500 Internal Server Error` : Échec du traitement OMR sur le serveur.

---

## 🧪 6. Exécution des Tests de Vérification

### Tests Backend (Python)
```bash
PYTHONPATH=. pytest backend/tests/test_main.py
```

### Tests Mobile (Flutter)
```bash
cd mobile
flutter test
```

---

## ❓ 7. Dépannage & Foire Aux Questions (FAQ)

#### Q: L'application affiche "Impossible de contacter le serveur" ?
* Vérifiez que le smartphone et le serveur Ubuntu sont connectés au **même réseau Wi-Fi local**.
* Assurez-vous que le pare-feu Ubuntu n'intercepte pas le port 8000 (`sudo ufw allow 8000/tcp`).

#### Q: Que faire si l'analyse OMR échoue ?
* Assurez-vous que la photo est bien éclairée, sans ombre portée sur la portée.
* MelodiScan est conçu pour des **mélodies monophoniques** (une seule ligne de notes sans accords complexes).
