# System Landscape — mcl-tube

```
   owner (local)                    mesh consumers
   ┌────────────────┐               ┌────────────────────────────┐
   │  web UI        │               │  lookup_* / watch_video_*  │
   │  (local, mcl-  │               │  over org mcl-tube         │
   │   tube service)│               └──────────────┬─────────────┘
   └───────┬────────┘                              │
           │ commands                             │ queries / stream
           ▼                                      ▼
   ┌───────────────────────────────────────────────────────────────┐
   │                    mcl-tube (OTP, four apps)                   │
   │                                                                │
   │  guide_tube_lifecycle  CMD: channel/clip lifecycle, events     │
   │                        + catalog announcements (4 facts)       │
   │  project_tube          PRJ: read model, in memory, rebuilt     │
   │                        from the store at boot                  │
   │  query_tube            QRY: lookups + watch stream             │
   │  mcl_tube              service: web UI + mcl_om contract       │
   │                                                                │
   │  ┌──────────────────┐   ┌───────────────────────────────────┐  │
   │  │ event store      │   │ clip content (mcid-served) [2]   │  │
   │  │ + snapshots [1]  │   │                                   │  │
   │  │ (reckon evoq,    │   └───────────────────────────────────┘  │
   │  │  mcl_tube_store) │                                          │
   │  └──────────────────┘                                          │
   │  ┌──────────────────┐                                          │
   │  │ identity key     │  /etc/mcl/secrets/identity.key [3]      │
   │  └──────────────────┘                                          │
   └───────────────────────────────────────────────────────────────┘
           ▲
           │ facts on io.macula/mcl-tube/tube/catalog/ + procedures
           │ (transport/DHT/station — out of scope, delegated)
   ┌───────┴──────────────────────────────────────────┐
   │  mesh substrate (mcl_om + macula, anchor #4)      │
   └──────────────────────────────────────────────────┘

   [1] event-sourced truth; the read model is rebuilt from it at boot
   [2] why this assessment has a real data family: stored clip bytes
   [3] same secrets-volume pattern as the sibling mcl services
```

## Scope markers

In scope (per fovea.yaml): the four apps, the event store, clip content,
the four procedures and four facts, the owner web UI, identity wiring. Out:
realm governance, station/DHT transport, the portal catalogue consumer,
operators' hosts.

## Risks the landscape must answer

1. **Retraction is a confidentiality promise.** A retracted clip must stop
   being servable everywhere — the gap between the `video_clip_retracted_v1`
   fact and the last cached stream is the sharpest cell in the grid.
2. **The owner UI is a new attack surface** none of the earlier dogfoods
   had: an authenticated local web session that can publish and retract.
3. **Content is real data.** Unlike stateless services, `at_rest.*` here
   covers stored events, snapshots, and clip bytes — and `in_motion.*`
   covers a *streaming* procedure, not just request/reply.
4. **Pre-deployment timing.** Status is "built and tested, not yet
   deployed": cells can be honest without fleet verification, and the
   assessment ships *before* the service does.
