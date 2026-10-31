# Championnat iOS — contrat v1

L'onglet Championnat suit Planning. Calendrier et Classement partagent le championnat de l'équipe active ; les joueurs et parents consultent sans modifier. Les droits sont fournis par `canManage`.

Configuration : nom, noms des adversaires (l'équipe active est ajoutée côté serveur), aller-retour activé par défaut. Le serveur génère les rencontres, journées, repos et classement. Aucun calcul métier du calendrier ou du classement n'est dupliqué dans l'app.

Intégration : `GET /championship?teamId=`, `POST /championship`, `PATCH /championship/:id/fixtures/:fixtureId`, `PUT /championship/:id/order`, `POST /championship/:id/validate`, `PUT /championship/:id/fixtures/:fixtureId/result`. Chaque mutation porte la révision courante et remplace l'enveloppe locale par la réponse serveur. Un conflit 409 recharge les données et invite à réessayer.

Date et heure sont enregistrées ensemble en ISO 8601 avec fuseau ; leur suppression envoie explicitement `kickoffAt: null`. Les scores sont soit deux entiers de 0 à 999, soit deux valeurs null pour retirer le résultat. Seul un championnat validé propose la saisie des résultats.

Le calendrier affiche une liste globale triée par `order`, chaque rencontre conservant son badge journée/aller-retour. Le glisser-déposer et les boutons Monter/Descendre déplacent seulement les rencontres non datées, en conservant exactement les positions des rencontres datées. Le corps envoyé contient tous les identifiants. Les journées d'origine et les repos ne sont pas recalculés par le client.

Après validation, le Planning affiche seulement les rencontres de l'équipe active : celles datées au jour sélectionné et toutes celles non datées dans « À programmer ». Il lit le championnat serveur pour compléter les matchdays existants, sans inventer de date ni créer de doublon local. Les jours de rencontres datées sont signalés dans le sélecteur calendrier et les données sont rechargées au retour dans Planning. Les cartes de rencontres ouvrent Championnat ; le détail historique de match reste privé et comporte des commandes manuelles non adaptées à ce flux. Le classement est signalé indicatif (3/1/0 ; départage points, différence, buts, nom).

Vérification autonome : `swiftc izifoot/Features/Championship/ChampionshipModels.swift tests/ChampionshipChecks.swift -o /tmp/championship-checks && /tmp/championship-checks`.

Validation effectuée : compilation Xcode Debug arm64 pour iphonesimulator réussie avec signature désactivée ; contrôles autonomes contrat, réordonnancement et valeurs null réussis. Aucun test UI sur simulateur ni parcours authentifié complet : CoreSimulator installé ne correspond pas à la version Xcode et aucun runtime n’est disponible.
