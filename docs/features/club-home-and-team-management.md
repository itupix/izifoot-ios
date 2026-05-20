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
- Coach list display, invitation share sheet, resend, and deletion.
- Coach assignment and removal from team cards.

Excluded
- Full coach-detail parity with the web detail route.

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
- Main flow: open club home -> inspect team names -> add or resend a coach invitation -> open the share sheet with the link and QR -> open a dedicated team sheet to review or edit team details and coach assignments -> manage the coach directory.
- Variants: add a coach from iOS; rename or create team.
- Back navigation: return to previous tab.
- Interruptions: update/create errors.
- Errors: alert-based feedback.
- Edge cases: club with no teams/coaches.

## 7. Functional Behavior
- UI behavior: sectioned lists for club, teams, and coaches with compact `Ajouter` actions in section headers; the team list shows only the team name and opens a dedicated team sheet for details and coach assignments, while both team sheets use explicit field labels, age-category tags, and a format dropdown.
- Actions: mutate club name, team list, coach list, coach invitations, and coach-team assignments.
- States: loading, ready, mutating, error.
- Conditions: direction role.
- Validations: required text inputs.
- Blocking rules: disable submit during request.
- Automations: none.

## 8. Data Model
- `Club`, `Team`, `Coach`, `CoachManagedTeam`.
Source: corresponding endpoints.
Purpose: admin display and mutation.
Format: codable structs.
Constraints: backend validations.

## 9. Business Rules
- Only direction can mutate club/team settings.
- Team creation requires category and format.
- Coach list derived from users and invitation context.
- Coach creation and resend can immediately open a share sheet with the invitation link and QR.
- The team-detail sheet is the primary surface for team metadata and coach assignments.
- The team scope picker is hidden on `Mon club` to avoid conflicting with cross-team administration.

## 10. State Machine
- Screen states: loading/ready/error.
- Mutation states: idle/saving/success/failure.
- Invalid transitions: coach attempting mutation.

## 11. UI Components
- Club info card.
- Rename sheet and create-team sheet using the shared team editor ergonomics.
- Team list with tap-to-open detail sheet.
- Team detail sheet with team metadata, coach assignments, and deletion entrypoint.
- Coach list with resend/delete actions.
- Add-coach sheet.

## 12. Routes / API / Handlers
- Native handlers in `ClubHomeView`.
- API: `/clubs/me`, `/clubs/me/coaches`, `/coaches/:id`, `/coaches/:id/teams`, `/teams`, `/accounts`.

## 13. Persistence
- Client: local state for fetched lists and forms.
- Backend: club/team/user/account invite models.

## 14. Dependencies
- Upstream: auth role and scope context.
- Downstream: planning/player modules depend on team structure.
- Cross-repo: web admin feature remains broader, but iOS now shares the same coach assignment contract.

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
- Empty states: no teams/no coaches/no assigned coach on a team.
- Loading: progress indicator.
- Responsive: native sheet UX.
- Action placement: primary add actions stay in the top-right corner of their associated block to match other admin surfaces.
- Team interactions: tapping a team row opens its dedicated sheet instead of expanding dense inline content in the list.
- Team editor ergonomics: age categories use multi-select tags with contiguous-range validation, and game format uses a dropdown aligned with the web flow.

## 18. Ambiguities & Gaps
- Observed
- iOS club feature still narrower than web for rich coach details.
- Inferred
- Parity work is planned.
- Missing
- Full coach-detail parity with the web route.
- Tech debt
- Potential drift with web admin capabilities.

## 19. Recommendations
- Product: align minimum admin capabilities across clients.
- UX: keep coach assignment anchored to team rows and avoid restoring the club-level team picker.
- Tech: share admin domain contracts in one spec.
- Security: audit admin actions for mutation traceability.

## 20. Acceptance Criteria
1. Direction can view and update club basics.
2. Direction can create team from iOS.
3. Direction can add, assign, unassign, and delete coaches from iOS.
4. Non-direction users cannot access club admin actions.
5. Error states are surfaced cleanly.

## 21. Test Scenarios
- Happy path: rename club, create team, add coach, assign the coach to another team, then remove one assignment.
- Permissions: coach blocked from club admin.
- Errors: duplicate team name.
- Edge cases: empty club without teams; deleting a pending coach; removing the last team from a coach.

## 22. Technical References
- `izifoot/Features/Club/ClubHomeView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
