# izifoot iOS

Base iOS native SwiftUI alignée avec `izifoot-web` et `api.izifoot.fr`.

## Ce qui est livré

- Architecture iOS native: `TabView`, `NavigationStack`, `List`, `Form`, `Toolbar`, `ShareLink`, `searchable`.
- Auth complète: connexion, inscription, restauration de session, logout.
- Scope équipe actif: header API `X-Team-Id` / `X-Active-Team-Id` comme le web.
- Modules principaux:
  - `Mon club` (direction): club, équipes, coachs, création d’équipe.
  - `Planning`: entraînements + plateaux, création en bottom sheets, détails.
  - `Exercices`: liste, détail, création en bottom sheet.
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

## Contrats API utilisés

Base URL: `https://api.izifoot.fr`

Endpoints principaux repris depuis la web app:

- `POST /auth/login`
- `POST /auth/register`
- `POST /auth/logout`
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
- Diagram editor tactique: ⏳ à implémenter (Canvas SwiftUI)
- Matchday orchestration avancée (rotations, events): ⏳ à implémenter
- IA drills/diagram endpoints: ⏳ à implémenter

