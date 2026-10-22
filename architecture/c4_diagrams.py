"""Generate mcl-tube's two C4 diagrams into assets/.

Run:  python3 architecture/c4_diagrams.py

  c4-context.svg     Level 1: what the service talks to
  c4-components.svg  Level 2: what it is made of

Drawn from the code, never from a template: the four apps under apps/, the
callbacks in mcl_tube_service.erl, the providers in query_tube, the projections
in project_tube, the handlers in guide_tube_lifecycle, the dependencies in
rebar.config, the port and volumes in the Containerfile and
deploy/docker-compose.yml. When one of those changes, the diagram changes in
the same commit.

Colours are plain classes with a prefers-color-scheme: dark block, no CSS custom
properties (rsvg-convert renders those black), so the SVGs render the same on
GitHub, in IDE previews and through rsvg-convert. After a change, render each
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it; keep
architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

# Element kinds, each (light fill, light stroke, dark fill, dark stroke).
KINDS = {
    "b-sys": ("#F5E9CC", "#A56F0A", "#3A2E13", "#E3AA3C"),   # in scope
    "b-per": ("#E3EBF2", "#3B5B7A", "#1D2A36", "#8EB4D8"),   # person
    "b-mac": ("#E6E4EE", "#5E5A78", "#26243A", "#A9A4C8"),   # Macula infrastructure
    "b-ext": ("#ECEFED", "#8A9791", "#1C2421", "#7D8B85"),   # external system
    "b-cmp": ("#FFFFFF", "#8A9791", "#171F1C", "#7D8B85"),   # component or container
}

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.t-leg {{ font-family: {SANS}; font-size: 12px; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
""" + "".join(f".{k} {{ fill: {v[0]}; stroke: {v[1]}; stroke-width: {2 if k == 'b-sys' else 1.25}; }}\n" for k, v in KINDS.items()) + """\
.b-later { fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }
.bound { fill: none; stroke: #B3BDB8; stroke-width: 1; }
.head { fill: #3B5B7A; }
.t-name, .t-code { fill: #16201D; }
.t-type, .t-bound, .t-leg { fill: #66736E; }
.t-desc { fill: #34413C; }
.t-rel { fill: #66736E; stroke: #FFFFFF; }
.edge, .edge-later { stroke: #8A9791; }
.arrowhead { fill: #8A9791; }
@media (prefers-color-scheme: dark) {
.bg { fill: #171F1C; }
""" + "".join(f".{k} {{ fill: {v[2]}; stroke: {v[3]}; }}\n" for k, v in KINDS.items()) + """\
.b-later { stroke: #7D8B85; }
.bound { stroke: #4A5752; }
.head { fill: #8EB4D8; }
.t-name, .t-code { fill: #E6ECE9; }
.t-type, .t-bound, .t-leg { fill: #93A09A; }
.t-desc { fill: #C3CDC8; }
.t-rel { fill: #93A09A; stroke: #171F1C; }
.edge, .edge-later { stroke: #7D8B85; }
.arrowhead { fill: #7D8B85; }
}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path class="arrowhead" d="M0 0L10 5L0 10z"/></marker></defs>')

LEGEND = [("b-sys", "In scope"), ("b-per", "Person"), ("b-mac", "Macula infrastructure"),
          ("b-ext", "External system"), ("b-cmp", "Container or component")]
BOUNDARY = ("bound", "Boundary")


class Diagram:
    def __init__(self, name, title, w, h):
        self.name, self.title, self.w, self.h, self.parts = name, title, w, h, []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def box(self, cls, x, y, w, h, name, kind, desc, person=False, code=False):
        # A box that is too small for its own words renders as text on top of the
        # next box, which no test would catch and a reader would read as the
        # diagram saying something it does not. Fail here instead.
        need = 70 + 16 * max(len(desc) - 1, 0) + 18
        if h < need:
            raise ValueError(f"{self.name}: {name} needs height {need}, has {h}")
        for line in desc:
            if 16 + 6.2 * len(line) > w - 16:
                raise ValueError(f"{self.name}: {name}: '{line}' is wider than {w - 32}px")
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-code" if code else "t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def bound(self, x, y, w, h, label):
        self.parts.append(f'<rect class="bound" x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/>')
        self.text("t-bound", x + 16, y + 22, label)

    def edge(self, d, later=False):
        self.parts.append(f'<path class="{"edge-later" if later else "edge"}" d="{d}" marker-end="url(#a)"/>')

    def legend(self, y, boundary=True):
        x = 24
        for cls, label in LEGEND + ([BOUNDARY] if boundary else []):
            self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="22" height="14" rx="3"/>')
            self.text("t-leg", x + 30, y + 12, label)
            x += 34 + 6.6 * len(label)

    def write(self):
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
               f'aria-label="{escape(self.title)}">', f"<title>{escape(self.title)}</title>", STYLE, DEFS,
               f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>'] + self.parts + ["</svg>", ""]
        with open(os.path.join(OUT, self.name), "w") as f:
            f.write("\n".join(svg))


def context():
    d = Diagram("c4-context.svg", "mcl-tube system context", 1160, 780)
    d.box("b-per", 40, 30, 300, 120, "Owner", "[Person]",
          ["Creates a channel, uploads clips", "and publishes, retracts and archives",
           "them through the web UI"], person=True)
    d.box("b-per", 420, 30, 300, 120, "Viewer", "[Person]",
          ["Any mesh caller: an app that looks", "a channel, a clip or its content up,",
           "and streams a published clip"], person=True)
    d.box("b-per", 790, 30, 320, 136, "Service operator", "[Person]",
          ["Runs the box, sets MCL_REALM, the", "realm key and the station seeds, and",
           "has the realm grant this node a D25", "provider authorization per procedure"],
          person=True)
    d.box("b-sys", 420, 230, 320, 152, "mcl-tube", "[mcl_om mesh service, own box]",
          ["Serves four sealed procedures under", "mcl-tube/ and the owner web UI on",
           "8491. Owns a reckon-db store and an", "event-sourced catalog, and announces",
           "it on four facts."])
    d.box("b-mac", 40, 460, 300, 120, "macula-realm", "[Macula infrastructure]",
          ["Endorses the node's identity key and", "issues the D25 provider grant for",
           "each org-namespaced procedure"])
    d.box("b-mac", 420, 460, 320, 136, "Macula stations, mesh DHT", "[Macula infrastructure]",
          ["The pinned seeds in", "MACULA_STATION_SEEDS carry every",
           "call and fact (QUIC); the DHT holds", "the four advertisements."])
    d.box("b-ext", 790, 460, 320, 136, "A catalogue, the portal's", "[External system]",
          ["Subscribes to the four catalog facts", "and lists channels and clips without",
           "asking; a listing nobody re-announced", "is expired."])

    d.edge("M190 150V300H420")
    d.text("t-rel", 198, 172, "uploads and publishes")
    d.text("t-rel", 198, 188, "through the UI on 8491")
    d.edge("M580 150V230")
    d.text("t-rel", 588, 186, "seals a call to")
    d.text("t-rel", 588, 202, "mcl-tube/<name>")
    d.edge("M950 166V200H700V230")
    d.text("t-rel", 938, 194, "deploys; sets the realm and station variables", anchor="end")
    d.edge("M460 382V420H190V460")
    d.text("t-rel", 316, 412, "boot claim, scope mcl-tube", anchor="middle")
    d.edge("M580 382V460")
    d.text("t-rel", 588, 404, "advertises the four")
    d.text("t-rel", 588, 420, "procedures, and publishes")
    d.text("t-rel", 588, 436, "the four facts")
    d.edge("M740 320H860V460")
    d.text("t-rel", 748, 314, "publishes the four catalog facts")
    d.text("t-desc", 40, 632, "The service calls nothing outside the mesh: a stream reads a clip off its own disk and the two lookups")
    d.text("t-desc", 40, 650, "read its own read model. Every procedure refuses a caller that does not seal, so a station relays ciphertext only.")
    d.legend(716, boundary=False)
    d.write()


def components():
    d = Diagram("c4-components.svg", "mcl-tube components", 1160, 1390)
    d.bound(16, 40, 1128, 890, "mcl-tube [Container: one OTP release, four apps]")

    d.box("b-cmp", 32, 70, 540, 120, "mcl_tube_app", "[OTP application]",
          ["Opens this service's own reckon-db store from mcl_tube_service:event_store/0,",
           "then calls mcl_om:boot/1. The three departments start before it, so every",
           "projection is registered before the store replays."], code=True)
    d.box("b-sys", 32, 222, 540, 136, "mcl_tube_service", "[mcl_om_service behaviour]",
          ["The six callbacks mcl_om resolves by name: info, start, stop, health,",
           "capabilities, identity_spec, plus event_store/0 and data_dir/0. Its",
           "capabilities/0 declares four procedures, each confidential => required and",
           "sealed with this node's ML-KEM key; identity_spec/0 asks for scope mcl-tube."], code=True)
    d.box("b-cmp", 32, 390, 540, 120, "mcl_tube_sup", "[supervisor, one_for_one]",
          ["One child: a cowboy listener through ranch:child_spec mcl_tube_http, on",
           "MCL_TUBE_HTTP_IP and MCL_TUBE_HTTP_PORT (127.0.0.1:8491 by default).",
           "It has no authentication of its own, so it binds loopback unless told."], code=True)
    d.box("b-cmp", 32, 542, 540, 136, "tube_owner_ui_routes", "[cowboy handlers]",
          ["The owner's pages: tube_dashboard_page, tube_channel_configure_page,",
           "tube_video_clip_upload_page, tube_video_clip_actions and",
           "tube_owner_content_page, with tube_multipart parsing uploads and",
           "tube_owner_http answering HTML. Every write dispatches an evoq command."], code=True)
    d.box("b-cmp", 32, 710, 540, 120, "mcl_tube_store", "[reckon-db store, single node]",
          ["Opened by mcl_tube_app before mcl_om boots: id mcl_tube_store, at MCL_DATA_DIR,",
           "no indexes, one node, integrity disabled. The evoq block in sys.config.src",
           "names the same id and a test compares the two."], code=True)

    d.box("b-cmp", 588, 70, 540, 152, "guide_tube_lifecycle", "[CMD app, event sourced]",
          ["channel_aggregate and video_clip_aggregate sit over the store, one desk",
           "per business step: initiate_channel, reconfigure_channel, upload_video_clip,",
           "publish_video_clip, retract_video_clip, archive_video_clip,",
           "record_video_clip_view, rehash_channel_logo and rehash_video_clip_thumbnail.",
           "Its events are the only source of the read model and the catalog facts."], code=True)
    d.box("b-cmp", 588, 254, 540, 136, "project_tube", "[PRJ app]",
          ["project_tube_store owns two ETS tables, tube_channels and tube_video_clips,",
           "and every QRY desk reads through it. Two evoq_projection workers fill",
           "them: channel_lifecycle_to_channels and video_clip_lifecycle_to_video_clips.",
           "The model is in memory and rebuilt from the store on every boot."], code=True)
    d.box("b-cmp", 588, 422, 540, 152, "query_tube", "[QRY app]",
          ["Four providers, one per advertised procedure: advertise_channel_lookup,",
           "advertise_video_clip_lookup, advertise_content_lookup and",
           "stream_video_clip_by_id, which pushes 64 KiB chunks off local disk and",
           "stops with a stream error the moment a clip is retracted. Only published",
           "clips are served; tube_json_view renders the page desks' JSON."], code=True)
    d.box("b-cmp", 588, 606, 540, 120, "tube_content_store", "[local content cache]",
          ["Clip thumbnails and channel logos, keyed by the hex MCID, which is the",
           "SHA-384 of the bytes: tube_content_put refuses bytes that do not hash to",
           "it, and a file that no longer does is never served."], code=True)
    d.box("b-cmp", 588, 758, 540, 152, "on_video_clip_published_publish_clip", "[evoq_event_handler]",
          ["One of four mesh handlers under guide_tube_lifecycle_sup; all four publish",
           "through tube_mesh_publisher. Its siblings withdraw a clip on retract and",
           "on archive, channel_announced_v1_to_mesh publishes a channel on every",
           "change, and channel_heartbeat re-announces every channel and one page of",
           "published clips every 60 s, so a catalogue can expire what it stops seeing."], code=True)

    d.edge("M200 190V222"); d.text("t-rel", 208, 214, "boots with")
    d.edge("M200 358V390"); d.text("t-rel", 208, 382, "start/1 starts")
    d.edge("M200 510V542"); d.text("t-rel", 208, 534, "mounts")
    d.edge("M740 222V254"); d.text("t-rel", 748, 246, "its events are projected")
    d.edge("M740 390V422"); d.text("t-rel", 748, 414, "every desk reads through project_tube_store")
    d.edge("M740 574V606"); d.text("t-rel", 748, 598, "serves logos and thumbnails from")
    d.edge("M1128 128H1140V740H900V758"); d.text("t-rel", 908, 747, "publishes through")

    d.box("b-mac", 32, 962, 352, 136, "mcl_om", "[library, ~> 1.0]",
          ["boot/1: loads the node identity key,",
           "joins the realm, dials the pinned",
           "stations over QUIC, advertises the four",
           "capabilities, serves /health on a socket."], code=True)
    d.box("b-mac", 404, 962, 352, 136, "macula", "[library, ~> 15.6, wire 1.0]",
          ["QUIC transport and the RPC dispatch to",
           "a provider that answers by name; the",
           "streamer, the publisher, and the signed",
           "records the mesh DHT holds."], code=True)
    d.box("b-cmp", 776, 962, 352, 136, "evoq / reckon_evoq / reckon_db", "[libraries, ~> 1.26 / ~> 2.7 / ~> 5.4]",
          ["Event sourcing for the two aggregates and",
           "the two projections, over this service's",
           "own store: commands in, events out, and",
           "the per-store subscription that replays."], code=True)
    d.box("b-ext", 40, 1122, 1080, 120, "MCL_DATA_DIR", "[environment, read by the service; a host volume in the compose file]",
          ["MCL_DATA_DIR (store, clips, content cache), MCL_TUBE_HTTP_IP and MCL_TUBE_HTTP_PORT, MCL_REALM,",
           "MCL_REALM_NAME and MCL_REALM_KEY, MACULA_STATION_SEEDS and MACULA_STATION_NODE_IDS. The node's",
           "identity key is /etc/mcl/secrets/identity.key, in the mcl-tube-secrets volume that must outlive it."], code=True)
    d.edge("M108 830V950H950V962"); d.text("t-rel", 120, 944, "events in and out, through reckon_evoq")
    d.text("t-desc", 40, 1282, "config/sys.config.src fixes the org, mcl-tube, which prefixes the four procedure names, and the realm name the catalog topics carry.")
    d.text("t-desc", 40, 1300, "The service refuses to start unless sha256 of that name is MCL_REALM, and mcl_om refuses a pool with an unpinned seed or no realm key.")
    d.legend(1340)
    d.write()


if __name__ == "__main__":
    for make in (context, components):
        make()
