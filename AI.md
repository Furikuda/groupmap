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
- Autocomplete is a native `<datalist>` built from `GET /all_fluffs`; the logic is in `public/autofill.js` (no DOM, tested with QuickJS in `test/js/`). Info is pre-filled only on a *pick* from the list: no typing key/paste/IME event in the last 150 ms AND the event looks like a list pick (non-`InputEvent` in Chrome, `insertReplacementText` in Firefox/Safari). Picking another name replaces auto-filled info; editing the name clears it; hand-typed info is never touched. When several fluffs share a name, `indexByName` suggests the one with info, newest first. Add `?debug` to the URL to log input events.
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

Logging: access log (Sinatra CommonLogger) + `rack.logger` at INFO on stderr (`set :logging, Logger::INFO`). Without it Sinatra::Base
installs a FATAL-level logger and Rack::Protection 403s (e.g. JsonCsrf when the proxy does not forward `Host`) are invisible.
Validation errors are not logged; 500s are logged as one line
(`dump_errors` off). `GROUPMAP_SQL_LOG=1` re-enables query logging.

Tile fallback: existing tiles are served statically (`Cache-Control: public, max-age=3600`); missing tiles inside a
known map get `blank.png` via `send_file`, unknown maps 404.

### Tools

- `tools/convert_db_to_v2.rb` – one-off, discard after use. Reads either old layout read-only, unescapes names, merges duplicates, reports rows with HTML-looking text.
- `tools/prepare_pic.rb` – vips only (graphicsmagick no longer needed); float upscale factor, temp upscaled copy in a tmpdir, writes manifest with `max_zoom`/`width`/`height` via `JSON.pretty_generate`, aborts on any command failure.
- `tools/transform.rb` – affine least-squares fit (stdlib `matrix`) from ≥3 control points; dry run by default, `--apply` updates the map's markers in one transaction. Replaces `transform.py`, which generated SQL for the pre-2019 schema.

## Tests

`bundle exec rake` runs Minitest + rack-test (`test/`). The helper sets `GROUPMAP_DB` to a temp file before loading the
app; each test swaps `store`, `catalog` and `add_throttle` settings on `GroupMap::App` with fresh fixtures.

| File | Covers |
| --- | --- |
| `throttle_test.rb` | min interval, sliding hourly cap, rejected hits not counted, per-key isolation, pruning, thread safety |
| `marker_input_test.rb` | required/length limits, raw HTML kept, NFC + control-char + invalid UTF-8 cleanup, coordinate parsing and bounds |
| `map_catalog_test.rb` | year sorting, broken manifests skipped with warning, hot reload, blank tile lookup |
| `store_test.rb` | idempotent add, fluff reuse, NOT NULL / FK / cascade / index in the schema |
| `app_test.rb` | every route, JSON errors (400/404/429/500), headers, throttling per IP, tile fallback, quiet logs |
| `tools_test.rb` | convert script (both old layouts, read-only source, refusals), transform (dry run, apply, bad points), prepare_pic argument checks |

Not covered: the front-end JS (no JS test runner here; Node is not used) and `prepare_pic.rb` tiling itself (needs libvips).

### Deployment behind nginx

The app must see the real `Host` (else Rack::Protection::JsonCsrf 403s every JSON call made from the page, because
the Referer host differs) and the client IP (else the throttle treats all users as 127.0.0.1). Run with
`RACK_ENV=production`: in development Sinatra 4 only permits localhost/`.test` hosts.

```nginx
proxy_set_header Host              $host;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

## Caching

`lib/groupmap/cache_headers.rb` (Rack middleware, also covers static files): `/group_pics/*` 1 day,
`/vendor/*` (versioned dirs) 1 year immutable, everything else `no-cache` (revalidated via Last-Modified → 304),
so JS/CSS deploys are picked up on the next page load.

`bundle exec rake` runs both the Minitest suite and the QuickJS tests (`rake test:js`, `QJS=` overrides the binary).
