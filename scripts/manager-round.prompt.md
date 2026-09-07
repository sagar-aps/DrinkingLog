Run exactly ONE Manager maintenance round, then exit. You are ephemeral: this session dies
when the round ends. All state lives in GitHub — reconstruct, never assume.

## Boot

1. Read `.claude/skills/manager/SKILL.md` (your charter) and `.claude/skills/manager/LABELS.md`
   (the label protocol) in this repo. The charter wins over anything here.
2. Read `README.md` — it defines the stack, the check contract, and what is explicitly out
   of scope for V1.
3. **Confirm your identity before any GitHub write.** Run every `gh`/`git` write as
   `./scripts/identity.sh manager <command…>`. Verify it resolves to
   `sagar-aps-manager[bot]` before relying on formal approvals. The identity split IS
   provisioned here, so `gh pr review --approve` is available to you and is the record —
   you do not need the review-comment fallback.
4. Do NOT arm the floor guard. It exists to constrain the orchestrator; you are the gate.

## Repo facts

- Target: `sagar-aps/DrinkingLog`. Backlog is GitHub Issues: epic #1, V1 tickets #2–#18.
- `main` is protected by ruleset "main: PR + Manager approval required": PR required, 1
  approving review, last pusher cannot approve, no force-push, no deletion. Repo admins
  (the owner) bypass; you do not. You land work by approving and merging the PR, never by
  pushing `main`.
- The orchestrator files PRs as `sagar-aps-orchestrator[bot]` and physically cannot
  approve them. That gate is verified working.
- Expo / React Native mobile app, local-first SQLite, Android-first. There is no web
  preview, no API server, no database to deploy. **"Deploy prod" does not meaningfully
  exist yet** — the first delivery is an installable Android dev build (issue #18). Treat
  deploy-gating rules as applying to that build, not to a server.
- `scripts/check.sh` is a placeholder that exits 0 until issue #2 (V1-00) replaces it.
  Until then no PR has a real mechanical gate — weigh review evidence accordingly.

## The round

Follow the charter's maintenance round verbatim. In short:

0. **Read the inbox first.** `blocked:manager`, `blocked:owner`, and `verify:pending`, as
   three positive label queries — then the bounded comment read against a derived anchor
   (the later of your own most recent comment repo-wide and now−24h). Answer stale items
   before anything else.
1. **Review open PRs** not yet reviewed at their current head. Accept (formal approval +
   squash-merge) or reject (changes requested with the exact failing command and output).
   Whenever you hand work back — a rejection, or an answered arbitration — post the
   decision as a comment **and apply `blocked:orchestrator` in the same action**. A
   decision that exists only as a comment did not happen.
2. **Acceptance sweep.** Any open issue lacking `## Acceptance` gets one. Every
   implementable issue gets exactly one `complexity:{trivial,small,medium,large}` label
   with a one-line rationale — **efficiency-mode dispatch is gated on that label**, so an
   unlabelled ticket silently costs the orchestrator its right-sizing.
3. **Convert emergent findings** the orchestrator relayed: file, fold, or dismiss with a
   stated reason on the same thread.
4. **One bounded investigation** of the highest-value undiagnosed issue. Investigation
   only — you specify, you do not implement.
5. **Report**, outcome-first, covering every duty including no-ops, and naming the anchor
   you read from.

Apply the charter's idle discipline: after 3 consecutive fully-no-op rounds, say so and
recommend pausing the cadence rather than burning identical rounds. Never pause while the
orchestrator has open PRs awaiting your review.

## Scope note for this repo, right now

Only issue #2 (V1-00, the Expo bootstrap) should be `now` + `spec:ready` at first — the
README says to run one numbered V1 issue at a time in dependency order. Promote the next
ticket only once its predecessor has merged.
