# Drills Home And Drill Detail

## 1. Summary
- Clear description: Drill listing, creation, and detail display/editing in native SwiftUI.
- User problem solved: Coaches can manage exercise catalog on mobile.
- Product value: Enables session preparation away from desktop.
- Repository: `izifoot-ios`.
- Status: existing (diagram editor parity partial).

## 2. Product Objective
- Why it exists: Core training content should be manageable from mobile.
- Target users: admin/coach.
- Context of use: drills tab and drill detail screen.
- Expected outcome: browse and create drills with core metadata.

## 3. Scope
Included
- `DrillsHomeView.swift` list/pagination/create.
- `DrillDetailView.swift` detail read and edits where implemented.

Excluded
- Full visual diagram editing parity with web.

## 4. Actors
- Admin
Permissions: full drill operations.
Actions: create/browse/edit drills.
Restrictions: scope.
- Coach
Permissions: same in managed scope.
Actions: same.
Restrictions: scope.
- Parent
Permissions: tab hidden.
Actions: none.
Restrictions: no access.
- Player
Permissions: tab hidden.
Actions: none.
Restrictions: no access.
- Guest
Permissions: none.
Actions: none.
Restrictions: blocked.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: blocked.
- System
Permissions: paginated fetch and local form handling.
Actions: persist drill changes.
Restrictions: depends on backend validation.

## 5. Entry Points
- UI: drills tab and navigation links to drill detail.
- API: drills list/detail/create/update/delete as implemented.

## 6. User Flows
- Main flow: open drills tab -> search/list -> open detail.
- Variants: create drill via sheet.
- Back navigation: detail back to list.
- Interruptions: create/update request failures.
- Errors: alerts for API failures.
- Edge cases: empty drill list.

## 7. Functional Behavior
- UI behavior: list pagination and form sheet for creation.
- Actions: create drill and inspect details.
- States: loading, loaded, creating, error.
- Conditions: role capability (`canEditSportData`).
- Validations: required fields before create.
- Blocking rules: disable save while request in progress.
- Automations: none.

## 8. Data Model
- `Drill` model.
Source: drills endpoints.
Purpose: render catalog and detail fields.
Format: codable struct with metadata.
Constraints: backend scope.

## 9. Business Rules
- Only authorized sport-edit roles can mutate drills.
- Pagination uses backend pagination metadata.
- Detail reload required after some mutations.

## 10. State Machine
- List states: loading/ready/error.
- Creation states: idle/submitting/success/failure.
- Invalid transitions: open detail for missing drill id.

## 11. UI Components
- Drill list.
- Create drill sheet.
- Drill detail view.

## 12. Routes / API / Handlers
- Native navigation in drills module.
- API: `drills`, `drill(id:)`, `createDrill` and related methods.

## 13. Persistence
- Client: local list and form state.
- Backend: drill table and related diagrams.

## 14. Dependencies
- Upstream: auth and role capability.
- Downstream: training detail drill assignment.
- Cross-repo: web has richer diagram tooling.

## 15. Error Handling
- Validation: local form errors.
- Network: alert states.
- Missing data: fallback for missing drill records.
- Permissions: backend forbidden.
- Current vs expected: limited offline support.

## 16. Security
- Access control: role-based tab gating and backend checks.
- Data exposure: scoped fetches.
- Guest rules: no access.

## 17. UX Requirements
- Feedback: clear creation/save results.
- Empty states: no drills available.
- Loading: progressive pagination indicator.
- Responsive: native list/detail responsiveness.

## 18. Ambiguities & Gaps
- Observed
- Diagram editing parity is not complete in iOS.
- Inferred
- Mobile tactical editor is planned but not finished.
- Missing
- Full drill-diagram creation workflow.
- Tech debt
- Divergence risk between web and iOS drill capabilities.

## 19. Recommendations
- Product: define minimum mobile tactical feature set.
- UX: provide richer filtering and tags.
- Tech: align drill model handling with shared contracts.
- Security: keep scope checks server-side for every mutation.

## 20. Acceptance Criteria
1. Coach/direction can list and create drills.
2. Drill detail loads correctly.
3. Role-restricted users cannot access drill tab.
4. API failures are handled without crashes.

## 21. Test Scenarios
- Happy path: create drill and view detail.
- Permissions: parent does not see drill tab.
- Errors: create request fails.
- Edge cases: empty first page.

## 22. Technical References
- `izifoot/Features/Drills/DrillsHomeView.swift`
- `izifoot/Features/Drills/DrillDetailView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
