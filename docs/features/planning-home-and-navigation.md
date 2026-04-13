# Planning Home And Navigation

## 1. Summary
- Clear description: Lists trainings and matchdays, supports creation flows, and routes into detail screens.
- User problem solved: Unified mobile planning timeline for daily operations.
- Product value: Entry point to all session-level actions.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Mobile-first access to schedule and quick create actions.
- Target users: all authenticated roles (creation mainly coach/direction).
- Context of use: `PlanningHomeView` tab.
- Expected outcome: clear upcoming session list and direct navigation.

## 3. Scope
Included
- `PlanningHomeView.swift` list and create sheets.
- Navigation to `TrainingDetailView` and `MatchdayDetailView`.

Excluded
- Detail editing logic.

## 4. Actors
- Admin
Permissions: full list and create.
Actions: create training/matchday.
Restrictions: scoped by team context.
- Coach
Permissions: same in managed scope.
Actions: create sessions.
Restrictions: managed-team bounds.
- Parent
Permissions: read-only planning access.
Actions: open session details where permitted.
Restrictions: no creation.
- Player
Permissions: read-only planning access.
Actions: open session details where permitted.
Restrictions: no creation.
- Guest
Permissions: none.
Actions: none.
Restrictions: blocked.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: no tab.
- System
Permissions: fetch and merge trainings/matchdays.
Actions: present sorted planning feed.
Restrictions: dependent on API availability.

## 5. Entry Points
- UI: Planning tab.
- API: trainings and matchday list/create endpoints.

## 6. User Flows
- Main flow: open planning -> view list -> open session detail.
- Variants: create new training/matchday from sheets.
- Back navigation: detail back to planning list.
- Interruptions: fetch errors.
- Errors: creation failure alerts.
- Edge cases: empty planning list.

## 7. Functional Behavior
- UI behavior: grouped list presentation with create actions.
- Actions: refresh list, create session items.
- States: loading, loaded, empty, error.
- Conditions: role controls creation affordances.
- Validations: sheet inputs validated before API calls.
- Blocking rules: duplicate concurrent create operations prevented.
- Automations: none.

## 8. Data Model
- `Training` and `Matchday` codable models.
Source: API responses.
Purpose: planning list and navigation payload.
Format: date/time/team metadata objects.
Constraints: requires normalization for optional fields.

## 9. Business Rules
- Team scope influences list and create requests.
- Creation options available based on role capabilities.
- Detail navigation passes selected model context.

## 10. State Machine
- Page states: loading/ready/error.
- Creation states: idle/submitting/success/failure.
- Invalid transitions: create action by read-only roles.

## 11. UI Components
- Planning list sections.
- Date/competition sheets.
- Navigation links to detail screens.

## 12. Routes / API / Handlers
- Native navigation destinations in planning feature.
- API: `/trainings`, `/matchday` list/create.

## 13. Persistence
- In-memory list state and creation forms.
- Backend persistence in session tables.

## 14. Dependencies
- Upstream: auth and team scope stores.
- Downstream: training/matchday detail features.
- Cross-repo: mirrors web planning home concept.

## 15. Error Handling
- Validation: input checks before create.
- Network: alert with retry option.
- Missing data: graceful empty views.
- Permissions: backend forbidden results shown to user.
- Current vs expected: no shared retry component.

## 16. Security
- Access control: shell auth and backend authorization.
- Data exposure: scoped API results only.
- Guest rules: no access.

## 17. UX Requirements
- Feedback: clear creation success/failure.
- Empty states: informative empty planning view.
- Loading: progress indicators during fetch.
- Responsive: native list adapts to device sizes.

## 18. Ambiguities & Gaps
- Observed
- Create-sheet behavior varies by competition type and role.
- Inferred
- Additional filters may be planned.
- Missing
- Dedicated pagination strategy for large planning histories.
- Tech debt
- Merge/sort logic likely duplicated across platforms.

## 19. Recommendations
- Product: define time-range filters and archive behavior.
- UX: quick actions for frequent session templates.
- Tech: shared contract tests for planning list ordering.
- Security: maintain strict backend role checks despite hidden UI actions.

## 20. Acceptance Criteria
1. Planning list loads scoped trainings and matchdays.
2. Coach/direction can create sessions from mobile UI.
3. Parent/player cannot create sessions.
4. Navigation to details works reliably.

## 21. Test Scenarios
- Happy path: create training then open detail.
- Permissions: parent create button absent and backend denies forced calls.
- Errors: offline create attempt.
- Edge cases: empty list on new team.

## 22. Technical References
- `izifoot/Features/Planning/PlanningHomeView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
