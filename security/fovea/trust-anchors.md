# Trust-Anchor Register — mcl-tube

Anchors whose compromise totals the assessment's `by_design` claims
(spec/v0.3/14-instantiation). Draft until the pipeline and realm operators
confirm their ceremonies.

| # | Anchor | Type | Present? | Compromise impact |
|---|--------|------|----------|-------------------|
| 1 | **Node identity key** (`/etc/mcl/secrets/identity.key`) | Node authority | ☐ (mounted secrets volume) | Impersonate the channel owner's node: publish/retract as them, serve their clips. |
| 2 | **io.macula realm signing key** (counterpart of `MCL_REALM_KEY`) | Realm authority, held off-repo by the realm operator | ☐ | Total: every org-scoped advertisement the service resolves verifies against it. Assessed here as a named dependency, not as something this repo controls. |
| 3 | **Release pipeline** (`ghcr.io` org + CI) | Supply-chain authority | ☐ | All `create`/`acquire`/`deliver` cells: a reachable attacker publishes a plausible image and the host pulls it. |
| 4 | **mcl_om + macula dependency** (the L2 substrate the service is built on) | Vendor authority | ☑ (hex deps, `mcl_om ~> 0.28`, `macula ~> 12.2`) | Total: identity, boot, capabilities, and the wire all come from this dependency; a compromised substrate compromises the service. |

**Explicitly NOT anchors here (correctly absent):**
- The event store and clip content — data, not trust roots; their story is
  the `at_rest.*` cells.
- The owner's web-UI session — an authentication surface, not a root; its
  story is `operate`/`in_use` cells.
