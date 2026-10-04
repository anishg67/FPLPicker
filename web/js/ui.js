// DOM helpers and the small shared components. Everything is built as real
// nodes rather than HTML strings, so player names and club names from the API
// can never be interpreted as markup.

import { formatPrice, positionShort, POSITIONS as POSITION_ORDER, num } from './models.js';
import { clubColour } from './clubs.js';

/** Hyperscript: h('div.card', { onclick }, 'text', childNode). */
export function h(spec, props, ...children) {
  const [tagPart, ...classes] = spec.split('.');
  const node = document.createElement(tagPart || 'div');
  if (classes.length) node.className = classes.join(' ');

  if (props && (typeof props !== 'object' || Array.isArray(props) || props instanceof Node)) {
    children.unshift(props);
  } else if (props) {
    for (const [key, value] of Object.entries(props)) {
      if (value === null || value === undefined || value === false) continue;
      if (key === 'class') node.className = [node.className, value].filter(Boolean).join(' ');
      else if (key === 'style' && typeof value === 'object') Object.assign(node.style, value);
      else if (key === 'dataset') Object.assign(node.dataset, value);
      else if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2), value);
      else if (key === 'html') node.innerHTML = value;
      else node.setAttribute(key, value === true ? '' : String(value));
    }
  }

  const append = (child) => {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) { child.forEach(append); return; }
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  };
  children.forEach(append);
  return node;
}

export const clear = (node) => { node.replaceChildren(); return node; };

export const text = (value) => document.createTextNode(String(value));

/** Replaces a container's contents in one go. */
export function mount(container, ...children) {
  container.replaceChildren(...children.flat(Infinity).filter(Boolean));
  return container;
}

// ---------- Shared components ----------

export function tile(label, value) {
  return h('div.tile', h('div.k', label), h('div.v', value));
}

export function pill(label, variant) {
  return h('span.pill', variant ? { class: variant } : null, label);
}

export function notice(kind, ...content) {
  return h(`div.notice.${kind}`, ...content);
}

export function progress(fraction) {
  return h('div.progress', h('span', { style: { width: `${Math.round(fraction * 100)}%` } }));
}

/**
 * A row the user picks from. `selected` draws the accent border.
 */
export function choice({ title, detail, selected, onSelect, extra }) {
  return h('button.choice', {
    type: 'button',
    'aria-pressed': selected ? 'true' : 'false',
    onclick: onSelect,
  },
  h('div.ct', title),
  detail ? h('div.cd', detail) : null,
  extra || null);
}

export function switchRow(label, checked, onChange) {
  const input = h('input', { type: 'checkbox', onchange: (event) => onChange(event.target.checked) });
  input.checked = checked;
  return h('label.switch', input, h('span', label));
}

/** A labelled slider that shows its current value. */
export function sliderRow({ label, min, max, step, value, format, onInput }) {
  const readout = h('span.small.muted.mono', format(value));
  const input = h('input', {
    type: 'range', min, max, step, value,
    oninput: (event) => {
      const next = Number(event.target.value);
      readout.textContent = format(next);
      onInput(next);
    },
  });
  return h('label.field',
    h('span.row', h('span', label), h('span.spacer'), readout),
    input);
}

// ---------- Players ----------

/** Initials for the shirt bubble when photos are off or fail to load. */
function initials(player) {
  const name = player.element.web_name || '';
  return name.replace(/[^\p{L}\s.'-]/gu, '').slice(0, 3).toUpperCase();
}

export function playerChip(player, { captain, vice, showPhotos, detail = 'standard', onSelect, showProjection }) {
  const colour = clubColour(player.team.short_name);
  const shirt = h('span.shirt', { style: { background: colour } });
  // The armband sits outside the clipped bubble, or overflow:hidden eats it.
  const bubble = h('span.bubble', shirt);

  if (showPhotos) {
    const img = h('img', {
      src: `https://resources.premierleague.com/premierleague/photos/players/110x140/p${player.element.code}.png`,
      alt: '', loading: 'lazy', decoding: 'async',
    });
    // Fall back to initials if the photo is missing for this player.
    img.addEventListener('error', () => { img.remove(); shirt.append(text(initials(player))); });
    shirt.append(img);
  } else {
    shirt.append(text(initials(player)));
  }

  if (captain) bubble.append(h('span.badge', { title: 'Captain' }, 'C'));
  else if (vice) bubble.append(h('span.badge', { title: 'Vice-captain' }, 'V'));

  const flag = player.availability.kind === 'out'
    ? h('span.flag.out', '● out')
    : player.availability.kind === 'doubtful'
      ? h('span.flag', `● ${player.availability.label}`)
      : null;

  const bits = [];
  if (detail !== 'minimal') bits.push(formatPrice(player.priceTenths));
  if (showProjection || detail === 'full') bits.push(`${player.projected.toFixed(1)} pts`);

  return h('button.player', {
    type: 'button',
    onclick: onSelect,
    title: `${player.element.first_name} ${player.element.second_name} — ${player.team.name}`,
  },
  bubble,
  h('span.name', player.element.web_name),
  bits.length ? h('span.meta', bits.join(' · ')) : null,
  flag);
}

export function playerRow(player, { onSelect, selected, trailing, showProjection = true } = {}) {
  return h('button.prow', {
    type: 'button',
    'aria-pressed': selected ? 'true' : 'false',
    onclick: onSelect,
  },
  h('span.pos', positionShort(player.position)),
  h('span.who',
    h('span.n', player.element.web_name),
    h('span.d', `${player.team.short_name} · ${num(player.element.selected_by_percent).toFixed(1)}% owned`)),
  trailing || h('span.nums',
    h('span.pr', formatPrice(player.priceTenths)),
    showProjection ? h('span.pj', `${player.projected.toFixed(1)} pts/GW`) : null));
}

/** The XI laid out by position, goalkeeper at the top. */
export function pitch(squad, options, onSelect) {
  const lines = POSITION_ORDER.map((position) => {
    const line = squad.starting.filter((player) => player.position === position);
    if (!line.length) return null;
    return h('div.pitch-line', line.map((player) => playerChip(player, {
      ...options,
      captain: player.id === squad.captain.id,
      vice: player.id === squad.viceCaptain.id,
      onSelect: onSelect ? () => onSelect(player) : undefined,
    })));
  });
  return h('div.pitch', lines.filter(Boolean));
}

export function benchStrip(squad, options, onSelect) {
  return h('div.bench-strip',
    h('div.label', 'Bench — in the order they come on'),
    h('div.pitch-line', squad.bench.map((player) => playerChip(player, {
      ...options,
      captain: false,
      vice: false,
      onSelect: onSelect ? () => onSelect(player) : undefined,
    }))));
}

// ---------- Sheet ----------

let activeSheet = null;

export function closeSheet() {
  if (!activeSheet) return;
  activeSheet.remove();
  activeSheet = null;
  document.body.style.overflow = '';
}

/** A modal panel. Returns the body node so callers can re-render in place. */
export function openSheet(title, build, { onClose } = {}) {
  closeSheet();
  const body = h('div.stack');
  const close = () => { closeSheet(); onClose?.(); };

  const panel = h('div.sheet', { role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
    h('div.sheet-head',
      h('h2', title),
      h('button.btn.btn-sm.btn-ghost', { type: 'button', 'aria-label': 'Close', onclick: close }, 'Done')),
    body);

  const backdrop = h('div.sheet-backdrop', {
    onclick: (event) => { if (event.target === backdrop) close(); },
  }, panel);

  const onKey = (event) => {
    if (event.key !== 'Escape') return;
    document.removeEventListener('keydown', onKey);
    close();
  };
  document.addEventListener('keydown', onKey);

  document.getElementById('sheet-root').append(backdrop);
  document.body.style.overflow = 'hidden';
  activeSheet = backdrop;
  build(body);
  panel.querySelector('button')?.focus();
  return body;
}

// ---------- Dialogs ----------
//
// Native alert/confirm/prompt are blocked outright in some embedding contexts
// and look nothing like the rest of the page, so the app rolls its own.

export function toast(message) {
  const node = h('div.toast', { role: 'status' }, message);
  document.getElementById('sheet-root').append(node);
  setTimeout(() => node.classList.add('leaving'), 2600);
  setTimeout(() => node.remove(), 3100);
}

export function confirmSheet({ title, body, confirmLabel = 'Confirm', destructive = false, onConfirm }) {
  openSheet(title, (panel) => mount(panel,
    h('p.small.muted', body),
    h('button.btn.btn-primary.btn-wide', {
      type: 'button',
      style: destructive ? { background: 'var(--bad)', color: '#fff' } : null,
      onclick: () => { closeSheet(); onConfirm(); },
    }, confirmLabel),
    h('button.btn.btn-ghost.btn-wide', { type: 'button', onclick: closeSheet }, 'Cancel')));
}

export function promptSheet({ title, body, value = '', confirmLabel = 'Save', onConfirm }) {
  openSheet(title, (panel) => {
    const input = h('input', { type: 'text', value });
    const submit = () => {
      const entered = input.value.trim();
      closeSheet();
      onConfirm(entered);
    };
    input.addEventListener('keydown', (event) => { if (event.key === 'Enter') submit(); });
    mount(panel,
      body ? h('p.small.muted', body) : null,
      input,
      h('button.btn.btn-primary.btn-wide', { type: 'button', onclick: submit }, confirmLabel),
      h('button.btn.btn-ghost.btn-wide', { type: 'button', onclick: closeSheet }, 'Cancel'));
    input.focus();
    input.select();
  });
}
