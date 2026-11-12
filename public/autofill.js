// Decides when the "info" field of the add-fluff form is pre-filled from a
// known fluff. No DOM access, so it can be tested with QuickJS (test/js/).
//
// Rule: only a *pick from the suggestion list* fills the info; typing or
// pasting a name that happens to match a known fluff never does. Two signals
// must agree that it was a pick:
// 1. No typing key, paste or IME composition just before the change. A mouse
//    or tap pick fires no keydown; a keyboard pick ends with Enter, which is
//    not a typing key.
// 2. The event looks like a list pick: not an InputEvent (Chrome), or
//    inputType "insertReplacementText" (Firefox/Safari), rather than
//    "insertText", "insertFromPaste", "insertCompositionText", ...

const TYPED_WINDOW_MS = 150;
const EDIT_KEYS = ['Backspace', 'Delete', 'Process', 'Unidentified', 'Dead'];

// Several fluffs can share a name (same person, links added over time). For
// each name keep the one worth pre-filling: with info first, then the newest.
export function indexByName(fluffs) {
  const better = (a, b) => (Boolean(a.info) !== Boolean(b.info) ? Boolean(a.info) : a.id > b.id);
  const byName = new Map();
  for (const fluff of fluffs) {
    const current = byName.get(fluff.name);
    if (!current || better(fluff, current)) byName.set(fluff.name, fluff);
  }
  return byName;
}

export function isTypingKey({ key, ctrlKey = false, metaKey = false, altKey = false }) {
  if (ctrlKey || metaKey || altKey || typeof key !== 'string') return false;
  return [...key].length === 1 || EDIT_KEYS.includes(key);
}

// lookup(name) -> { info } | undefined for a known fluff.
// now() -> milliseconds, injectable for tests.
export function createAutofill(lookup, now = () => performance.now()) {
  let typedAt = -Infinity;
  let autoFilled = null; // the info value we filled in, so we may replace/clear it

  return {
    keydown(event) {
      if (isTypingKey(event)) typedAt = now();
    },

    // paste, cut, drop, compositionstart, compositionupdate
    typed() {
      typedAt = now();
    },

    // Call on every "input" event of the name field. Returns
    // { picked, info } where info is the new value for the info field, or
    // undefined to leave it as it is.
    input({ name, info, isInputEvent, inputType }) {
      const typed = now() - typedAt < TYPED_WINDOW_MS;
      const listLike = !isInputEvent || !inputType || inputType === 'insertReplacementText';
      const picked = !typed && listLike;
      const ownInfo = Boolean(info) && info !== autoFilled; // typed by the user

      const known = picked ? lookup(name) : undefined;
      if (known) {
        if (ownInfo) return { picked, info: undefined };
        autoFilled = known.info ?? '';
        return { picked, info: autoFilled };
      }
      if (autoFilled !== null && !ownInfo) {
        // The name changed after a pick: drop the info that belonged to that fluff.
        autoFilled = null;
        return { picked, info: '' };
      }
      return { picked, info: undefined };
    },
  };
}
