# izifoot iOS

Base iOS native SwiftUI alignée avec `izifoot-web` et `api.izifoot.fr`.

## Ce qui est livré

- Architecture iOS native: `TabView`, `NavigationStack`, `List`, `Form`, `Toolbar`, `ShareLink`, `searchable`.
- Auth via web sécurisée: `ASWebAuthenticationSession`, échange code/state, restauration de session, logout.
- Scope équipe actif: header API `X-Team-Id` / `X-Active-Team-Id` comme le web.
- Modules principaux:
  - `Mon club` (direction): club, équipes, coachs, création d’équipe.
  - `Planning`: entraînements + plateaux, création en bottom sheets, détails.
  - `Exercices`: liste, détail, bouton d'ajout flottant, création en bottom sheet.
  - `Mon équipe`: liste, recherche, détail, création en bottom sheet.
  - `Stats`: agrégats clés (joueurs, entraînements, plateaux, exercices).
  - `Compte`: infos compte + logout.
  - `Partage public`: chargement d’un plateau public par token.

## Arborescence

- `/Users/jeromeboukorras/Dev/izifoot-ios/IzifootIOS/App`
- `/Users/jeromeboukorras/Dev/izifoot-ios/IzifootIOS/Core`
- `/Users/jeromeboukorras/Dev/izifoot-ios/IzifootIOS/Features`

## Setup Xcode

L'environnement actuel ne contient pas l'app Xcode complète (pas de `xcodebuild`), donc le code SwiftUI est fourni prêt à intégrer dans un projet iOS Xcode.

1. Créer une app iOS SwiftUI (Xcode 16+, iOS 17+ recommandé).
2. Copier le dossier `IzifootIOS` dans le projet.
3. Ajouter tous les fichiers Swift au target iOS.
4. Vérifier que le point d’entrée est `IzifootApp`.
5. Lancer sur simulateur iPhone.

## Auth iOS via web

Flow livré:

1. L’utilisateur touche `Se connecter`.
2. L’app ouvre `https://izifoot.fr/auth/mobile/start?platform=ios` via `ASWebAuthenticationSession`.
3. Le web redirige ensuite vers l’app avec `izifoot://auth/callback?code=...&state=...`.
4. L’app échange ce couple via `POST /auth/mobile/exchange`.
5. L’access token est stocké dans le Keychain, jamais dans `UserDefaults`.
6. L’app recharge `/me` puis ouvre l’espace connecté.

Configuration Xcode appliquée:

- URL scheme personnalisé: `izifoot`
- `Info.plist` explicite pour déclarer `CFBundleURLTypes`
- stockage local: `TokenStore` Keychain pour access token et refresh token éventuel

Variables / dépendances backend attendues:

- `APP_BASE_URL` doit pointer vers le site web `izifoot.fr`
- `IOS_APP_CALLBACK_URL` peut rester sur `izifoot://auth/callback`
- `MOBILE_AUTH_CODE_TTL_SECONDS` optionnel pour la durée de vie du code temporaire

## Contrats API utilisés

Base URL: `https://api.izifoot.fr`

Endpoints principaux repris depuis la web app:

- `POST /auth/login`
- `POST /auth/register`
- `POST /auth/logout`
- `GET /auth/mobile/start`
- `POST /auth/mobile/exchange`
- `GET /me`
- `GET /clubs/me`
- `GET /clubs/me/coaches`
- `GET/POST /teams`
- `GET/POST /players`
- `GET /players/:id`
- `GET/POST /trainings`
- `GET/POST /matchday`
- `GET /matches?matchdayId=...`
- `POST /matchday/:id/share`
- `GET /drills`
- `GET/POST /drills`
- `GET /drills/:id`
- `GET /attendance?session_type=...&session_id=...`
- `GET /public/matchday/:token`

## Parité web -> iOS (itération 1)

- Auth + rôles: ✅
- Sélection équipe active: ✅
- Club management: ✅ (socle)
- Planning: ✅ (socle)
- Détails entraînement/plateau: ✅ (socle)
- Exercice + détail: ✅ (socle)
- Effectif + détail: ✅ (socle)
- Stats globales: ✅
- Matchday public: ✅
- Diagram editor tactique: ✅
- Matchday orchestration avancée (rotations, events): ⏳ à implémenter
- IA drills/diagram endpoints: 🟡 génération de diagrammes livrée, génération d'exercices à finir
