# GroupMap – implementation notes

## Front-end (rewritten 2026-11)

No build step, no framework. Files:

- `views/main.slim` – page shell: top bar (map `<select>`, marker toggle, About), full-height `#map`, toast, native `<dialog>` for About.
- `public/groupmap.css` – plain CSS with custom properties, light/dark via `prefers-color-scheme`, `100dvh` layout and safe-area insets for phones.
- `public/groupmap.js` – one ES module (`type="module"`), uses only the global `L` from Leaflet.
- `public/vendor/leaflet-1.9.4/` – vendored Leaflet (js, css, marker images). jQuery and Materialize were removed.

### Behaviour

- Map list comes from `GET /list_maps`; the selected map is the URL hash (`#folder`), with `hashchange` support so back/forward work.
- Tiles: `/group_pics/<folder>/{z}/{y}/{x}.jpg` (vips `--layout google`), `L.CRS.Simple`. Coordinates are **unchanged** from the old front-end, so existing markers stay in place.
- Manifest fields used: `name`, `shortname`, `url`, `source_pic`, `source_photographer`, `max_zoom` (default 7, the deepest tile level), and optionally `width`/`height` (pixel size of the tiled image). With width/height the view fits the picture exactly; otherwise the legacy view `[-20, 100]` @ zoom 3 is used and bounds fall back to the 256×256 zoom-0 square.
- One extra zoom level beyond `max_zoom` is allowed (`maxNativeZoom`) for precise tapping on phones.
- Click/tap an empty spot to open the add form; a tap that only dismisses an open popup does not start a new tag. The draft marker is removed when its popup closes.
- Autocomplete is a native `<datalist>` built from `GET /all_fluffs`; choosing a known name pre-fills its info.
- All user content is rendered with `textContent`/DOM nodes; URLs in `info` are linkified only if they start with `http(s)://`. Manifest values in the attribution are HTML-escaped.
- Names are decoded with `decodeEntities()` because the backend stores them `CGI.escapeHTML`-ed. If the backend stops escaping, remove that call.
- Responses that arrive out of order for markers are dropped (`markersToken`).

### API used (unchanged)

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/list_maps` | `{maps: [manifest + folder]}` |
| GET | `/all_fluffs` | `{fluffs: [{id, name, info}]}` |
| GET | `/list_fluff?map=` | `{fluffs: [{id, fluff_id, map, lat, lng}]}` |
| POST | `/add_fluff` | form-encoded `name, info, lat, lng, map`; any non-2xx is treated as an error |

- Errors come back as `{error: "..."}` with 400 (validation), 404 (unknown map) or 429 (throttled, with `Retry-After`); the front-end shows 4xx messages to the user.
- Clicks outside the picture bounds are ignored client-side (the server rejects them anyway).

## Back-end (rewritten 2026-11)

Modular Sinatra app, gems via `Gemfile` into `vendor/bundle`. Entry points: `config.ru` (rackup/puma) and `index.rb`.

| File | Role |
| --- | --- |
| `lib/groupmap/app.rb` | `GroupMap::App < Sinatra::Base`: routes, JSON helpers, security headers (CSP, nosniff), error handlers |
| `lib/groupmap/db.rb` | Sequel connection + `create_table?` schema (no migration framework, by choice) |
| `lib/groupmap/store.rb` | queries; `add_marker` is idempotent via `INSERT ... ON CONFLICT DO NOTHING` |
| `lib/groupmap/map_catalog.rb` | reads `public/group_pics/*/manifest.json`, re-reads on mtime change, skips broken manifests with a warning |
| `lib/groupmap/marker_input.rb` | validation: known map, name 1–100 chars, info ≤ 500, UTF-8 scrubbed + NFC + control chars removed, lat ∈ [-256,0], lng ∈ [0,256] |
| `lib/groupmap/throttle.rb` | in-memory per-IP sliding window (min interval + hourly cap). Per process, resets on restart. Uses `request.ip` (Rack honours `X-Forwarded-For` from private/loopback proxies only) |

Schema (`db/fluff_v2.sqlite`): `fluff(id, name NOT NULL, info NOT NULL DEFAULT '', UNIQUE(name, info))`,
`map(id, fluff_id NOT NULL → fluff ON DELETE CASCADE, map, lat, lng NOT NULL, UNIQUE(fluff_id, map, lat, lng), INDEX(map))`.
Text is stored raw (no HTML escaping); XSS safety relies on the front-end rendering text only, plus CSP.

Logging: puma/rack access log only. Validation errors are not logged; 500s are logged as one line
(`dump_errors` off). `GROUPMAP_SQL_LOG=1` re-enables query logging.

Tile fallback: existing tiles are served statically (`Cache-Control: public, max-age=3600`); missing tiles inside a
known map get `blank.png` via `send_file`, unknown maps 404.

### Tools

- `tools/convert_db_to_v2.rb` – one-off, discard after use. Reads either old layout read-only, unescapes names, merges duplicates, reports rows with HTML-looking text.
- `tools/prepare_pic.rb` – vips only (graphicsmagick no longer needed); float upscale factor, temp upscaled copy in a tmpdir, writes manifest with `max_zoom`/`width`/`height` via `JSON.pretty_generate`, aborts on any command failure.
- `tools/transform.rb` – affine least-squares fit (stdlib `matrix`) from ≥3 control points; dry run by default, `--apply` updates the map's markers in one transaction. Replaces `transform.py`, which generated SQL for the pre-2019 schema.
