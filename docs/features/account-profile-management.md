# Account Profile Management

## 1. Summary
- Clear description: Displays and edits current account profile and linked-child details.
- User problem solved: Users maintain personal data in-app.
- Product value: Improves data quality for communication and role context.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Profile maintenance is needed for reliable contact and identity context.
- Target users: all authenticated roles.
- Context of use: `AccountView`.
- Expected outcome: profile updates persist and refresh correctly.

## 3. Scope
Included
- Account data display.
- Profile edit sheet and save flow.
- Linked child display for parent role.

Excluded
- Password change and invitation acceptance flows.

## 4. Actors
- Admin
Permissions: edit own profile.
Actions: update account fields.
Restrictions: own account only.
- Coach
Permissions: same.
Actions: same.
Restrictions: own account only.
- Parent
Permissions: same plus linked child read-only info.
Actions: update own profile.
Restrictions: child data non-editable.
- Player
Permissions: edit own profile.
Actions: same.
Restrictions: own account only.
- Guest
Permissions: none.
Actions: none.
Restrictions: blocked.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: blocked.
- System
Permissions: fetch teams and linked child to enrich profile view.
Actions: refresh auth profile after update.
Restrictions: depends on API availability.

## 5. Entry Points
- UI: account destination in app chrome.
- API: `/me/profile`, `/teams`, `/me/child`.

## 6. User Flows
- Main flow: open account -> edit fields -> save -> view refreshed values.
- Variants: parent inspects linked child card.
- Back navigation: dismiss edit sheet.
- Interruptions: save or linked-child fetch errors.
- Errors: profile alerts.
- Edge cases: linked child unavailable.

## 7. Functional Behavior
- UI behavior: read-only + editable sections.
- Actions: submit profile update request.
- States: view, editing, saving, error.
- Conditions: authenticated context.
- Validations: local field validation before save.
- Blocking rules: save disabled while request in flight.
- Automations: profile refresh after save.

## 8. Data Model
- `Me`, `Team`, `LinkedChildProfile`.
Source: account-related endpoints.
Purpose: account overview and edit payload.
Format: codable models with alias handling.
Constraints: backend field validation.

## 9. Business Rules
- User edits only own profile.
- Parent linked child is read-only information.
- Team display uses team id lookup from list endpoint.

## 10. State Machine
- States: loading/ready/editing/saving/error.
- Transitions: enter edit -> submit -> success/failure.
- Invalid transitions: submit without auth context.

## 11. UI Components
- Profile summary list.
- Edit sheet form.
- Linked child block.

## 12. Routes / API / Handlers
- Native: `AccountView` methods.
- API: me profile update and related reads.

## 13. Persistence
- Client: local view state.
- Backend: `User` table updates.

## 14. Dependencies
- Upstream: auth store.
- Downstream: messaging and invite operations rely on updated contact data.
- Cross-repo: web account page uses same contract.

## 15. Error Handling
- Validation: local + backend errors.
- Network: alert and retry.
- Missing data: linked child request failure tolerated.
- Permissions: auth required.
- Current vs expected: error granularity can improve.

## 16. Security
- Access control: authenticated access only.
- Data exposure: own profile and linked child only.
- Guest rules: blocked.

## 17. UX Requirements
- Feedback: explicit save success/failure states.
- Empty states: fallback for absent optional values.
- Loading: show progress while loading and saving.
- Responsive: native forms with keyboard-safe layout.

## 18. Ambiguities & Gaps
- Observed
- Alias-heavy decoding remains necessary.
- Inferred
- API normalization effort is still active.
- Missing
- Profile completeness indicator.
- Tech debt
- Repeated data-normalization logic across models.

## 19. Recommendations
- Product: define required profile fields per role.
- UX: add profile validation hints inline.
- Tech: centralize profile field adapter utilities.
- Security: track profile update audit events.

## 20. Acceptance Criteria
1. Authenticated user can view and edit own profile.
2. Save refreshes displayed data.
3. Parent sees linked child info when available.
4. Failures are handled without navigation breakage.

## 21. Test Scenarios
- Happy path: edit phone and save.
- Permissions: unauthenticated user cannot access account view.
- Errors: backend validation failure.
- Edge cases: no linked child for parent role.

## 22. Technical References
- `izifoot/Features/Account/AccountView.swift`
- `izifoot/Core/Models/APIModels.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
