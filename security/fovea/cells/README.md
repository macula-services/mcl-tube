# Cells — mcl-tube

*Not yet generated.* When the grid is filled (`fovea init .` from
[`macula-io/macula-fovea`](https://github.com/macula-io/macula-fovea) —
96 cells: 16 columns × 6 attributes), fill in this order, which follows the
three distinguishing surfaces named in `landscape.md`:

1. **Retraction first** — `at_rest.confidentiality`, `in_motion.confidentiality`,
   and the `operate.*` cells around `video_clip_retracted_v1`: the gap
   between the retraction fact and the last cached stream is the sharpest
   cell in the grid.
2. **The owner surface** — `operate.authenticity/accountability`,
   `in_use.confidentiality`: the local web UI is the only authenticated
   write path.
3. **Content + streaming** — `at_rest.integrity/availability`, the
   `in_motion.*` cells for `watch_video_clip`, and `possession` (identity
   key + clip bytes).
4. **Then the familiar ground** — supply chain (`create`/`acquire`/
   `deliver`), actors, environment — reusing the `by_design` claims from
   the mcl-echo dogfood where the mechanisms are the same (pins, digests,
   crash-loud boot), always citing *this repo's* artifacts.

Statuses stay honest: pre-deployment, most claims will be `assumed` or
`roadmap`; `assessed` only where a test or doc in this repo proves the
mechanism. `na` always with a written reason, never as a shortcut.

CI wiring (`security-fovea` workflow) is added only when `fovea lint`
is clean — do not ship a red gate for an unfinished grid.
