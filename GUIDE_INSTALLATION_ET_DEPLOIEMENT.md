# Guide de déploiement — Application de rencontre Chari (Android & Apple iOS)

Ce projet a été configuré pour fonctionner sur **Android**, **Apple (iOS)** et sur le web en **PWA (Progressive Web App)**.

---

## 📁 Structure du projet

* `www/` : Le code source de l'application (HTML, CSS, JavaScript, icônes, manifest PWA).
  * `www/index.html` : L'interface principale (bilingue Français/Arabe, swipes, chat, profil, paiements).
  * `www/manifest.json` : Fichier de configuration PWA (icônes, couleur de thème, affichage plein écran).
  * `www/sw.js` : Service worker pour le mode hors ligne et l'installation instantanée.
  * `www/icons/` : Les icônes de l'application (192px, 512px et vectoriel SVG).
* `android/` : **Projet natif Android** complet (prêt pour Android Studio).
* `ios/` : **Projet natif Apple (iOS)** complet (prêt pour Xcode).
* `capacitor.config.json` : Configuration générale Capacitor (identifiant `td.chari.app`).
* `sync.bat` : Script en un clic pour synchroniser vos modifications web vers les dossiers Android et iOS.
* `lancer-apercu.bat` : Script pour tester l'application dans votre navigateur sur votre ordinateur.

---

## 📱 1. Comment tester immédiatement sur téléphone (PWA)

Sans même installer d'outils lourds de compilation, l'application est déjà une **PWA** :
1. Lancez `lancer-apercu.bat` ou mettez le contenu du dossier `www` en ligne (par exemple sur Vercel, Netlify ou Firebase Hosting qui sont 100% gratuits).
2. Ouvrez le lien sur votre téléphone :
   * **Sur Android (Chrome)** : Un bouton « Installer l'application » ou « Ajouter à l'écran d'accueil » apparaît. L'application s'installe et s'ouvre comme une vraie application sans barre d'adresse.
   * **Sur iPhone (Safari)** : Appuyez sur le bouton de partage (icône avec un carré et une flèche vers le haut) puis sur **« Sur l'écran d'accueil »**. L'icône Chari s'ajoute à votre écran d'accueil et s'ouvre en plein écran.

---

## 🤖 2. Comment générer l'APK pour Android

1. Téléchargez et installez **Android Studio** (gratuit sur [developer.android.com/studio](https://developer.android.com/studio)).
2. Lancez Android Studio et cliquez sur **Open** (Ouvrir un projet existant).
3. Sélectionnez le dossier `android` situé dans ce dossier :
   `C:\Users\DELL\Downloads\Rencontre\android`
4. Android Studio va synchroniser le projet Gradle.
5. Dans le menu du haut, cliquez sur :
   **Build > Build Bundle(s) / APK(s) > Build APK(s)**
6. Une fois la compilation terminée, un lien "locate" apparaît : votre fichier `.apk` est prêt !
7. Vous pouvez envoyer ce fichier `.apk` sur n'importe quel smartphone Android par câble USB, WhatsApp ou Google Drive et l'installer directement.

Pour publier sur le **Google Play Store** :
* Dans Android Studio, allez dans **Build > Generate Signed Bundle / APK**.
* Choisissez **Android App Bundle (.aab)** et signez-le avec votre clé de production.

---

## 🍏 3. Comment compiler et publier pour Apple (iOS / iPhone)

Apple exige macOS et Xcode pour compiler le binaire final iOS :
* **Option A (Si vous avez un Mac)** :
  1. Copiez ce dossier sur votre Mac.
  2. Ouvrez le dossier `ios/App` dans **Xcode**.
  3. Branchez votre iPhone ou lancez le simulateur, puis cliquez sur **Play / Run**.
  4. Pour publier sur l'App Store, configurez votre compte Apple Developer et lancez **Product > Archive**.
* **Option B (Si vous n'avez pas de Mac)** :
  * Vous pouvez utiliser un service cloud d'intégration continue comme **Codemagic**, **GitHub Actions** ou **Appcircle** qui compile le projet `ios` automatiquement dans le cloud sans avoir besoin d'acheter un Mac.

---

## 🔄 Comment mettre à jour le code ?

1. Modifiez les fichiers dans le dossier `www/` (design, textes, fonctionnalités).
2. Double-cliquez sur `sync.bat` (ou tapez `npx cap sync` dans un terminal).
3. Les projets Android et iOS reçoivent instantanément vos modifications !
