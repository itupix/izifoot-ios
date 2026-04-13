# Matchday Detail And Sharing

## 1. Summary
- Clear description: Matchday detail operations including attendance, match management, share links, and planning linkage.
- User problem solved: Coaches can control competition day from mobile.
- Product value: High-impact operational control during matchday.
- Repository: `izifoot-ios`.
- Status: existing (advanced workflows partial and complex).

## 2. Product Objective
- Why it exists: Matchday execution requires rapid updates and communication.
- Target users: admin/coach primarily.
- Context of use: `MatchdayDetailView`.
- Expected outcome: coherent matchday, matches, and shared output.

## 3. Scope
Included
- Matchday metadata updates and deletion.
- Attendance per player and team absence toggles.
- Match create/update/delete operations and summary refresh.
- Share link generation and planning linkage actions.

Excluded
- Public token page rendering (separate feature doc).

## 4. Actors
- Admin
Permissions: full operations.
Actions: all matchday/match mutations and share.
Restrictions: scope-bound.
- Coach
Permissions: same in managed teams.
Actions: same.
Restrictions: scope-bound.
- Parent
Permissions: read-only in dedicated contexts.
Actions: none here.
Restrictions: no structural edits.
- Player
Permissions: read-only in dedicated contexts.
Actions: none here.
Restrictions: no structural edits.
- Guest
Permissions: none.
Actions: none.
Restrictions: no access.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: no access.
- System
Permissions: loads club/players/attendance/matches/summary/plannings.
Actions: orchestrates dependent mutations.
Restrictions: API contract complexity.

## 5. Entry Points
- UI: navigation from planning list to matchday detail.
- API: `/matchday*`, `/matches*`, `/attendance`, `/plannings*`.

## 6. User Flows
- Main flow: open matchday -> update attendance/matches -> share link.
- Variants: open sheet editors for schedule and match edits.
- Back navigation: return to planning tab.
- Interruptions: mutation conflicts and refresh mismatch.
- Errors: displayed in alerts and sheet error blocks.
- Edge cases: remove and recreate full match schedule.

## 7. Functional Behavior
- UI behavior: multi-sheet workflow with nested editors.
- Actions: create/update/delete matchday and matches, set absences, share.
- States: loading, editing, persisting, sheet-specific error.
- Conditions: role/scope authorization.
- Validations: payload normalization before updates.
- Blocking rules: interactive dismiss disabled while persisting in some sheets.
- Automations: summary and related list refresh after operations.

## 8. Data Model
- `Matchday`, `Match`, `AttendanceRow`, matchday summary payload.
Source: multiple API endpoints.
Purpose: comprehensive matchday operation state.
Format: codable models and in-view structures.
Constraints: backend scope and relation constraints.

## 9. Business Rules
- Team absence toggles affect summary context.
- Share call returns tokenized URL for external read.
- Match operations maintain relation to matchday.

## 10. State Machine
- Matchday states: active/shared/deleted.
- Match states: planned/played/cancelled.
- Share state: unshared/shared.
- Invalid transitions: mutate deleted matchday.

## 11. UI Components
- Matchday detail sections.
- Attendance and schedule editor sheets.
- Share sheet.
- Match editor sheets.

## 12. Routes / API / Handlers
- Native handlers in `MatchdayDetailView`.
- API: `matchday.byID/summary/share/teamsAbsence`, `matches.*`, `attendance`.

## 13. Persistence
- Client: rich local state and derived view models.
- Backend: plateau, match, attendance, planning models.

## 14. Dependencies
- Upstream: planning list and team scope.
- Downstream: public matchday and stats features.
- Cross-repo: closely mirrors web matchday operations.

## 15. Error Handling
- Validation: payload guards and sheet-level checks.
- Network: alerts and inline sheet error blocks.
- Missing data: fallback loading paths.
- Permissions: forbidden operations surfaced.
- Current vs expected: high-complexity flow needs more granular error taxonomy.

## 16. Security
- Access control: protected by auth and backend scope.
- Data exposure: scoped by active team and role.
- Guest rules: no access.

## 17. UX Requirements
- Feedback: visible persistence indicators per sheet.
- Empty states: no matches configured.
- Loading: initial and incremental refresh indicators.
- Responsive: native sheets and lists adapt to device.

## 18. Ambiguities & Gaps
- Observed
- `MatchdayDetailView` contains broad orchestration responsibilities.
- Inferred
- Feature is under active iteration and parity tuning.
- Missing
- Formal UI state diagram for all sheet interactions.
- Tech debt
- Large view complexity raises regression risk.

## 19. Recommendations
- Product: define minimal matchday action set for mobile-first scenarios.
- UX: simplify sheet stack and add clear save checkpoints.
- Tech: refactor into dedicated sub-view models.
- Security: keep strict scope checks server-side for every mutation.

## 20. Acceptance Criteria
1. Admin/coach can manage matchday metadata, attendance, and matches.
2. Share action returns usable public link.
3. Errors in subflows do not crash screen.
4. Unauthorized users cannot perform restricted mutations.

## 21. Test Scenarios
- Happy path: update attendance and create match then share.
- Permissions: non-admin/coach edit attempts denied.
- Errors: share endpoint failure.
- Edge cases: delete matchday with existing matches.

## 22. Technical References
- `izifoot/Features/Planning/MatchdayDetailView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
