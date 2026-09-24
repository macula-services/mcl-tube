# Changelog

## 0.1.0 (unreleased)

Ported from `hecate-services/hecate-tube` (main 41f693d plus the unmerged
`fix/wire-text-and-arg-keys`, 06c58a8) onto `mcl_om` and macula 12.

- **On `mcl_om` 0.27; the boot claim says which service, which box.** The claim
  carries `MCL_SERVICE_NAME=mcl-tube` and the host's `MCL_BOX`, shown on the
  realm's Providers desk. 0.27 no longer brings barrel_docdb or rocksdb, which
  tube never used: its read model is in memory.
- **The team image pair.** Builds in `macula-ci-otp` and runs on
  `macula-pq-runtime` (Debian trixie) with ffmpeg from Debian, both pinned by
  dated tag and digest, instead of floating `erlang:28-alpine` and
  `alpine:3.22`. CI runs in the same build image, installs ffmpeg for the scan
  tests and adds dialyzer; `.tool-versions` moves to 28.4.3.
- **Test modules no longer ship in the release, and each suite runs once.** The
  apps' `rebar.config` files listed `test` in `src_dirs`, which compiled the
  test modules into the production release (eight shipped in the image) and ran
  every guide suite twice. The explicit lists go: rebar3 compiles `src/`
  recursively and adds `test/` for eunit only.
- **Dialyzer clean.** The command and event accessors are specced on their
  opaque `t()`, and ranch, cowlib and reckon_gater join the PLT.

- **Procedures are org-namespaced**: `mcl-tube/lookup_channel`,
  `mcl-tube/lookup_video_clip`, `mcl-tube/lookup_content` and
  `mcl-tube/watch_video_clip` replace the bare `tube.*` names macula 12 refuses
  to serve.
- **Catalog facts are canonical**: `io.macula/mcl-tube/tube/catalog/*_v1`
  replace `io.macula/tube-commons/tube/*_v1`. Text travels as CBOR text and ids
  as bytes; id arguments are read under every key form (06c58a8).
- **A view is announced once.** `video_clip_viewed_v1` was published by an
  event handler that evoq replays on every boot, and consumers count views by
  fact, so every restart re-added every historical view. It is now announced
  from the dispatch that recorded it.
- **The owner web UI binds loopback by default.** It has no authentication of
  its own and bound every interface under host networking, which handed upload,
  reconfigure and retract to anyone who could reach the port.
- **Health reports a missing provider grant**, per procedure (through mcl_om 0.26.3's own check), instead of `ok`.
- **Refuses to start** when the realm name the topics carry does not hash to
  the realm tag.
