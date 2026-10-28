# 🎵 MelodiScan

**MelodiScan** est une application personnelle d'OMR (*Optical Music Recognition*) domestique permettant de prendre en photo une partition musicale monophonique depuis un smartphone Android, de l'analyser sur un serveur Ubuntu local, puis de la jouer de manière interactive sur le téléphone.

---

## 📋 CAHIER DES CHARGES TECHNIQUE

### 1. Présentation du Projet
* **Nom du projet :** MelodiScan
* **Type de musique :** Mélodies simples et monophoniques (une seule note à la fois : xylophone, flûte, saxophone).
* **Réseau :** Utilisation exclusive en réseau local (Wi-Fi domestique).
* **Environnement :** Client Android et Serveur Ubuntu Linux.

---

## 2. Architecture Globale du Système

```
[ Smartphone Android ] ───────( Réseau Local Wi-Fi )───────► [ Serveur Ubuntu ]
  ├── Appareil photo            • Requête HTTP POST (Photo)    ├── API FastAPI
  └── Lecteur Interactif        ◄──────────────────────────────┤  ├── Traitement OMR (oemer)
      (Fichier MIDI + .sf2)       Fichier MIDI en retour       └── Conversion (music21)
```

---

## 3. Spécifications du Serveur (Back-End)

### Environnement technique
* **OS :** Ubuntu Linux
* **Langage :** Python 3.10+ (dans un environnement virtuel `venv`)
* **Framework API :** FastAPI (pour sa rapidité et sa documentation automatique)
* **Moteur OMR :** `oemer` (Optical Music Recognition)
* **Manipulation Musicale :** `music21`

### Fonctionnalités de l'API (`/scan`)
1. **Réception :** Un point de terminaison (Endpoint) `POST /scan` qui accepte un fichier image (`multipart/form-data`).
2. **Traitement OMR :** Le script sauvegarde l'image temporairement, exécute la commande système `oemer <image>` pour générer un fichier `.musicxml`.
3. **Conversion :** Utilisation de `music21` pour lire le fichier `.musicxml` généré et l'exporter au format standard `.mid` (MIDI).
4. **Réponse :** L'API renvoie directement le fichier `.mid` au smartphone avec le type MIME approprié (`audio/midi`), puis nettoie les fichiers temporaires.

---

## 4. Spécifications de l'Application Mobile (Front-End)

### Environnement technique
* **Plateforme :** Android (Développement suggéré en **Flutter** pour la gestion simple des plugins audio et réseau).
* **Stockage Local :** Gestion éphémère (le fichier MIDI reçu peut être écrasé à chaque nouveau scan).

### Écrans et Expérience Utilisateur (UX)
L'application comporte un écran unique divisé en deux états :

#### État 1 : Capture
* Un bouton central **"Scanner une partition"** qui ouvre l'appareil photo.
* Une fois la photo prise, un indicateur visuel de chargement (*"Analyse de la partition en cours..."*) s'affiche pendant que la photo est envoyée en tâche de fond à l'adresse IP locale du serveur (`http://<IP_SERVEUR>:8000/scan`).

#### État 2 : Lecteur Interactif (Mode "Interactif")
Dès la réception du fichier MIDI, l'interface bascule en mode lecteur avec les composants suivants :
* **Boutons de contrôle :** Play, Pause, Stop.
* **Contrôle du Tempo :** Un curseur (Slider) permettant de modifier la vitesse de lecture (ex: de 50% à 150% du tempo d'origine) sans altérer la hauteur des notes.
* **Visualisation défilante :** Une barre de progression ou une visualisation simplifiée (type ligne de temps ou mini Piano Roll) qui montre la note en train d'être jouée pour aider à suivre le rythme au xylophone ou à la flûte.

### Moteur Audio Local
* L'application intègre un synthétiseur MIDI local utilisant une **SoundFont (.sf2)** légère (ex: son de piano ou de xylophone généraliste) embarquée dans les assets de l'application.
* **Aucun flux audio n'est généré par le serveur :** c'est le smartphone qui synthétise le son en temps réel à partir du fichier MIDI reçu, garantissant une latence zéro lors des actions Play/Pause et du changement de tempo.

---

## 5. Gestion des Erreurs et Robustesse
* **Timeouts réseau :** Le traitement d'image par l'IA sur le serveur pouvant prendre de 5 à 30 secondes selon la puissance de la machine, l'application mobile doit avoir un timeout réseau configuré à au moins 60 secondes.
* **Notification d'échec :** Si le serveur ne parvient pas à lire la partition, l'API renvoie une erreur HTTP 422 ou 500, et l'application affiche un message clair : *"Impossible de lire la partition. Veuillez reprendre la photo avec une meilleure luminosité."*