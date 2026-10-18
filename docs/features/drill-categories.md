# Exercise categories

Exercises use the closed category values `collectif`, `technique`, `jeu`, `autres`, displayed as Collectif, Technique, Jeu, Autres in that order. Creation defaults to Autres even when the library is empty. Existing exercises are migrated to `autres` by the backend.

Drill models, creation requests, details and training selection no longer include exercise duration or player counts. Training duration and diagram animations are unchanged.

The exercise library uses a versioned cache key to prevent pre-migration categories from returning offline. Category choices come from the API contract rather than the cached catalogue.

Validation: the full Debug iOS Simulator build passes with signing disabled. Runtime Swift checks pass for decoding a Drill without duration/players, encoding without those keys, the exact category order and French labels.

## Editing an exercise

Staff can use **Modifier la fiche**, separately from diagram actions, in the library or training exercise detail. The same active-team permission rule applies to both actions. The sheet starts with the current title, description and category, trims text, and validates title (1–100 characters), description (1–2000 characters) and the closed category list.

Save sends `PUT /drills/:id` with only `title`, `description`, `category`; tags remain unchanged. Saving disables fields, duplicate submissions, cancellation and swipe dismissal. An API error stays in the sheet with the draft retained. Success uses the returned canonical Drill, immediately updates the detail and training/library lists, invalidates all versioned exercise library caches, and closes the sheet. Editing from a training changes the source drill ID, not the training association.
