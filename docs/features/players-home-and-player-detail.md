# Players Home And Player Detail

## 1. Summary
- Clear description: Player list, creation, detail editing, invitation status, and parent unlink actions.
- User problem solved: Staff can manage roster from mobile.
- Product value: Mobile parity for core player operations.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Coaches need roster access during sessions and travel.
- Target users: admin/coach.
- Context of use: players tab.
- Expected outcome: accurate player records and invite status insight.

## 3. Scope
Included
- `PlayersHomeView.swift` and `PlayerDetailView.swift`.
- Player list/create/edit/delete.
- Invite and parent-link management actions.

Excluded
- Public/player-portal access flows.

## 4. Actors
- Admin
Permissions: full roster management.
Actions: CRUD and invite.
Restrictions: scope.
- Coach
Permissions: same in managed scope.
Actions: same.
Restrictions: scope.
- Parent
Permissions: no tab access.
Actions: none.
Restrictions: blocked.
- Player
Permissions: no tab access.
Actions: none.
Restrictions: blocked.
- Guest
Permissions: none.
Actions: none.
Restrictions: blocked.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: blocked.
- System
Permissions: enriches player detail with attendance/match context.
Actions: computes derived statistics and invitation state.
Restrictions: dependent on multi-endpoint calls.

## 5. Entry Points
- UI: players tab list and detail navigation.
- API: players endpoints, invitation status/invite, parent delete, aggregate endpoints.

## 6. User Flows
- Main flow: open players list -> create/select player -> edit detail.
- Variants: send invite or remove parent link.
- Back navigation: detail back to list.
- Interruptions: invite action errors.
- Errors: validation or scope failures.
- Edge cases: legacy payload aliases.

## 7. Functional Behavior
- UI behavior: paginated list and sheet-based create/edit forms.
- Actions: CRUD plus invite operations.
- States: loading, saving, deleting, error.
- Conditions: role and scope checks.
- Validations: required fields and contact formatting.
- Blocking rules: disable actions during persistence.
- Automations: invite status refresh after invitation operations.

## 8. Data Model
- `Player` and nested `ParentContact` with alias decoding.
Source: backend payloads.
Purpose: resilient rendering and edits.
Format: Codable with alternate key decoding.
Constraints: backend role/scope and field constraints.

## 9. Business Rules
- Invite status endpoint queried per-player detail.
- Parent deletion uses dedicated endpoint and refreshes player data.
- Player list is paginated.

## 10. State Machine
- Player states: created/updated/deleted.
- Invite states: none/pending/accepted/cancelled/expired.
- Invalid transitions: editing deleted player record.

## 11. UI Components
- Players list/search.
- Create/edit sheets.
- Player detail sections.
- Invite and parent-management sheets.

## 12. Routes / API / Handlers
- Native navigation in players module.
- API: players CRUD, invitation status/invite, parent unlink.

## 13. Persistence
- Client: local state and selected player models.
- Backend: player and related invite/contact relations.

## 14. Dependencies
- Upstream: team scope and auth role checks.
- Downstream: training/matchday attendance and messaging context.
- Cross-repo: parity with web roster feature.

## 15. Error Handling
- Validation: local and server-side checks.
- Network: alerts for failed operations.
- Missing data: safe fallback when detail dependencies fail.
- Permissions: backend forbidden response handling.
- Current vs expected: error reasons are mostly plain text.

## 16. Security
- Access control: role-based tab exposure and backend scope checks.
- Data exposure: roster data unavailable to non-privileged roles.
- Guest rules: no access.

## 17. UX Requirements
- Feedback: clear mutation status and invite status cues.
- Empty states: no players available.
- Loading: pagination and detail loading indicators.
- Responsive: native forms optimized for small screens.

## 18. Ambiguities & Gaps
- Observed
- Alias-heavy decoding is required for player payloads.
- Inferred
- API contract normalization is still in progress.
- Missing
- Canonical payload versioning in client docs.
- Tech debt
- Detail screen has broad responsibilities and many data dependencies.

## 19. Recommendations
- Product: define final invite lifecycle visualization.
- UX: simplify detail sections with collapsible groups.
- Tech: centralize player normalization logic across iOS modules.
- Security: keep invite actions rate-limited server-side.

## 20. Acceptance Criteria
1. Admin/coach can CRUD players on iOS.
2. Invite and parent unlink actions function correctly.
3. Unauthorized roles cannot access players tab.
4. Failure states are visible without app crash.

## 21. Test Scenarios
- Happy path: create player and send invite.
- Permissions: parent has no player management access.
- Errors: invitation status endpoint failure.
- Edge cases: player payload using legacy keys only.

## 22. Technical References
- `izifoot/Features/Players/PlayersHomeView.swift`
- `izifoot/Features/Players/PlayerDetailView.swift`
- `izifoot/Core/Models/APIModels.swift`
