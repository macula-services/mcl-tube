# Changelog

## 0.1.0 (unreleased)

Ported from `hecate-services/hecate-tube` (main 41f693d plus the unmerged
`fix/wire-text-and-arg-keys`, 06c58a8) onto `mcl_om` and macula 12.

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
