# mcl-tube

**Video channels over the mesh: owners publish clips, anyone looks them up and streams them.**

This exists so a channel owner can publish video from their own box and anyone
on the mesh can find it and watch it, with no platform in between.

## Status

Built and tested locally, **not yet deployed**. Runs on macula 12 through
`mcl_om`. It replaces `hecate-services/hecate-tube` and inherits nothing from
it: no store, no identity, no topic, no procedure name.

## What it does

- An **owner** creates a channel, uploads clips (each is scanned before it can
  be published), publishes, retracts and archives them, through a web UI
  served locally by the service.
- **Anyone** on the mesh looks a channel, a clip or a piece of content (a
  thumbnail, a logo) up, and streams a published clip, over four procedures.
- The catalog is **announced** on four facts, so a catalogue (the portal's)
  can list channels and clips without asking.

Four apps, one per department:

| App | Department | What it holds |
|---|---|---|
| `guide_tube_lifecycle` | CMD | the channel and clip lifecycles, event sourced, and the catalog announcements |
| `project_tube` | PRJ | the read model, in memory, rebuilt from the store at boot |
| `query_tube` | QRY | the lookups and the watch stream |
| `mcl_tube` | service | the owner web UI and the mcl_om contract |

The design is in `plans/` (the event storm and plan it was built from).

## The contract

### Procedures

Served under the org `mcl-tube`, so callers dial `mcl-tube/<name>`:

| Procedure | Kind | Answers |
|---|---|---|
| `mcl-tube/lookup_channel` | request/reply | a channel's current details |
| `mcl-tube/lookup_video_clip` | request/reply | a clip's details |
| `mcl-tube/lookup_content` | request/reply | a stored piece of content by mcid |
| `mcl-tube/watch_video_clip` | stream | a published clip's bytes |

### Facts

Canonical macula app facts in `io.macula/mcl-tube/tube/catalog/`:

| Topic | When |
|---|---|
| `channel_announced_v1` | a channel was created or reconfigured, and on a heartbeat |
| `video_clip_published_v1` | a clip became visible |
| `video_clip_retracted_v1` | a clip was retracted or archived |
| `video_clip_viewed_v1` | a clip was watched to the end, once per view |

Text fields (names, descriptions, owners, tags) are sent as CBOR text, so every
stack reads them as strings; ids and mcids stay bytes. Channel and clip
announcements are upserts by id, safe to receive twice. A view is announced
exactly once, live, when it is recorded, because a consumer counts views by
fact.

Both lists are pinned by tests (`mcl_tube_service_tests`,
`tube_catalog_topic_tests`). A change is a new name, not an edit.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `MCL_REALM` | required | 64-hex realm tag, sha256 of the realm name |
| `MCL_REALM_NAME` | required | the realm name the catalog topics carry, e.g. `io.macula`. The service **refuses to start** unless its sha256 is `MCL_REALM` |
| `MCL_REALM_KEY` | required | the realm's public signing key, hex |
| `MACULA_STATION_SEEDS` | required | station hosts, `host[:port]`, comma-separated |
| `MACULA_STATION_NODE_IDS` | required | the matching 64-hex station node ids |
| `MCL_TUBE_HTTP_PORT` | `8491` | the owner web UI |
| `MCL_TUBE_HTTP_IP` | `127.0.0.1` | where the owner web UI binds. **It has no authentication of its own**, and the container runs on host networking: reach it over an SSH tunnel, and widen this only knowingly |
| `MCL_DATA` | `/bulk0/mcl-tube` | (compose) host directory for the store, the clips and the content cache |
| `MCL_HEALTH_PORT` | `8490` | health endpoint |

## Deploy

What an operator does, in order:

1. Set `MCL_REALM` and `MCL_REALM_NAME`, and mount the data directory on a
   bulk drive. `deploy/docker-compose.yml` also mounts the named identity
   volume `mcl-tube-secrets`; keep it, because the next step is tied to it.
2. **Have the realm grant this node its provider authorization.** Serving an
   org-namespaced procedure needs a realm-issued grant (D25) naming this node's
   id, and a person admits it on the realm. Until then nothing is advertised,
   every call resolves to nothing, and `/health` is degraded, naming each
   procedure still missing one under `provider_grants`. A new identity is a
   new, unadmitted node.
3. Reach the owner UI over a tunnel:
   `ssh -L 8491:127.0.0.1:8491 <box>`, then browse to `http://localhost:8491/`.

## Health

`/health` answers whether callers can **reach** the service. mcl_om reports
every procedure the realm has not granted this node a provider authorization
for: degraded at once when no delegation names this node (an operator has to
grant it), after a 60 s grace window for any other refusal, so a lookup that
fails once does not flap.

## Build and test

    rebar3 eunit
    rebar3 lint

OTP 28, pinned in `.tool-versions`, the `Containerfile` and CI.

## License

Apache-2.0. See [LICENSE](LICENSE).
