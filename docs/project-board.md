# Project board

Project 4 of the SlidePilot organization is the live overview of all work. It answers "what is done, what is in progress, what can start now and what waits for whom" without a separately maintained list.

## How the state is stored
- **Status** (Backlog, In Progress, In Review, Done): set by Claude and by GitHub (Done on merge), see the `implement-issue` skill.
- **Blocked by another issue:** GitHub's native issue dependencies ("blocked by"). An issue is unblocked automatically when its blockers close.
- **Waiting for a decision of the product owner** (deviation, proposal, prototype acceptance): label `needs-decision`.
- There is no extra status such as "Ready" or "Waiting": it would duplicate the dependencies and go stale. An issue that was started and then becomes blocked stays In Progress.

## Views
| View | Layout | Filter |
|---|---|---|
| Phase 1 … Phase 5 | Board, columns by Status | `milestone:"Phase 2 – Presenting"` (one view per milestone) |
| Ready to start | Table | `is:open -is:blocked -label:needs-decision status:Backlog` |
| Waiting for you | Table | `is:open label:needs-decision` |
| Blocked | Table | `is:open is:blocked` |

The `is:blocked` qualifier must be checked against GitHub's project filter syntax when the views are created; adjust this table if it differs.
