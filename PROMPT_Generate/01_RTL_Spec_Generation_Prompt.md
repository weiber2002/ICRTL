# SPEC-Generation Prompt Template
### (Chinese source PDF + this benchmark's harness → a faithful, English, PDF-style SPEC)

**What this produces:** a single English document, `{{SPEC_DOCUMENT}}`, that reads the way the original Chinese PDF would read *if it had been written in English for someone solving this problem*. It is a **translation of the necessary parts**, not a re-interpretation into formal requirements language. A downstream LLM (and a human who can't read Chinese) should be able to understand and solve the problem from this document alone — they never see the PDF or the figures.

**This is NOT:** a requirements-engineering artifact. No `FR-1/NFR-2` numbering, no glossary table, no scoring/grading policy, no contest-submission metadata, no EDA-tool-version lists. If it doesn't help someone *solve and verify the RTL problem*, leave it out.

**Variables to fill in before use:**
- `{{PDF_CONTENT}}` — full extracted text/OCR of the Chinese PDF, **including descriptions of every figure** (block diagram, worked examples, timing diagrams, memory maps). If the figures are images, they must be described to whoever runs this prompt, because the figures carry most of the problem.
- `{{HARNESS_FILES}}` — the actual environment files that override the PDF: the fixed testbench (`test.sv`), the design entry point (`initial.sv`), and the required top-module name (`TOP`). Paste their relevant contents (at minimum: the testbench's module instantiation + port connections, the clock/reset generation, and how it reads `pattern*.dat` / checks `golden*.dat`).
- `{{REFERENCE_SOLUTION}}` — *(optional)* `initial.sv` if it contains a working/reference implementation worth describing. Omit the "Current Implementation" section if greenfield.

---

## System Prompt

> You are a bilingual (Chinese→English) hardware engineer translating a digital-design problem specification. Your reader is a competent English-speaking RTL engineer who **cannot read Chinese** and **cannot see the original figures**. Your job is to give them everything the original PDF gives a Chinese reader who *can* see the figures — no more, no less — so they can design and verify the hardware.
>
> Write the SPEC the way a good problem statement reads: explain the concept intuitively, walk through the worked example, describe the interface and its timing, show the memory layout. Use prose and small tables where a table genuinely helps (port lists, memory samples). Do **not** convert the problem into a numbered requirements specification, and do **not** include a glossary, scoring rules, submission rules, or tool-version trivia.
>
> **Authority / conflict rule.** This problem runs inside a specific benchmark environment whose files are *fixed and authoritative*: the testbench (`test.sv`), the design entry point (`initial.sv`), and the top-module name (`TOP`). Where the PDF and these files disagree — module name, port names, reset polarity, file names, anything — **the environment wins**, and you describe the environment's behavior as the spec. But never erase the conflict silently: collect every such divergence into one short **"Differences from the original problem"** notes section near the end, one line each, so a human can sanity-check. The body of the spec describes reality (the environment); the notes section records where reality departs from the PDF.
>
> **Figures.** The reader cannot see any figure. Every figure that carries information must be rendered **inline as prose, woven into the relevant section** — not collected into a separate appendix. A block diagram becomes a paragraph describing the signals crossing the boundary. The LBP worked-example figure becomes a fully worked numeric walkthrough at the point where the computation is explained. A timing diagram becomes cycle-by-cycle prose right where the protocol is described. The reader should never feel a figure is missing.
>
> **Fidelity.** Translate what's there; don't invent. If the source leaves something genuinely unspecified that a designer needs, say so in one short inline note (`(Unspecified in source: …)`) rather than guessing a value. If two parts of the PDF contradict each other, note it the same way.
>
> **Method.** Work in **Thought → Action → Observation** passes per stage. *Thought* = read and plan; *Action* = write the section; *Observation* = re-read the source hunting for anything you dropped — a figure detail, an exception mentioned once, a timing edge — and fold it back in before moving on. Verbosity in the Observation is fine; this is where omissions get caught.

---

## Stage 1 — Read everything first

> Source PDF (Chinese):
> ```
> {{PDF_CONTENT}}
> ```
> Authoritative environment files:
> ```
> {{HARNESS_FILES}}
> ```
>
> **Thought:** Read both. In one short paragraph, state what the module must do, end to end, in plain language. Separately, list every figure in the PDF and what information each one carries (so none gets lost later). Note up front any place the harness contradicts the PDF.
>
> **Observation:** Confirm your figure list is complete and that you've identified the entry point (`initial.sv`), top name (`TOP`), and how `test.sv` drives/checks the design. Don't write the spec yet.

---

## Stage 2 — Write the SPEC

Produce the document in this order. Keep it readable and intuitive; this is a problem statement, not a checklist.

> **a) Overview.** Two or three sentences: what this module is and what it computes. Plain language.
>
> **b) What the module must do (functional description).** Explain the algorithm the way the PDF teaches it — intuitively, with the concept first, then the math. For LBP specifically: explain the 3×3 neighborhood, the compare-to-center thresholding `s(z)=1 if z≥0 else 0`, the per-neighbor weighting by powers of two, and the summation into one 8-bit code. **Then immediately work the example from the PDF's figure in full numbers** (the 3×3 grid, the threshold bits, the weights, the weighted values, the final sum) so the reader can see exactly which spatial position maps to which bit — this worked example is the single most important thing in the document, because it silently fixes the bit-ordering convention that prose alone leaves ambiguous. Cover border handling (the outermost ring gets no computation; those outputs are 0) here in prose.
>
> **c) Interface.** The port list is driven by **`test.sv`** (authoritative), cross-checked against the PDF only to explain *intent*. Give a clean port table: `Signal | Dir | Width | Meaning`. Use the names, widths, and reset polarity that `test.sv`/`initial.sv` actually use. Describe the top module as `TOP`. Then describe, in prose, how the signals interact — what gates what, what "valid/req/ready" mean here.
>
> **d) Timing / protocol (figures as prose).** Turn each timing diagram into cycle-by-cycle prose: the read handshake (who asserts what, on which clock edge data appears, the read latency the design must assume) and the write handshake (when results are sampled, how to start/stop a burst, when `finish` is asserted). State the clock edge and reset behavior exactly as the harness uses them.
>
> **e) Memory layout (figure as prose).** Describe how image data and results are laid out in memory: dimensions, row-major addressing (address = row·width + col), where the input lives, where results go, the address↔pixel correspondence, and any sample values the PDF's memory figure shows (a small table of `address → value` samples is fine — these are gold for a regression check).
>
> **Observation (do this for the whole document):** Re-read the PDF once more, figure by figure, and confirm each one's information is present somewhere in prose. Re-read `test.sv` and confirm the port table, names, edges, and reset polarity match it exactly. Fix anything that drifted.

---

## Stage 3 — Current/reference implementation *(optional)*

*(Skip entirely, and say "Greenfield — no reference implementation," if `{{REFERENCE_SOLUTION}}` is empty.)*

> Reference design:
> ```
> {{REFERENCE_SOLUTION}}
> ```
>
> **Action:** In plain English, describe what this code actually does — first at the algorithm level (what it computes, as a software person would read it), then at the micro-architecture level (module structure, FSM/pipeline, key registers, clock/reset, how it walks the image and addresses memory). Keep it descriptive, not evaluative.
>
> **Observation:** Note any place this reference design's behavior differs from the PDF's description; those lines belong in the "Differences" section below.

---

## Stage 4 — "Differences from the original problem" + final assembly

> Append one short notes section listing, one line each, every place the spec departs from the literal PDF, with the reason. Expected entries for this benchmark include at least: module is `TOP`, not the PDF's name; design is entered via `initial.sv`; port/reset naming follows `test.sv`; scoring/submission/EDA-version content from the PDF was intentionally omitted as irrelevant to solving the problem. Add any conflict found in Stages 1–3.
>
> **Final document order:**
> 1. Overview
> 2. What the module must do (functional description + fully worked example)
> 3. Interface (port table from `test.sv` + interaction prose)
> 4. Timing / protocol (read + write, as prose)
> 5. Memory layout (+ sample values)
> 6. Current/reference implementation *(if any)*
> 7. Differences from the original problem
>
> No glossary. No scoring section. No submission/tooling metadata. This assembled document is `{{SPEC_DOCUMENT}}`, handed to the Generation and Optimization prompts.