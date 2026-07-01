---
name: ten-development-rules
description: Boundary-first, contract-first workflow for planning, restructuring, reviewing, or executing software development tasks. Use when Codex needs to define in-scope vs out-of-scope work, freeze types or interfaces before implementation, sequence work by dependency, isolate new domain logic from shared core, add review and validation loops, or distill concrete project work into reusable engineering principles.
---

# Ten Development Rules

## Default Stance

- Start from scope, not solution shape.
- Prefer explicit contracts over implicit assumptions.
- Build from lower dependencies upward.
- Keep new complexity local until repeated pressure justifies abstraction.
- Treat review, failure handling, and verification as part of delivery.

## Workflow

1. Set the boundary.
   - State what the task solves now.
   - State what it does not solve now.
   - Remove adjacent ideas unless they block the current task.
   - Tighten the scope before implementation if the task boundary is fuzzy.

2. Freeze the contract.
   - Define the types, statuses, routes, inputs or outputs, ownership, or acceptance criteria that other work depends on.
   - Keep shared contracts in one obvious place.
   - Delay broad implementation if the contract is still moving.

3. Sequence by dependency.
   - Build shared foundations before consumers.
   - Let upper layers consume stable lower-layer behavior instead of inventing it.
   - Parallelize only when contracts are stable and file ownership does not overlap.

4. Stage the work.
   - Split large tasks into phases with clear outputs and entry or exit conditions.
   - Use stages such as contract, schema, service, route, UI, review, and verification when helpful.
   - Prefer several small stage boundaries over one oversized feature pass.

5. Isolate new complexity.
   - Put new domain logic in domain-specific files, modules, tables, or services.
   - Protect shared core from speculative reuse.
   - Abstract only after repeated pressure, not in anticipation.

6. Build the review loop.
   - Plan implementation, review, fix, and re-verification as one loop.
   - Define how the change will be checked before calling it done.
   - Update source-of-truth docs when the system meaning changes.

7. Design failure paths.
   - Check timeouts, retries, rollback, idempotency, concurrency, auth, rate limits, and cost controls.
   - Ask what happens when upstreams fail, inputs are partial, or operations race.
   - Treat unhappy paths as first-class behavior.

8. Compress documentation.
   - Write the minimum documentation that restores context quickly.
   - Separate living specs from historical material.
   - Make the default reading order explicit when the repo contains legacy narratives.

9. Verify reality.
   - Prefer checks that can reveal real runtime behavior.
   - Keep smoke tests honest; do not count expected failures as success.
   - Call out what was verified, what was skipped, and what still carries risk.

10. Distill reusable principles.
    - Lift patterns out of feature names when summarizing work.
    - Prefer verbs such as scope, freeze, sequence, stage, isolate, review, and verify.
    - End with a short formula the team can reuse.

## Anti-Patterns

- Do not design the full future system when the current task has a narrower boundary.
- Do not let consumers define contracts that providers have not stabilized.
- Do not abstract early just because two things sound similar.
- Do not treat review or smoke checks as ceremonial.
- Do not write documentation that preserves history but hides current truth.

## Default Summary Formula

Describe the approach as boundary-driven, contract-driven, dependency-ordered, staged, isolated, and closed-loop verified.
