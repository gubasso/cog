# 06 — Appetite and Scope

A unit of work needs a bound, or it grows until it feels finished. This chapter defines that unit, defines the bound, and — the part most methods leave to taste — states when the bound may move and what it takes to move it. The rules are independent of how a project files its plan documents; what the plan zone holds is in [07 — Plan and Slices](./07-plan-and-slices.md).

## The unit of work

A slice is one vertical unit of work: end to end through every layer, small enough to finish inside its appetite, and demonstrable when done.

All three properties are load-bearing. Vertical means the slice crosses every layer rather than completing one, so something is demonstrable at the end; "add the mailer abstraction" fails this and "password reset by email" passes it. Bounded means an appetite was fixed before the design. Demonstrable means completion is an objective condition — named tests pass unskipped — and not a judgment call.

A slice is also the unit of agent context: it is the entry document a session loads, along with the sources it names and nothing else; see [04 — Agent Context](./04-agent-context.md).

## Appetite is a budget, not an estimate

An estimate fixes the scope and asks how long the work will take. When the answer is wrong, the time moves, because scope was what was promised.

An appetite inverts that. It fixes the time and asks how much is worth building inside it. Shape Up states the difference exactly: "Estimates start with a design and end with a number. Appetites start with a number and end with a design." The appetite is decided before the design exists, and it is a statement of what the outcome is worth, not a prediction of effort. Running out of an appetite is therefore not a failed prediction; it is the budget doing its job, and the designed response is to cut scope.

The specific form used here — an appetite fixed before any design exists, in a cycle that is cancelled rather than extended — is Basecamp's. The underlying discipline is about two decades older: DSDM builds a project increment from a fixed timebox, a prioritized and deliberately cuttable scope list, and a guaranteed minimum subset. Where two methods developed independently agree, the rule is not one vendor's preference, and this chapter leans on the overlap.

## What the budget is denominated in

Shape Up denominates the appetite in calendar time for a standard team. That still applies when a human implements the work or when an external date is the real constraint. When an agent implements, calendar time is a poor budget, because agent hours and your hours are unrelated quantities and the scarce resource is your review attention.

| Unit                   | Use when                                          |
| ---------------------- | ------------------------------------------------- |
| Calendar time          | A human implements, or an external date binds.    |
| Human review passes    | An agent implements and review is the bottleneck. |
| Implementation session | Work is dispatched as discrete agent runs.        |

Pick one unit per project and keep it. Whichever it is, the appetite MUST be a number written before the design, or it is not a budget.

## Non-negotiable scope

Some outcomes are not negotiable — a correctness property, a security control, a regulatory requirement, an interface another slice already depends on. Non-negotiable scope does not mean the appetite is unbounded. It means the non-negotiable part is named up front and the appetite sized around it.

DSDM names this part the Must Have, defined as the Minimum Usable SubseT of requirements the project guarantees to deliver, and gives the test: ask what happens if the requirement is not met, and if the answer is that the work is pointless, it is a Must Have. Everything else is negotiable by construction.

So each slice declares two things, not one: a core, which is the non-negotiable outcome and is never cut, and a remainder, which is everything else in scope, ordered so the least valuable is cut first.

```text
  appetite   ├────────────────────────────────────────────────┤   fixed

  well shaped
             ├──── core ────┤──── remainder, ordered ────┤ slack ┤
                             cut from the right when the budget binds
                             the remainder is what funds the guarantee

  unfunded guarantee — mis-shaped, split it
             ├─────────────────────── core ───────────────────────┤
                             nothing left to cut, so the only way to
                             protect the guarantee is to move the budget
```

The remainder is not filler; it is the contingency that makes the guarantee credible. DSDM sizes this explicitly at no more than 60 percent of effort as Must Have, with roughly 20 percent held as deliberate contingency. Those figures are stated for a project increment rather than a single slice, but the discipline scales down, and the checkable form has no percentages in it: a slice whose core alone consumes the whole appetite has no contingency, so its guarantee is unfunded and the slice is mis-shaped. Split it until a core fits with room to spare, or raise the appetite deliberately before the work starts — never after it has begun.

This is the honest answer to non-negotiable scope. You do not protect a guarantee by leaving the deadline open. You protect it by making the guaranteed part small enough that the budget can absorb being wrong.

## Cutting is the first response

When the appetite binds, cut the remainder. Shape Up calls this scope hammering: "Forcefully questioning a design, implementation, or use case to cut scope and finish inside the fixed time box." Two rules keep it honest.

Compare against the baseline, not the ideal. The comparison that decides whether a reduced version ships is against what users have today, not against the version in your head.

Cut scope, never quality. Correctness, tests, and security controls are not the negotiable axis. A slice that ships by dropping its tests has not cut scope; it has moved the cost somewhere it will not be counted. If quality is the only thing left to cut, the slice is mis-shaped and the next section applies.

## When the appetite may change

An appetite that moves whenever it binds is an estimate wearing a different name. An appetite that can never move makes the method dishonest, because sometimes the premise was wrong. The resolution is that a change is allowed, is rare, and is gated on two conditions that MUST both hold: what remains is true core that withstood every attempt to scope hammer it, and it is all downhill — no unsolved problems, no open questions.

```text
the appetite binds
      │
      ▼
cut the remainder ──► anything still outstanding?
      │                          │
      │                          └─ no ──► finished, inside the budget
      ▼ yes
is what remains true core,
survived every attempt to scope hammer it?
      │
      ├─ no ──► it was never core. keep cutting.
      ▼ yes
is it all downhill —
no unsolved problems, no open questions?
      │
      ├─ yes ──► the shaping was sound, the sizing was off.
      │          extend, by the smallest amount that finishes it.
      │
      └─ no  ──► the shaping was wrong, not the sizing.
                 stop, record what was learned, re-shape.
                 a re-shaped slice is a new slice with a new appetite.
```

Downhill is the phase where all unknowns are solved and only execution is left; uphill is the phase where unknowns or unsolved problems remain. Both conditions are checkable, and together they separate the two cases that feel identical from inside the work. A re-shaped slice is a fresh decision to spend, not an extension of the old one — the distinction Shape Up enforces with the circuit breaker, cancelling work that does not ship in one cycle by default instead of extending it by default.

Reaching for the appetite should be the last option, not the first. A trap you anticipated already has a pre-authorized escape recorded in the slice; a trap you did not anticipate goes to the open-questions register. The appetite moves only when neither is enough. The pre-authorized escape is this shelf's addition rather than Shape Up's, which names rabbit holes in the pitch and patches them by deciding the risky part in advance, with the circuit breaker as its escape valve. Deciding the response to each named trap before the work starts is a cheaper valve, and it is what keeps the appetite from being the first lever anyone reaches for.

## Every change is visible

An appetite change MUST be a committed edit to the slice document, carrying one line that names the new figure, which of the two conditions was met, and what was cut before the change was proposed.

Silence is the whole failure mode. An appetite revised in someone's head leaves no trace, so the pattern of revision never becomes visible and the shaping problem behind it is never diagnosed. An appetite revised in a diff is reviewable, greppable, and countable across slices — and a project whose slices routinely extend has learned something about how it shapes work, which it can only learn if the changes are on record. Committed is not the same as frozen; the revision rule for the rest of the slice is in [07 — Plan and Slices](./07-plan-and-slices.md).

## Anti-patterns

- Appetite as estimate: a figure derived from the design rather than fixed before it. It will move every time it binds, because nothing was ever promised except accuracy.
- Unfunded guarantee: a core that fills the entire appetite, leaving nothing to cut.
- Everything is core: a slice where no scope was ever classified as negotiable. This is usually unwillingness to prioritize rather than a genuinely indivisible outcome.
- Quality as the cut: shipping inside the appetite by dropping tests, review, or a security control.
- Silent extension: the appetite changes and no document changes.
- Serial extension: a slice extended more than once. The second request is evidence the work is uphill, whatever the first one claimed.
- Extension instead of re-shaping: buying more time for work that still contains unsolved problems, which spends budget on discovering what shaping was supposed to find.

## A known limitation

A slice is feature-shaped by definition: it is vertical, and it is demonstrable because a user-facing outcome can be demonstrated. That definition has a cost worth stating rather than discovering.

A project that only ever ships feature-shaped increments never spends an increment on an abstraction, because an abstraction has nothing to demonstrate. The design work then happens incidentally, inside slices whose acceptance criteria are about something else, which is the mode where local decisions accumulate into a shape nobody chose. The strategic-versus-tactical framing in [A Philosophy of Software Design](https://web.stanford.edu/~ouster/cgi-bin/book.php) is the fullest statement of why that mode is expensive.

Two answers, and neither is that the objection is wrong. First, the subsystem page is where design-level work is recorded and reviewed, so it does not depend on a slice existing to hold it; see [03 — Subsystem Pages](./03-subsystem-pages.md). Second, a slice MAY be shaped around an abstraction when it still meets the definition — when a named test at the new boundary passes unskipped, "replace the mailer with an interface two callers use" is demonstrable and vertical enough to qualify. What the definition rules out is the slice with no demonstrable end at all, not the slice whose demonstrable end is an interface.

## Sources

- Shape Up, Set Boundaries (appetite, fixed time and variable scope): <https://basecamp.com/shapeup/1.2-chapter-03>
- Shape Up, The Betting Table (circuit breaker): <https://basecamp.com/shapeup/2.2-chapter-08>
- Shape Up, Show Progress (uphill and downhill): <https://basecamp.com/shapeup/3.4-chapter-13>
- Shape Up, Decide When to Stop (scope hammering, baseline, the two extension conditions): <https://basecamp.com/shapeup/3.5-chapter-14>
- DSDM MoSCoW prioritisation (Minimum Usable SubseT, effort split, contingency): <https://www.agilebusiness.org/dsdm-project-framework/moscow-prioritisation.html>
