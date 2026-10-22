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

## Training summary PDF

Coaches and direction can use “Générer le résumé de la séance” near the date, including for cancelled sessions. The button displays “Génération du PDF…” while downloading and is disabled during loading, saves and drill reordering. Editors are modal: dismiss or save them before exporting; the summary always uses saved server data.

- Contract: authenticated `GET /trainings/:id/summary.pdf?timeZone=Europe%2FParis`, no request body. Uses existing Bearer token and active team headers.
- Success: binary `application/pdf` containing date, hours, actual recorded present players and attached exercises in saved order, each with full title and description. Attached exercises have no completion flag; attendance intentions are excluded.
- The downloaded PDF opens a large preview sheet titled “Résumé de la séance”, with “Fermer” on the left and “Partager le PDF” on the right. Native PDFKit displays the document with automatic scaling, continuous vertical scrolling and pinch zoom. The share button opens the native share sheet (including Save to Files) above the preview; closing sharing returns to the same preview. Both use the same local file without another API request. Temporary files use complete file protection and are removed only when the preview closes. An unreadable or empty PDF displays “Impossible d’afficher le PDF.” and disables sharing. Requests bypass the local response cache; server responses are private/no-store.
- Errors: 400 invalid timezone, 401 expired session (existing sign-in handling), 403 access denied, 404 missing training and 500 generation failure remain recoverable with the same button. Invalid/non-PDF successful responses are rejected.
- Manual acceptance: export a saved session and cancelled session; verify accented names, exercise order, long descriptions, empty attendance/exercises, Europe/Paris timezone, native sharing/cancel, network failure/retry and restricted-role visibility. Export must remain disabled until saves/reorder complete.

### Verification

The standalone networking check compiles the production API client against a stub URL protocol and verifies PDF bytes, authentication/team headers, cache bypass, malformed payload rejection, generation errors and session expiry:

```sh
swiftc -module-cache-path /tmp/izifoot-summary-swift-cache izifoot/Core/Networking/APIClient.swift tests/TrainingSummaryDownloadChecks.swift -o /tmp/check-training-summary
/tmp/check-training-summary
```

Swift syntax parsing and this networking check pass. Full iOS compilation and simulator share-sheet checks require a full Xcode installation; this environment only has Command Line Tools.

## Training observations

Training Information includes an optional multiline “Observations” editor, using the existing schedule-edit permissions. Saved text appears in full after the schedule in the Information card, including for readers. Empty values display “Aucune observation”. Accents and line breaks remain unchanged; there is no client-side length limit.

`Training.observations` decodes as an optional string, including older responses omitting the key. `createTraining` and `updateTraining` accept optional observations. An omitted update leaves existing observations unchanged; the Information editor always sends its string and sends an empty string to clear the field. Status-only updates omit observations. The existing PDF endpoint includes saved observations without a new query parameter.

The modal editor blocks PDF access while editing. “Enregistrer” awaits success before dismissing. A failed save keeps the draft and displays a retry message. Closing explicitly confirms abandonment of unsaved changes; swipe dismissal is disabled. Saving disables all fields and dismissal. PDF help text states that only saved information is included.

Verification: unsigned Debug iPhoneOS arm64 build passes with Xcode (explicit `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`); Swift syntax parsing passes; decoding checked with absent/null/empty/multiline accented observations. The existing production API client PDF networking check passes (including auth, team scope, PDF validation and errors). Manual device acceptance remains: save/reopen multiline text, clear/reopen, retry failed save, discard confirmation, inspect generated PDF, and compare coach/reader/cancelled-session permissions with schedule editing.

## PDF preview sheet verification

The preview uses the existing PDF endpoint unchanged. Verify a multipage document, scrolling, pinch zoom, toolbar accessibility labels, Share then Cancel returning to the preview, repeated sharing without downloading again, Close/swipe cleanup, and generation error/retry. The unreadable-document fallback keeps Close available and disables Share. No persistence or permission changes.

Validation: unsigned Debug iPhoneOS arm64 build and Swift syntax parsing pass. UX code review passes; simulator/device visual and sharing acceptance remains manual.
