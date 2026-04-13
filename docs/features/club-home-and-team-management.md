# Club Home And Team Management

## 1. Summary
- Clear description: Direction-focused club screen for club metadata, teams list, coaches view, and team creation.
- User problem solved: Admins manage organization from mobile.
- Product value: Necessary setup for operational modules.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Club/team setup is prerequisite for scoped operations.
- Target users: direction role.
- Context of use: `ClubHomeView`.
- Expected outcome: maintainable club profile and teams.

## 3. Scope
Included
- Club fetch and rename.
- Team list and team creation.
- Coach list display.

Excluded
- Full account invitation workflow parity with web.

## 4. Actors
- Admin
Permissions: full access.
Actions: rename club and create teams.
Restrictions: own club only.
- Coach
Permissions: no direct club screen access in role design.
Actions: none.
Restrictions: blocked.
- Parent
Permissions: none.
Actions: none.
Restrictions: blocked.
- Player
Permissions: none.
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
Permissions: fetches club/teams/coaches in parallel.
Actions: updates UI sections.
Restrictions: backend role/scope checks.

## 5. Entry Points
- UI: club tab or chrome destination for direction users.
- API: clubs, teams, and coaches endpoints.

## 6. User Flows
- Main flow: open club home -> inspect data -> rename or create team.
- Variants: switch active team through scope picker.
- Back navigation: return to previous tab.
- Interruptions: update/create errors.
- Errors: alert-based feedback.
- Edge cases: club with no teams/coaches.

## 7. Functional Behavior
- UI behavior: sectioned cards/lists for club, teams, coaches.
- Actions: mutate club name and team list.
- States: loading, ready, mutating, error.
- Conditions: direction role.
- Validations: required text inputs.
- Blocking rules: disable submit during request.
- Automations: none.

## 8. Data Model
- `Club`, `Team`, `Coach`.
Source: corresponding endpoints.
Purpose: admin display and mutation.
Format: codable structs.
Constraints: backend validations.

## 9. Business Rules
- Only direction can mutate club/team settings.
- Team creation requires category and format.
- Coach list derived from users and invitation context.

## 10. State Machine
- Screen states: loading/ready/error.
- Mutation states: idle/saving/success/failure.
- Invalid transitions: coach attempting mutation.

## 11. UI Components
- Club info card.
- Rename and create-team sheets.
- Team and coach lists.

## 12. Routes / API / Handlers
- Native handlers in `ClubHomeView`.
- API: `/clubs/me`, `/clubs/me/coaches`, `/teams`.

## 13. Persistence
- Client: local state for fetched lists and forms.
- Backend: club/team/user/account invite models.

## 14. Dependencies
- Upstream: auth role and scope context.
- Downstream: planning/player modules depend on team structure.
- Cross-repo: web admin feature has broader invitation coverage.

## 15. Error Handling
- Validation: local checks for empty fields.
- Network: alert errors.
- Missing data: empty states displayed.
- Permissions: backend 403 enforced.
- Current vs expected: iOS admin parity with web invitations is partial.

## 16. Security
- Access control: role gating in navigation and backend.
- Data exposure: admin data not visible to non-direction roles.
- Guest rules: blocked.

## 17. UX Requirements
- Feedback: clear save and failure messages.
- Empty states: no teams/no coaches.
- Loading: progress indicator.
- Responsive: native sheet UX.

## 18. Ambiguities & Gaps
- Observed
- iOS club feature currently narrower than web (invitations).
- Inferred
- Parity work is planned.
- Missing
- Account invitation management UI.
- Tech debt
- Potential drift with web admin capabilities.

## 19. Recommendations
- Product: align minimum admin capabilities across clients.
- UX: add invitation list/create flow on iOS.
- Tech: share admin domain contracts in one spec.
- Security: audit admin actions for mutation traceability.

## 20. Acceptance Criteria
1. Direction can view and update club basics.
2. Direction can create team from iOS.
3. Non-direction users cannot access club admin actions.
4. Error states are surfaced cleanly.

## 21. Test Scenarios
- Happy path: rename club and create team.
- Permissions: coach blocked from club admin.
- Errors: duplicate team name.
- Edge cases: empty club without teams.

## 22. Technical References
- `izifoot/Features/Club/ClubHomeView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
