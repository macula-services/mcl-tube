# Changelog

## 0.4.1 - 2026-10-10

- **Rebuilt on macula ~> 14 (newest release):** request admission frees the slot when the reply is sent, and caller attribution covers every payload shape (macula#89, macula#60).

## 0.4.0 - 2026-10-07

- **On macula 14.2 and mcl_om 0.39, `/health` on a Unix socket (#19).** `~> 14.2` (at least 14.2.1) and `~> 0.39`, the current SDK base, so an SDK fix reaches this service with the rest. mcl_om's `health_socket`, `/run/mcl/health.sock` inside the container: no TCP health listener runs, the image's HEALTHCHECK uses `curl --unix-socket`, and nothing configures, exposes or passes a health port; `scripts/health.sh` asks the running container. The sealing posture is unchanged.

## 0.3.0 - 2026-10-07

Sealed Macula TV (mcl-tube#17): a viewer's video never crosses the mesh in the
clear, and a retracted clip cannot be looked up or streamed by any path.

- **A retracted clip is unservable (#9).** `lookup_content` answers only for
  content something public names now, a published clip's thumbnail or a
  channel's logo; a retracted, archived or never-published clip's thumbnail is
  `not_found`, though its bytes stay on the owner's disk. A `watch_video_clip`
  stream already open reads its clip's state before every chunk and ends with a
  stream error (`video_clip_not_published`) once the clip is retracted or
  archived; no view is recorded.
- **Every published clip is re-announced within 5 minutes.** The heartbeat page
  grows with the catalog so a cycle never exceeds 5 ticks, so a catalogue can
  expire a listing nobody re-announced (macula-portal does) instead of trusting
  one `video_clip_retracted_v1` to arrive. A clip is announced published only
  while its row says so, so a heartbeat that listed a clip just before its
  retraction cannot re-list it after the withdraw went out.
- **Every procedure requires a sealed caller.** All four capabilities are
  `confidential => required`: a clear call or open is refused with
  `sealed_required` from the first second after boot, where `preferred` answered
  one for about 10 minutes after each start. Every macula SDK seals by default.
- **On macula 14.2 and `mcl_om` 0.38** (`~> 14.2`, `~> 0.38`, at least 14.2.1). tube sets no
  `node_identity_path`, so macula 14's per-account identity directory
  (macula-io/macula#76) changes nothing here; 14.1 puts every advertisement a
  caller seals to in the DHT (macula-io/macula#33), and 14.2.1 forwards a
  stream's `confidential`, without which the watch stream stayed `preferred`
  (macula-io/macula#85).

## 0.2.0 - 2026-10-06

- **Content ids are SHA-384 (macula-io/macula#46).** Logos and thumbnails are
  named by macula's raw-block id, `<<2, 16#55, SHA-384(Bytes)>>`, not the
  legacy BLAKE3 `<<1, 16#55, Hash:32>>`. The content store holds and serves
  bytes only under the id they hash to, refuses a legacy id (`bad_request` on
  `lookup_content`), and refuses more than one 256 KiB block; extracted
  thumbnails are scaled to at most 640 px wide so they fit. A one-shot boot
  migration (`rehash_legacy_content`) re-hashes every stored legacy logo and
  thumbnail once, records `channel_logo_rehashed_v1` /
  `video_clip_thumbnail_rehashed_v1`, and removes the legacy files; it goes in
  the next release. The owner UI reads its own images from the local store,
  not the mesh, and `tube_content_get` is gone.

## 0.1.0 - 2026-10-06

Ported from `hecate-services/hecate-tube` (main 41f693d plus the unmerged
`fix/wire-text-and-arg-keys`, 06c58a8) onto `mcl_om` and macula 12, then
moved to macula 13 (mcl-tube#14).

- **On macula 13.6 and `mcl_om` 0.37, with its own store.** `mcl_om` opens no
  store from 0.35 (mcl-om#10), and tube floated onto it unbuilt: every
  event-sourced test failed and no image built. `mcl_tube_app` now opens the
  reckon-db store `mcl_tube_service:event_store/0` describes, and its evoq
  subscription, before `mcl_om:boot/1`, at the same `<data_dir>/mcl_tube_store`
  mcl_om 0.34 used, so a node's existing events are the ones it opens. tube
  declares `reckon_db`, `evoq` and `reckon_evoq` itself and no longer exports
  `store_id/0`.
- **Its advertisements name an ML-KEM key** (`{kem_advertise, enabled}`), so a
  caller can seal lookups and the watch stream end to end and a station relays
  only ciphertext (macula-fleet#7). Every procedure stays `preferred`: a caller
  that does not seal is still answered.

- **`lookup_content` answers real callers, and only with content.** It matched
  `#{mcid := _}` raw, but macula 12's decoder leaves the key as sent and
  delivers the value as `{text, Hex}`, so every mesh caller (macula-portal's
  thumbnails and logos) got `bad_request`. It reads `mcid` through
  `mcl_om_wire:field/2` now, and upper-case hex is the same MCID.
- **The content store accepts only a hex MCID**, on read and on write. It built
  the file path from the MCID as given, so a value such as `../secret` reached a
  file outside the content directory; reading the field properly would have
  opened that to mesh callers. Anything but 2 to 128 hex digits, even in number,
  is refused (`bad_request` on the procedure). Tests send the request through
  macula's frame codec and cover traversal on read and on write.

- **On `mcl_om` 0.28 with macula 12.2.** The service answers `mcl-tube/info`,
  which mcl_om adds (public facts: versions, labels, health word, procedures),
  and a test sends that reply through macula's frame codec and checks it names
  this service and the mcl_om 0.28 / macula 12.2 pair. 0.28 is the release
  macula 12.2 needs: under 12.2 an older mcl_om lets a failed publish
  announcement kill the publishing process.
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
