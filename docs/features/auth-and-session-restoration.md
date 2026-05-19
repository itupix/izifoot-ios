# Auth And Session Restoration

## 1. Summary
- Clear description: Manages login, registration, session restore, and logout in `AuthStore`/`AuthView`.
- User problem solved: Users can securely enter and return to the app.
- Product value: Gatekeeper for all protected mobile modules.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Native app must persist and restore authentication reliably.
- Target users: all account roles.
- Context of use: app launch and auth actions.
- Expected outcome: stable authenticated state and populated `me` context.

## 3. Scope
Included
- `AuthStore.swift` and `AuthView.swift`.
- `AuthService.swift` with `ASWebAuthenticationSession`.
- Root switching in `RootView.swift`.
- Login/register/logout + refresh flow.

Excluded
- Universal Links / Associated Domains are not active in the current delivery; callback uses the custom URL scheme `izifoot://`.

## 4. Actors
- Admin
Permissions: login/register/logout.
Actions: enters direction workspace.
Restrictions: backend role checks still apply.
- Coach
Permissions: same.
Actions: enters coach workspace.
Restrictions: scoped operations only.
- Parent
Permissions: same.
Actions: enters parent workspace.
Restrictions: no admin-only tabs.
- Player
Permissions: same.
Actions: enters player workspace.
Restrictions: no admin-only tabs.
- Guest
Permissions: view auth screen only.
Actions: submit credentials.
Restrictions: no protected content.
- Unauthenticated user
Permissions: same as guest.
Actions: none beyond auth attempts.
Restrictions: no tabs.
- System
Permissions: restore session from token storage.
Actions: route to shell or auth view.
Restrictions: dependent on backend `/me` availability.

## 5. Entry Points
- UI: `AuthView`, launch `RootView`.
- API: auth endpoints via `IzifootAPI`, including mobile exchange.
- System triggers: app startup session restoration.

## 6. User Flows
- Main flow: open app -> restore session -> show shell or auth.
- Mobile flow: tap `Se connecter` -> `ASWebAuthenticationSession` -> web login page -> `izifoot://auth/callback?code&state` -> `/auth/mobile/exchange` -> `/me`.
- Back navigation: logout returns to auth screen.
- Interruptions: token invalidated server-side.
- Errors: user cancellation is neutral, network/exchange/token failures are surfaced as auth errors.
- Edge cases: network unavailable during restore.

## 7. Functional Behavior
- UI behavior: blocking loader while restoring session; web-auth progress during exchange.
- Actions: web sign-in, logout and `me` refresh.
- States: restoring, authenticated, unauthenticated, error.
- Conditions: valid callback `code/state`, backend availability, valid token exchange.
- Validations: local form checks + backend responses.
- Blocking rules: main shell not shown until auth resolved.
- Automations: restore attempt on startup.

## 8. Data Model
- `Me` model in `APIModels.swift`.
Source: `/me` response.
Purpose: role-based UI and scope.
Format: Codable with alias decoding.
Constraints: role enum and optional scope fields.
- Keychain tokens
Source: `/auth/mobile/exchange`.
Purpose: authenticated API access after web sign-in.
Format: access token + optional refresh token.
Constraints: stored in Keychain only.

## 9. Business Rules
- `AuthStore` is single source for auth state.
- Successful auth always followed by `/me` refresh.
- Web auth never stores tokens in callback URLs; only `code + state` traverse the custom scheme.
- Logout clears session and returns to auth route.

## 10. State Machine
- `RESTORING` -> `AUTHENTICATED` or `UNAUTHENTICATED`.
- `UNAUTHENTICATED` -> `AUTHENTICATING` -> `AUTHENTICATED`.
- `AUTHENTICATING` includes the web callback exchange step before shell access.
- Invalid transitions: shell render without valid `me` when restore pending.

## 11. UI Components
- Auth CTA screen.
- Root loading view.
- Logout actions in account/chrome contexts.

## 12. Routes / API / Handlers
- Native handlers: `AuthStore` methods.
- API: `/auth/mobile/exchange`, `/auth/logout`, `/me`.

## 13. Persistence
- Token persistence in `TokenStore`/`AppSession`.
- In-memory `AuthStore` published state.

## 14. Dependencies
- Upstream: backend auth contract.
- Downstream: shell tabs and all feature views.
- Cross-repo: parity expected with web auth behavior.

## 15. Error Handling
- Validation: form-level checks.
- Network: errors surfaced through alert messages.
- Missing data: failed `/me` refresh resets auth state.
- Permissions: backend decides role access.
- Current vs expected: structured machine error mapping is limited.

## 16. Security
- Access control: authenticated shell only.
- Data exposure: auth data retained in secure local storage abstractions.
- Guest rules: no protected content.
- Callback: custom URL scheme `izifoot://` must be declared in the app bundle.

## 17. UX Requirements
- Feedback: clear loading and error states.
- Errors: actionable auth failure messages.
- Loading: launch spinner while session restore runs.
- Responsive: native layout adapts by default.

## 18. Ambiguities & Gaps
- Observed
- Web remains the source of truth for sign-in and account creation.
- Inferred
- iOS onboarding parity is still evolving.
- Missing
- Universal Links / Associated Domains if the project later migrates away from the custom URL scheme.
- Tech debt
- Error handling mostly message-based, not typed.

## 19. Recommendations
- Product: define iOS invite onboarding parity target.
- UX: add deep-link handling for invitation URLs.
- Tech: introduce typed auth error enum.
- Security: review token storage hardening and expiry refresh strategy.

## 20. Acceptance Criteria
1. App restores an existing Bearer session on launch.
2. `Se connecter` opens the web auth flow and returns through `izifoot://`.
3. Successful exchange stores the token in Keychain and transitions to shell.
4. Logout returns to auth view and clears Keychain credentials.
5. Failed auth requests display an error without crash.

## 21. Test Scenarios
- Happy path: web sign-in then relaunch app with restored session.
- Permissions: unauthenticated user cannot reach shell tabs.
- Errors: user cancellation, missing code, exchange rejection, invalid token.
- Edge cases: token expired during restore.

## 22. Technical References
- `izifoot/Features/Auth/AuthStore.swift`
- `izifoot/Features/Auth/AuthService.swift`
- `izifoot/Features/Auth/AuthView.swift`
- `izifoot/Features/Shell/RootView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
