# Exercise categories

Exercises use the closed category values `collectif`, `technique`, `jeu`, `autres`, displayed as Collectif, Technique, Jeu, Autres in that order. Creation defaults to Autres even when the library is empty. Existing exercises are migrated to `autres` by the backend.

Drill models, creation requests, details and training selection no longer include exercise duration or player counts. Training duration and diagram animations are unchanged.

The exercise library uses a versioned cache key to prevent pre-migration categories from returning offline. Category choices come from the API contract rather than the cached catalogue.

Validation: the full Debug iOS Simulator build passes with signing disabled. Runtime Swift checks pass for decoding a Drill without duration/players, encoding without those keys, the exact category order and French labels.
