// GroupMap front-end. Plain ES module, only depends on Leaflet (global `L`).
// See AI.md for an overview of how this talks to the Sinatra backend.

const DEFAULT_MAX_ZOOM = 7;
const TILE_SIZE = 256;
// Legacy initial view, used when a manifest has no width/height.
const LEGACY_VIEW = { center: [-20, 100], zoom: 3 };

const state = {
  maps: [],
  fluffs: new Map(), // fluff id -> { id, name, info }
  fluffsByName: new Map(), // display name -> fluff
  current: null, // manifest of the map on screen
  bounds: null, // L.LatLngBounds of the picture on screen
  tileLayer: null,
  draft: null, // temporary marker used to add a fluff
  markersToken: 0, // guards against out-of-order marker responses
};

const $ = (sel) => document.querySelector(sel);
const ui = {
  select: $('#map-select'),
  toggle: $('#toggle-markers'),
  aboutOpen: $('#about-open'),
  about: $('#about'),
  toast: $('#toast'),
};

// ---------- Helpers ----------

const escapeHTML = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const isHttpUrl = (s) => /^https?:\/\//i.test(s ?? '');

const linkHTML = (href, text) =>
  `<a href="${escapeHTML(href)}" target="_blank" rel="noopener">${escapeHTML(text)}</a>`;

function el(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children.filter((c) => c != null));
  return node;
}

// Turns "foo https://x.y bar" into text nodes and safe <a> elements.
function linkify(text) {
  const frag = document.createDocumentFragment();
  for (const part of text.split(/(https?:\/\/\S+)/i)) {
    if (!part) continue;
    frag.append(isHttpUrl(part)
      ? el('a', { href: part, target: '_blank', rel: 'noopener', textContent: part })
      : part);
  }
  return frag;
}

let toastTimer;
function toast(message, { error = false } = {}) {
  ui.toast.textContent = message;
  ui.toast.classList.toggle('error', error);
  ui.toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { ui.toast.hidden = true; }, error ? 5000 : 2500);
}

// ---------- API ----------

class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function getJSON(url, options) {
  const res = await fetch(url, options);
  if (!res.ok) {
    // The server answers errors as {error: "..."}; fall back to the status line.
    const body = await res.json().catch(() => ({}));
    throw new ApiError(body.error || `${res.status} ${res.statusText}`, res.status);
  }
  return res.json();
}

const api = {
  maps: () => getJSON('/list_maps').then((d) => d.maps ?? []),
  fluffs: () => getJSON('/all_fluffs').then((d) => d.fluffs ?? []),
  markers: (folder) => getJSON(`/list_fluff?map=${encodeURIComponent(folder)}`).then((d) => d.fluffs ?? []),
  addFluff: (fields) => getJSON('/add_fluff', { method: 'POST', body: new URLSearchParams(fields) }),
};

// ---------- Fluff list (autocomplete) ----------

const datalist = el('datalist', { id: 'fluff-names' });
document.body.append(datalist);

async function loadFluffs() {
  const rows = await api.fluffs();
  state.fluffs = new Map();
  state.fluffsByName = new Map();
  for (const row of rows) {
    const fluff = { ...row, info: row.info ?? '' };
    state.fluffs.set(fluff.id, fluff);
    if (!state.fluffsByName.has(fluff.name)) state.fluffsByName.set(fluff.name, fluff);
  }
  datalist.replaceChildren(...[...state.fluffsByName.keys()].sort().map((name) => el('option', { value: name })));
}

// ---------- Leaflet map ----------

const map = L.map('map', {
  crs: L.CRS.Simple,
  minZoom: 0,
  maxZoom: DEFAULT_MAX_ZOOM + 1,
  maxBoundsViscosity: 0.8,
  zoomControl: true,
});
const markers = L.layerGroup().addTo(map);

// Bounds of the picture in CRS.Simple units. One unit is one pixel at zoom 0,
// so a full pyramid always fits in the 256x256 square at the top-left.
function imageBounds(meta, maxZoom) {
  const w = Number(meta.width);
  const h = Number(meta.height);
  if (w > 0 && h > 0) {
    const scale = 2 ** maxZoom;
    return { bounds: L.latLngBounds([[-h / scale, 0], [0, w / scale]]), exact: true };
  }
  return { bounds: L.latLngBounds([[-TILE_SIZE, 0], [0, TILE_SIZE]]), exact: false };
}

function attributionHTML(meta) {
  const parts = [];
  const name = meta.name || meta.shortname || meta.short_name;
  if (name) parts.push(isHttpUrl(meta.url) ? linkHTML(meta.url, name) : escapeHTML(name));

  const photographer = meta.source_photographer;
  if (photographer) parts.push(isHttpUrl(photographer) ? linkHTML(photographer, photographer) : escapeHTML(photographer));

  const pic = meta.source_pic;
  if (pic) {
    const href = isHttpUrl(pic) ? pic : `/group_pics/${encodeURIComponent(meta.folder)}/${encodeURIComponent(pic)}`;
    parts.push(linkHTML(href, 'Full image'));
  }
  return parts.join(' · ');
}

function fluffPopup(fluffId) {
  const fluff = state.fluffs.get(fluffId);
  if (!fluff) return el('div', { className: 'fluff-popup' }, el('em', { textContent: 'Unknown fluff' }));
  return el('div', { className: 'fluff-popup' },
    el('h3', { textContent: fluff.name }),
    fluff.info ? el('p', {}, linkify(fluff.info)) : null);
}

async function loadMarkers(folder) {
  const token = ++state.markersToken;
  const rows = await api.markers(folder);
  if (token !== state.markersToken) return; // a newer request superseded this one
  markers.clearLayers();
  for (const row of rows) {
    const fluff = state.fluffs.get(row.fluff_id);
    L.marker([row.lat, row.lng], { title: fluff?.name ?? '', alt: fluff?.name ?? 'Fluff' })
      .bindPopup(() => fluffPopup(row.fluff_id))
      .addTo(markers);
  }
}

async function showMap(folder) {
  const meta = state.maps.find((m) => m.folder === folder) ?? state.maps[0];
  if (!meta) return;
  state.current = meta;
  ui.select.value = meta.folder;
  document.title = `${meta.name || meta.folder} · Fluffy maps`;

  closeDraft();
  markers.clearLayers();
  state.tileLayer?.remove();

  const maxZoom = Number(meta.max_zoom) || DEFAULT_MAX_ZOOM;
  const { bounds, exact } = imageBounds(meta, maxZoom);
  state.bounds = bounds;

  map.setMinZoom(0);
  map.setMaxZoom(maxZoom + 1); // one extra level of over-zoom helps precise tapping
  map.setMaxBounds(bounds.pad(0.2));

  state.tileLayer = L.tileLayer(`/group_pics/${encodeURIComponent(meta.folder)}/{z}/{y}/{x}.jpg`, {
    noWrap: true,
    bounds,
    maxNativeZoom: maxZoom,
    maxZoom: maxZoom + 1,
    attribution: attributionHTML(meta),
  }).addTo(map);

  if (exact) map.fitBounds(bounds);
  else map.setView(LEGACY_VIEW.center, LEGACY_VIEW.zoom);
  map.setMinZoom(Math.max(0, Math.floor(map.getBoundsZoom(bounds)) - 1));

  try {
    await loadMarkers(meta.folder);
  } catch (err) {
    console.error(err);
    toast('Could not load the markers for this picture.', { error: true });
  }
}

// ---------- Adding a fluff ----------

function closeDraft() {
  const draft = state.draft;
  state.draft = null;
  draft?.remove();
}

function addFluffForm(latlng) {
  const nameInput = el('input', {
    name: 'name', required: true, maxLength: 100, placeholder: 'Fluff name',
    autocomplete: 'off', autocapitalize: 'words', enterKeyHint: 'next',
  });
  nameInput.setAttribute('list', datalist.id);
  const infoInput = el('input', {
    name: 'info', maxLength: 500, placeholder: 'Social link or extra info',
    autocomplete: 'off', enterKeyHint: 'done',
  });
  const save = el('button', { type: 'submit', className: 'btn btn-primary', textContent: 'Save' });
  const cancel = el('button', { type: 'button', className: 'btn', textContent: 'Cancel' });
  const form = el('form', { className: 'add-fluff' },
    el('h3', { textContent: 'Who is that fluff?' }),
    nameInput, infoInput,
    el('div', { className: 'actions' }, cancel, save));

  // Picking a known fluff from the suggestion list pre-fills their info.
  // Typing a matching name does not: a list pick is not an InputEvent in
  // Chrome and has inputType "insertReplacementText" in Firefox, while typing
  // and pasting are "insertText"/"insertFromPaste".
  let autoFilled = null; // info value we put there, so we may replace/clear it
  const ownInfo = () => infoInput.value && infoInput.value !== autoFilled;
  nameInput.addEventListener('input', (e) => {
    const picked = !(e instanceof InputEvent) || e.inputType === 'insertReplacementText';
    const known = picked ? state.fluffsByName.get(nameInput.value) : null;
    if (known) {
      if (!ownInfo()) infoInput.value = autoFilled = known.info;
    } else if (autoFilled !== null && !ownInfo()) {
      // Name changed after a pick: drop the info that belonged to that fluff.
      infoInput.value = '';
      autoFilled = null;
    }
  });
  cancel.addEventListener('click', closeDraft);
  form.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeDraft(); });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = nameInput.value.trim();
    if (!name) return nameInput.focus();
    save.disabled = true;
    try {
      await api.addFluff({ name, info: infoInput.value.trim(), lat: latlng.lat, lng: latlng.lng, map: state.current.folder });
      closeDraft();
      toast(`${name} tagged!`);
      await loadFluffs();
      await loadMarkers(state.current.folder);
    } catch (err) {
      console.error(err);
      // 400 (validation) and 429 (too fast) carry a message meant for the user.
      const message = err instanceof ApiError && err.status < 500 ? err.message : 'Saving failed, please try again.';
      toast(message, { error: true });
      save.disabled = false;
    }
  });
  return { form, nameInput };
}

function openDraft(latlng) {
  closeDraft();
  const { form, nameInput } = addFluffForm(latlng);
  const draft = L.marker(latlng, { opacity: 0.75, keyboard: false }).addTo(map);
  draft.bindPopup(form, { minWidth: 200, autoPanPadding: [16, 16] });
  draft.on('popupclose', () => { if (state.draft === draft) closeDraft(); });
  state.draft = draft;
  draft.openPopup();
  // Only autofocus with a mouse: on touch it pops the keyboard and shifts the view.
  if (matchMedia('(pointer: fine)').matches) nameInput.focus();
}

// A click that only dismisses an open popup should not start a new tag.
let popupOpen = false;
let clickDismissedPopup = false;
map.on('popupopen', () => { popupOpen = true; });
map.on('popupclose', () => { popupOpen = false; });
map.on('preclick', () => { clickDismissedPopup = popupOpen; });
map.on('click', (e) => {
  if (clickDismissedPopup || !state.current) return;
  // Ignore clicks in the margin around the picture; the server would reject them.
  if (!state.bounds?.contains(e.latlng)) return;
  openDraft(e.latlng);
});

// ---------- Controls ----------

ui.toggle.addEventListener('click', () => {
  const visible = !map.hasLayer(markers);
  if (visible) markers.addTo(map);
  else markers.remove();
  ui.toggle.setAttribute('aria-pressed', String(visible));
});

ui.aboutOpen.addEventListener('click', () => ui.about.showModal());
// Clicking the backdrop closes the dialog.
ui.about.addEventListener('click', (e) => { if (e.target === ui.about) ui.about.close(); });

ui.select.addEventListener('change', () => { location.hash = encodeURIComponent(ui.select.value); });

const folderFromHash = () => decodeURIComponent(location.hash.slice(1));
window.addEventListener('hashchange', () => showMap(folderFromHash()));

// ---------- Boot ----------

async function boot() {
  try {
    const [maps] = await Promise.all([api.maps(), loadFluffs()]);
    state.maps = maps;
  } catch (err) {
    console.error(err);
    toast('Could not load the group pictures.', { error: true });
    return;
  }

  if (!state.maps.length) {
    ui.select.replaceChildren(el('option', { textContent: 'No group pictures yet' }));
    return;
  }
  ui.select.replaceChildren(...state.maps.map((m) =>
    el('option', { value: m.folder, textContent: m.name || m.shortname || m.folder })));
  ui.select.disabled = false;
  await showMap(folderFromHash());
}

boot();
