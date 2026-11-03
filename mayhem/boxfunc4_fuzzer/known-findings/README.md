# boxfunc4_fuzzer: out-of-memory in `boxaDisplayTiled` (CWE-789), not a memory-safety error

- **Reproducer:** `oom-boxaDisplayTiled.boxa` (a valid, serialized `boxa`: 44 page-sized boxes,
  about 1800 x 2700 each, the shape of a real page-layout box set).
- **Crash:** `libFuzzer: out-of-memory (used: 2363Mb; limit: 2048Mb)`, in
  `boxaDisplayTiled` -> `pixAddSingleTextblock` -> `pixCreate` -> `pixdata_malloc` (`src/pix1.c`).
- **Cause:** `boxaDisplayTiled` (`src/boxfunc4.c`) calls `pixCreate(w, h, 32)` once per box, with
  `w`,`h` the extent of the *whole* boxa, and keeps every tile alive in a `PIXA` until
  `pixaDisplayTiledInRows` has composed them. 44 tiles of roughly 20 MB each, plus the copies made
  by `pixAddSingleTextblock`, exceed the 2 GB RSS limit. No out-of-bounds access, no UB.
- **Impact:** resource exhaustion on a large `boxa` (memory is linear in box count x extent).
  `-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION` caps one `pixCreate` at 64 MB, not the sum.
- **Not guarded in the harness:** the upstream harness is unchanged on purpose; filtering the
  shape that exhausts memory would mask the finding. Treat this defect as OOM-class, not as a
  confirmed memory-safety bug.
- **Possible upstream fix:** build each tile at the box's own size, or render tiles into one
  canvas incrementally instead of holding `n` full-extent images.

Replay: `/mayhem/boxfunc4_fuzzer mayhem/boxfunc4_fuzzer/known-findings/oom-boxaDisplayTiled.boxa`
(the libFuzzer binary, default `-rss_limit_mb=2048`).
