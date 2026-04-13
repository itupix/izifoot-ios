# Training Detail Operations

## 1. Summary
- Clear description: Training detail screen with attendance, roles, drills, metadata edits, and status updates.
- User problem solved: Coaches can run session operations directly from mobile.
- Product value: Mobile parity for core training workflow.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Coaches need on-field friendly controls for session management.
- Target users: admin/coach primarily.
- Context of use: `TrainingDetailView`.
- Expected outcome: accurate, up-to-date training operational state.

## 3. Scope
Included
- Load training + players + attendance + drills + roles + intents.
- Update training metadata/status.
- Attendance toggles, role assignment, drill add/remove/reorder.

Excluded
- Planning list creation behavior.

## 4. Actors
- Admin
Permissions: full detail editing.
Actions: all operations.
Restrictions: scoped.
- Coach
Permissions: same in managed teams.
Actions: all scoped operations.
Restrictions: scope boundaries.
- Parent
Permissions: read-only context (intent handled elsewhere).
Actions: minimal interactions.
Restrictions: no structural edits.
- Player
Permissions: read-only context.
Actions: minimal interactions.
Restrictions: no structural edits.
- Guest
Permissions: none.
Actions: none.
Restrictions: blocked.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: no screen.
- System
Permissions: orchestrates multi-request loading and synchronization.
Actions: keeps detail sub-sections consistent.
Restrictions: relies on backend contract stability.

## 5. Entry Points
- UI: navigation from planning list.
- API: training, attendance, roles, drills and drill-order endpoints.

## 6. User Flows
- Main flow: open detail -> update session info -> manage participants -> save.
- Variants: assign/remove drills and reorder.
- Back navigation: return to planning tab.
- Interruptions: partial fetch failure per section.
- Errors: mutation errors in sheets/alerts.
- Edge cases: no available players/drills.

## 7. Functional Behavior
- UI behavior: sheet-based editors for attendance, exercises, and metadata.
- Actions: save updates through dedicated API methods.
- States: loading, editing, persisting, error.
- Conditions: role and scope checks.
- Validations: field constraints and id presence.
- Blocking rules: disable controls during persistence.
- Automations: refresh dependent data after writes.

## 8. Data Model
- `Training`, `AttendanceRow`, `TrainingDrill`, `TrainingRoleAssignment`, `Drill`.
Source: endpoint aggregation.
Purpose: complete training operation context.
Format: codable structs in `APIModels.swift`.
Constraints: scope and relation integrity.

## 9. Business Rules
- Attendance updates use dedicated training attendance endpoint.
- Role updates submitted as assignment set.
- Drill order persisted item by item.

## 10. State Machine
- Detail states: loading/ready/error.
- Persist states: idle/persisting/success/failure.
- Training status transitions include planned/cancelled.
- Invalid transitions: save actions without loaded training object.

## 11. UI Components
- Detail header and metadata section.
- Attendance sheet.
- Exercise sheet.
- Role assignment editor.

## 12. Routes / API / Handlers
- Native: `TrainingDetailView` actions.
- API: `trainings.byID`, `trainings.attendance`, `trainings.roles`, `trainings.drills`.

## 13. Persistence
- Client: local state in view model/view.
- Backend: training-linked relational tables.

## 14. Dependencies
- Upstream: planning navigation and team scope.
- Downstream: stats and session execution.
- Cross-repo: aligned with web training detail intent.

## 15. Error Handling
- Validation: local input checks.
- Network: alerts for failed actions.
- Missing data: fallback rendering for absent optional payloads.
- Permissions: backend forbidden responses.
- Current vs expected: limited granular error typing.

## 16. Security
- Access control: auth and backend role checks.
- Data exposure: scoped data loading.
- Guest rules: no access.

## 17. UX Requirements
- Feedback: clear save/progress indicators in sheets.
- Empty states: no players/no drills messaging.
- Loading: section-level progress feedback.
- Responsive: native sheet ergonomics on smaller devices.

## 18. Ambiguities & Gaps
- Observed
- Complex sheet orchestration in one large view file.
- Inferred
- Further modularization needed for long-term maintainability.
- Missing
- Unified conflict-resolution UX for concurrent edits.
- Tech debt
- High coupling between UI state and API response shape.

## 19. Recommendations
- Product: define minimal offline behavior expectations.
- UX: improve section-level retry affordances.
- Tech: split view into smaller components and state reducers.
- Security: preserve strict backend authorization checks.

## 20. Acceptance Criteria
1. Training detail loads all required related data.
2. Admin/coach can update attendance, roles, and drills.
3. Save failures are visible and recoverable.
4. Unauthorized users cannot perform restricted actions.

## 21. Test Scenarios
- Happy path: adjust attendance and roles in one session.
- Permissions: parent cannot edit metadata.
- Errors: drill reorder persistence failure.
- Edge cases: empty roster training.

## 22. Technical References
- `izifoot/Features/Planning/TrainingDetailView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
