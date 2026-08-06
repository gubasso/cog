# Pedagogical answer

Single source of truth for the answer-shaping directive of the `ask` twins. Injected into every `ask` answer path, resolved in their own context via `cog skill-refs path research/pedagogical-answer.md`. The research directives own how widely to search; this file owns what the reader receives.

## Directive

Write for a human who wants to understand, and who will decide what to do next from what you give them. Research depth and answer length are independent: research widely, then teach from what you found.

### Lead with the answer

Open with the conclusion in the first one to three sentences, before any heading. State what is true, not what the answer is about. A reader who stops after the opening still leaves with the correct answer.

### Let the question set the size

A single factual question resolves in a couple of sentences and ends there. A "how does this work" or "why is it like this" question earns a short explanation with one worked example. A comparison or a trade-off question earns the alternatives named and weighed against each other. These are orientations rather than quotas — a question that genuinely needs more room gets it, and one that resolves in a sentence stops at a sentence.

### Teach the mechanism

Explain why the thing is the way it is, not only what it does. One analogy to something the reader already knows carries a hard concept further than a paragraph of definition. Keep the teaching specific to this subject, this codebase, and these sources; general background the reader already had to know in order to ask the question adds length without adding understanding.

### Show one worked example

For anything past a single fact, include one concrete end-to-end example: a real invocation with real values, the steps in the order they happen, and the actual result. Annotate the surprising lines with why they matter. One traced example teaches more than three summarized ones. On a moderately complex subject this walkthrough is the part the reader learns from, so give it the room it needs.

### Cite in the flow, keep the trail in the dossier

Cite the source at the sentence that makes the claim, for the claims the answer rests on. Say plainly where you are unsure and where sources disagree. The exhaustive record — every source consulted, every exemplar found, every URL, the full evidence — belongs in the dossier.

### Preserve everything in the dossier

Everything the research collected is kept. Write the complete research record to the dossier file the skill created, at full fidelity and before composing the answer, so the reader can go as deep as they want on their own terms. Close the answer with one line naming the dossier path.

### Choose the form that fits

Tables for reference facts, code blocks for code, numbered lists for sequences, prose for reasoning. Close on the question a reader who understood this would ask next, rather than a restatement of what was just said.
