// Run with: qjs -m test/js/autofill_test.js   (or `bundle exec rake test:js`)
import { createAutofill, indexByName, isTypingKey } from '../../public/autofill.js';

let failures = 0;
let count = 0;
function check(label, actual, expected) {
  count += 1;
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures += 1;
    print(`FAIL ${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

const fluffs = new Map([['Aji', { info: 'https://bsky.app/profile/aji' }], ['Bob', { info: 'https://bob' }]]);
const lookup = (name) => fluffs.get(name);

// Simulated browser: a clock plus helpers that mimic the event sequences.
function browser() {
  let t = 1000;
  const af = createAutofill(lookup, () => t);
  const form = { name: '', info: '' };
  const apply = (event) => {
    const res = af.input({ name: form.name, info: form.info, ...event });
    if (res.info !== undefined) form.info = res.info;
    return res;
  };
  return {
    form,
    wait(ms) { t += ms; },
    type(text, inputType = 'insertText') {
      for (const ch of text) {
        t += 120;
        af.keydown({ key: ch });
        t += 2;
        form.name += ch;
        apply({ isInputEvent: true, inputType });
      }
    },
    backspace() {
      t += 120;
      af.keydown({ key: 'Backspace' });
      t += 2;
      form.name = form.name.slice(0, -1);
      apply({ isInputEvent: true, inputType: 'deleteContentBackward' });
    },
    pickWithMouse(name, flavour) {
      t += 500; // moving to the list, no keydown
      form.name = name;
      return apply(flavour === 'chrome' ? { isInputEvent: false } : { isInputEvent: true, inputType: 'insertReplacementText' });
    },
    pickWithKeyboard(name) {
      t += 300;
      af.keydown({ key: 'ArrowDown' });
      t += 300;
      af.keydown({ key: 'Enter' });
      t += 2;
      form.name = name;
      return apply({ isInputEvent: true, inputType: 'insertReplacementText' });
    },
    paste(text) {
      t += 500;
      af.keydown({ key: 'v', ctrlKey: true });
      af.typed(); // paste event
      t += 2;
      form.name += text;
      apply({ isInputEvent: true, inputType: 'insertFromPaste' });
    },
    typeInfo(text) { form.info = text; },
  };
}

// The reported bug: typing "Ajiho" passes through "Aji" and must not fill.
{
  const b = browser();
  b.type('Ajiho');
  check('typing Ajiho leaves info empty', b.form, { name: 'Ajiho', info: '' });
}
{
  const b = browser();
  b.type('Aji');
  check('typing an exact known name does not fill', b.form.info, '');
}
// Even if the browser labels typed text like a replacement, a keydown just
// before means typing.
{
  const b = browser();
  b.type('Aji', 'insertReplacementText');
  check('typing labelled insertReplacementText still does not fill', b.form.info, '');
}
// IME / mobile keyboards report key "Process"/"Unidentified".
{
  const b = browser();
  b.type('Aj');
  b.wait(120);
  b.form.name = 'Aji';
  check('IME keydown counts as typing', isTypingKey({ key: 'Process' }) && isTypingKey({ key: 'Unidentified' }), true);
}
{
  const b = browser();
  b.paste('Aji');
  check('pasting a known name does not fill', b.form.info, '');
}

// Picks fill.
for (const flavour of ['firefox', 'chrome']) {
  const b = browser();
  b.type('Aj');
  const res = b.pickWithMouse('Aji', flavour);
  check(`mouse pick fills (${flavour})`, [res.picked, b.form.info], [true, 'https://bsky.app/profile/aji']);
}
{
  const b = browser();
  b.type('Aj');
  b.pickWithKeyboard('Aji');
  check('keyboard pick (arrows + Enter) fills', b.form.info, 'https://bsky.app/profile/aji');
}

// After a pick.
{
  const b = browser();
  b.pickWithMouse('Aji');
  b.pickWithMouse('Bob');
  check('picking another fluff replaces auto-filled info', b.form.info, 'https://bob');
}
{
  const b = browser();
  b.pickWithMouse('Aji');
  b.type('ho');
  check('editing the name after a pick clears auto-filled info', b.form, { name: 'Ajiho', info: '' });
}
{
  const b = browser();
  b.typeInfo('my own link');
  b.pickWithMouse('Aji');
  check('a pick never overwrites info typed by hand', b.form.info, 'my own link');
  b.type('x');
  check('typing never clears info typed by hand', b.form.info, 'my own link');
}
{
  const b = browser();
  b.pickWithMouse('Aji');
  b.backspace();
  b.wait(1000);
  b.pickWithMouse('Aji');
  check('re-picking after a backspace fills again', b.form.info, 'https://bsky.app/profile/aji');
}
{
  const b = browser();
  const res = b.pickWithMouse('Nobody');
  check('picking an unknown name changes nothing', [res.picked, b.form.info], [true, '']);
}

// isTypingKey details.
check('letters are typing keys', ['a', 'Z', ' ', 'é', '😀'].every((key) => isTypingKey({ key })), true);
check('navigation keys are not', ['Enter', 'ArrowDown', 'Tab', 'Shift', 'Escape'].some((key) => isTypingKey({ key })), false);
check('shortcuts are not', [{ key: 'v', ctrlKey: true }, { key: 'a', metaKey: true }, { key: 'x', altKey: true }].some(isTypingKey), false);

// indexByName: several fluffs with the same name (live data has 42 such names).
{
  const byName = indexByName([
    { id: 292, name: "Birdy", info: "" }, { id: 322, name: "Birdy", info: "https://t.me/funkbird" },
    { id: 389, name: "Aji", info: "https://twitter.com/AjiWoof" }, { id: 642, name: "Aji", info: "https://bsky.app/profile/spicywoof.pet" },
    { id: 2, name: "Cabs", info: "https://twitter.com/Cabarun" }, { id: 387, name: "Cabs", info: "" },
    { id: 5, name: "Solo", info: "" },
  ]);
  check("prefers the entry with info over an older empty one", byName.get("Birdy").id, 322);
  check("keeps the entry with info over a newer empty one", byName.get("Cabs").id, 2);
  check("among entries with info, the newest wins", byName.get("Aji").id, 642);
  check("a single empty entry is still listed", byName.get("Solo").id, 5);
  check("one entry per name", [...byName.keys()].sort(), ["Aji", "Birdy", "Cabs", "Solo"]);
}
{
  const byName = indexByName([{ id: 292, name: "Birdy", info: "" }, { id: 322, name: "Birdy", info: "https://t.me/funkbird" }]);
  let t = 0;
  const af = createAutofill((n) => byName.get(n), () => t);
  t = 1000;
  const res = af.input({ name: "Birdy", info: "", isInputEvent: true, inputType: "insertReplacementText" });
  check("picking a duplicated name fills the link", res.info, "https://t.me/funkbird");
}

print(`${count} checks, ${failures} failures`);
if (failures) throw new Error(`${failures} autofill check(s) failed`);
