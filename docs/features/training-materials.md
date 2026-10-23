# Matériel de la séance

La page Entraînement affiche une carte Matériel après les exercices, y compris en lecture seule et pour une séance annulée. Elle utilise GET /trainings/:id/materials avec l’authentification habituelle, sans calcul local ni endpoint supposé.

Le serveur fournit les libellés et les quantités maximales réutilisables entre exercices et images. Une quantité null (chasubles) ne reçoit aucun chiffre. Les lignes s’adaptent aux grands caractères. Les exercices sans schéma produisent un avertissement de liste partielle ou indisponible, distinct d’une absence de matériel ou d’exercices. Une erreur réseau propose Réessayer.

Actualisation à l’ouverture, par rafraîchissement manuel, après ajout/suppression d’exercice et au retour de sa page ou lors de sa mise à jour. Une ancienne réponse ne peut pas remplacer une sélection plus récente.

Vérification automatisée : `python3 tests/check_training_materials.py` (décodage, quantité null, erreur, nouvelle tentative et réponses concurrentes).

La requête matériel est indépendante des autres ressources de la page : sa panne ne bloque pas les présences ou exercices. Validation du build Debug pour simulateur iOS avec Xcode, sans signature. Revue UX du code réalisée ; rendu sur appareil/simulateur à contrôler avant livraison.
