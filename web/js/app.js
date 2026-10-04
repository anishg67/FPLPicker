// Squad XI for the web. Same engine as the iOS app; everything runs in the
// browser, and nothing but the public fantasy data ever leaves it.

import {
  POSITIONS, GOALKEEPER, CHIPS, CHIP_META, MODE_META,
  positionShort, positionName, squadCount, formatPrice, num,
  defaultPreferences, effectivePreferences, emptyChipUsage, hasUsedChip, toggleChip,
  validateSquad, isOut,
} from './models.js';
import { ProjectionEngine } from './projection.js';
import { SquadOptimizer, OptimizerError, rebuild } from './optimizer.js';
import { TransferPlanner } from './transfers.js';
import { ChipPlanner } from './chips.js';
import { loadLeagueData, loadTeam, FPLError } from './api.js';
import { FixturePlanner } from './fixtures.js';
import { QUESTIONS, evaluateSurvey, knowledgeLabel, TEAM_STATUS_META, searchGlossary } from './content.js';
import { clubColour } from './clubs.js';
import {
  h, mount, tile, pill, notice, progress, choice, switchRow, sliderRow,
  pitch, benchStrip, playerRow, playerChip, openSheet, closeSheet,
  toast, confirmSheet, promptSheet, fixtureRun, fixtureLegend,
} from './ui.js';

// ---------------------------------------------------------------- persistence

const KEY = 'squadxi.';

function load(name, fallback) {
  try {
    const raw = localStorage.getItem(KEY + name);
    return raw === null ? fallback : JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function save(name, value) {
  try {
    localStorage.setItem(KEY + name, JSON.stringify(value));
  } catch { /* private mode, or quota — the app works without persistence */ }
}

function defaultSettings() {
  return {
    accent: 'mint',
    theme: 'dark',
    showPlayerPhotos: true,
    cardDetail: 'standard',
    showOwnership: false,
    defaultBudgetTenths: 1000,
  };
}

function emptyTeam() {
  return {
    playerIDs: [],
    bankTenths: 0,
    freeTransfers: 1,
    chipsUsed: emptyChipUsage(),
    entryID: null,
    teamName: null,
    managerName: null,
    reportedValueTenths: null,
  };
}

// ---------------------------------------------------------------------- state

const state = {
  screen: 'loading',
  tab: 'squad',
  loadingNote: 'Fetching live prices, form and fixtures…',
  data: null,
  rated: [],
  ratedByID: new Map(),
  squad: null,
  /** Looks up what each club has coming; rebuilt whenever the league data is. */
  fixturePlanner: null,
  transferPlan: null,
  /** Which suggested transfers the user has ticked, by move id. */
  selectedMoves: new Set(),
  showBenchFixtures: false,
  chipAdvice: null,
  error: null,
  busy: false,

  survey: load('survey', null),
  prefs: { ...defaultPreferences(), ...load('prefs', {}) },
  settings: { ...defaultSettings(), ...load('settings', {}) },
  team: { ...emptyTeam(), ...load('team', {}) },
  savedTeams: load('saved', []),

  // Survey progress
  surveyIndex: 0,
  surveyAnswers: [],
  surveyResult: null,
  surveyMode: 'auto',

  // Setup progress
  setupStage: null,       // 'import' | 'manual' | 'prefs'
  teamIDInput: '',
};

const screen = () => document.getElementById('screen');

const cardOptions = () => ({
  showPhotos: state.settings.showPlayerPhotos,
  detail: state.settings.cardDetail,
  showProjection: state.settings.cardDetail === 'full',
});

function applyTheme() {
  document.documentElement.dataset.accent = state.settings.accent;
  document.documentElement.dataset.theme = state.settings.theme;
}

// --------------------------------------------------------------- engine calls

/** Re-rates every player. Needed whenever a preference the model reads changes. */
function rateAll() {
  const prefs = effectivePreferences(state.prefs);
  state.rated = new ProjectionEngine(state.data, prefs).rateAll();
  state.ratedByID = new Map(state.rated.map((player) => [player.id, player]));
  state.fixturePlanner = new FixturePlanner(state.data);
}

const ownedPlayers = () => state.team.playerIDs
  .map((id) => state.ratedByID.get(id))
  .filter(Boolean);

const hasTeam = () => state.team.playerIDs.length === 15;

/** Budget for a squad the user already owns: what it's worth plus the bank. */
function ownedBudget() {
  const value = ownedPlayers().reduce((sum, player) => sum + player.priceTenths, 0);
  return value + state.team.bankTenths;
}

/** Builds the squad to show: the user's own team, or a fresh suggestion. */
function buildSquad() {
  state.error = null;
  state.transferPlan = null;
  state.transferPlanner = null;
  state.chipAdvice = null;

  try {
    if (hasTeam()) {
      const players = ownedPlayers();
      const check = validateSquad(players, state.prefs.maxPerClub);
      state.squad = rebuild(players, ownedBudget(), check.isValid ? [] : [check.message], false);

      state.transferPlanner = new TransferPlanner({
        squad: players,
        rated: state.rated,
        bankTenths: state.team.bankTenths,
        freeTransfers: state.team.freeTransfers,
        maxPerClub: state.prefs.maxPerClub,
      });
      state.transferPlan = state.transferPlanner.plan();
      // Start with the recommended plan ticked, so the headline number answers
      // "what do I get if I just do what it says?" without any tapping.
      state.selectedMoves = new Set(state.transferPlan.moves.map((move) => move.id));
    } else {
      const prefs = effectivePreferences(state.prefs);
      state.squad = new SquadOptimizer(state.rated, prefs).optimize();
    }

    state.chipAdvice = new ChipPlanner({
      squad: state.squad,
      rated: state.rated,
      data: state.data,
      usage: state.team.chipsUsed,
    }).plan();
  } catch (error) {
    state.squad = null;
    state.error = error instanceof OptimizerError ? error.message : `Something went wrong: ${error.message}`;
  }
}

/** Runs work that takes a moment, with the spinner up so the page stays honest. */
function withBusy(note, work) {
  state.busy = true;
  state.loadingNote = note;
  render();
  // Two frames, so the browser actually paints the spinner before the engine
  // blocks the main thread.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    try {
      work();
    } finally {
      state.busy = false;
      render();
    }
  }));
}

// ---------------------------------------------------------------------- router

function render() {
  applyTheme();
  const root = screen();
  document.getElementById('glossary-button').classList.toggle('hidden', state.screen === 'loading');

  if (state.busy || state.screen === 'loading') {
    renderTabs();
    mount(root, h('div.loading-wrap',
      h('div.spinner', { role: 'status', 'aria-label': 'Working' }),
      h('p.muted', state.loadingNote)));
    return;
  }

  renderTabs();
  switch (state.screen) {
    case 'survey': mount(root, renderSurvey()); break;
    case 'setup': mount(root, renderSetup()); break;
    default: mount(root, renderMain()); break;
  }
}

const TABS = [
  { id: 'squad', icon: '⚽️', label: 'Squad' },
  { id: 'transfers', icon: '⇄', label: 'Transfers' },
  { id: 'chips', icon: '🃏', label: 'Chips' },
  { id: 'saved', icon: '☆', label: 'Saved' },
  { id: 'settings', icon: '⚙', label: 'Settings' },
];

function renderTabs() {
  const bar = document.getElementById('tabbar');
  bar.classList.toggle('hidden', state.screen !== 'main');
  if (state.screen !== 'main') return;
  mount(bar, TABS.map((item) => h('button.tab', {
    type: 'button',
    role: 'tab',
    'aria-selected': state.tab === item.id ? 'true' : 'false',
    onclick: () => { state.tab = item.id; render(); window.scrollTo({ top: 0 }); },
  }, h('span.ic', item.icon), h('span', item.label))));
}

function setSub(line) {
  document.getElementById('masthead-sub').textContent = line;
}

// ---------------------------------------------------------------------- survey

function renderSurvey() {
  if (state.surveyResult) return renderSurveyResult();

  const index = state.surveyIndex;
  const question = QUESTIONS[index];
  setSub(`Question ${index + 1} of ${QUESTIONS.length}`);

  const answer = (optionIndex) => {
    state.surveyAnswers[index] = optionIndex;
    if (index + 1 < QUESTIONS.length) {
      state.surveyIndex = index + 1;
    } else {
      const result = evaluateSurvey(state.surveyAnswers);
      state.surveyResult = result;
      state.surveyMode = result.recommended;
    }
    render();
    window.scrollTo({ top: 0 });
  };

  return h('div.stack',
    progress((index + 1) / QUESTIONS.length),
    h('div.stack',
      h('h1', question.prompt),
      h('p.muted', question.subtitle)),
    h('div.stack', question.options.map((option, optionIndex) => choice({
      title: option.text,
      detail: option.detail,
      selected: state.surveyAnswers[index] === optionIndex,
      onSelect: () => answer(optionIndex),
    }))),
    question.showsGlossary
      ? h('button.btn.btn-sm.btn-ghost', { type: 'button', onclick: showGlossary }, 'What do these mean?')
      : null,
    index > 0
      ? h('button.btn.btn-ghost.btn-sm', {
        type: 'button',
        onclick: () => { state.surveyIndex = index - 1; render(); },
      }, '← Back')
      : null);
}

function renderSurveyResult() {
  const result = state.surveyResult;
  setSub('Your answers');

  const finish = () => {
    state.prefs.mode = state.surveyMode;
    state.prefs.budgetTenths = state.settings.defaultBudgetTenths;
    state.survey = result;
    save('survey', result);
    save('prefs', state.prefs);
    state.screen = 'setup';
    state.setupStage = result.teamStatus === 'none' ? 'prefs' : result.teamStatus === 'importByID' ? 'import' : 'manual';
    render();
    window.scrollTo({ top: 0 });
  };

  return h('div.stack',
    h('h1', "Here's how I'd run it for you"),
    h('p.muted', `Based on your answers I'd suggest ${MODE_META[result.recommended].title}. Change it if you disagree — nothing here is locked in.`),
    h('div.card',
      h('div.row', h('span.small.muted', 'Football knowledge'), h('span.spacer'),
        h('span.small.mono', `${result.knowledge}/100`)),
      h('div', { style: { marginTop: '8px' } }, progress(result.knowledge / 100)),
      h('div.small.muted', { style: { marginTop: '6px' } }, knowledgeLabel(result.knowledge))),
    h('h2', 'How much do you want to decide?'),
    h('div.stack', Object.keys(MODE_META).map((mode) => choice({
      title: MODE_META[mode].title,
      detail: MODE_META[mode].blurb,
      selected: state.surveyMode === mode,
      onSelect: () => { state.surveyMode = mode; render(); },
      extra: mode === result.recommended ? h('div', { style: { marginTop: '8px' } }, pill('Suggested', 'accent')) : null,
    }))),
    result.teamStatus !== 'none'
      ? notice('info', `Next I'll ask for your existing squad, then suggest transfers from it.`)
      : null,
    h('button.btn.btn-primary.btn-wide', { type: 'button', onclick: finish }, 'Continue'),
    h('button.btn.btn-ghost.btn-sm', {
      type: 'button',
      onclick: () => { state.surveyResult = null; state.surveyIndex = QUESTIONS.length - 1; render(); },
    }, '← Change an answer'));
}

// ----------------------------------------------------------------------- setup

function renderSetup() {
  switch (state.setupStage) {
    case 'import': return renderImport();
    case 'manual': return renderManual();
    default: return renderPrefsSetup();
  }
}

function goToMain() {
  withBusy('Working out the best legal squad…', () => {
    rateAll();
    buildSquad();
    state.screen = 'main';
    state.tab = 'squad';
  });
}

function renderImport() {
  setSub('Import your team');

  const idInput = h('input', {
    type: 'text',
    inputmode: 'numeric',
    placeholder: '1234567',
    value: state.teamIDInput,
    oninput: (event) => { state.teamIDInput = event.target.value.replace(/[^\d]/g, ''); },
  });

  const errorSlot = h('div');

  const doImport = async () => {
    const id = Number.parseInt(state.teamIDInput, 10);
    if (!Number.isFinite(id) || id <= 0) {
      mount(errorSlot, notice('error', 'Enter the number from the address bar.'));
      return;
    }
    mount(errorSlot, h('div.row', h('div.spinner'), h('span.small.muted', 'Fetching your squad…')));
    try {
      const team = await loadTeam(id);
      state.team = { ...emptyTeam(), ...team };
      save('team', state.team);
      goToMain();
    } catch (error) {
      mount(errorSlot, notice('error',
        error instanceof FPLError ? error.message : `Couldn't import that team: ${error.message}`),
      error instanceof FPLError && error.kind === 'seasonNotStarted'
        ? h('button.btn.btn-sm', {
          type: 'button', style: { marginTop: '10px' },
          onclick: () => { state.setupStage = 'manual'; render(); },
        }, 'Enter my 15 by hand instead')
        : null);
    }
  };

  const step = (number, ...content) => h('div.row',
    h('span.pill.accent', String(number)),
    h('span.small', ...content));

  return h('div.stack',
    h('h1', 'Your team ID'),
    h('p.muted', "It's the number in the address bar when you look at your own team on the web."),
    h('div.card.stack',
      step(1, 'Log in to your account at ',
        h('a', {
          href: 'https://fantasy.premierleague.com',
          target: '_blank',
          rel: 'noopener noreferrer',
          style: { color: 'var(--accent-1)' },
        }, 'fantasy.premierleague.com ↗')),
      step(2, 'Open the ', h('strong', 'Points'), ' tab'),
      step(3, 'Read the team number out of the address bar, like ', h('strong', '1234567'))),
    h('label.field', h('span', 'Team ID'), idInput),
    errorSlot,
    h('button.btn.btn-primary.btn-wide', { type: 'button', onclick: doImport }, 'Import my squad'),
    h('div.row.wrap',
      h('button.btn.btn-sm.btn-ghost', {
        type: 'button',
        onclick: () => { state.setupStage = 'manual'; render(); },
      }, 'Enter 15 players by hand'),
      h('button.btn.btn-sm.btn-ghost', {
        type: 'button',
        onclick: () => { state.setupStage = 'prefs'; render(); },
      }, 'Build me a squad instead')));
}

function renderManual() {
  setSub('Enter your squad');
  const players = ownedPlayers();
  const check = validateSquad(players, state.prefs.maxPerClub);

  const remove = (id) => {
    state.team.playerIDs = state.team.playerIDs.filter((item) => item !== id);
    save('team', state.team);
    render();
  };

  const addFor = (position) => openPlayerPicker({
    title: `Add a ${positionName(position).toLowerCase()}`,
    position,
    exclude: new Set(state.team.playerIDs),
    clubLimitSquad: players,
    onPick: (player) => {
      state.team.playerIDs = [...state.team.playerIDs, player.id];
      save('team', state.team);
      closeSheet();
      render();
    },
  });

  const positionBlock = (position) => {
    const mine = players.filter((player) => player.position === position);
    const need = squadCount(position) - mine.length;
    return h('div.card.stack',
      h('div.row',
        h('h3', positionName(position) + 's'),
        h('span.spacer'),
        h('span.small.muted.mono', `${mine.length}/${squadCount(position)}`)),
      mine.length
        ? h('div.plist', mine.map((player) => playerRow(player, {
          showProjection: false,
          trailing: h('span.row',
            h('span.small.mono.muted', formatPrice(player.priceTenths)),
            h('span.pill', '✕')),
          onSelect: () => remove(player.id),
        })))
        : null,
      need > 0
        ? h('button.btn.btn-sm.btn-wide', { type: 'button', onclick: () => addFor(position) },
          `Add ${need} ${positionShort(position)}`)
        : null);
  };

  const spend = players.reduce((sum, player) => sum + player.priceTenths, 0);

  return h('div.stack',
    h('h1', 'Your 15 players'),
    h('p.muted', 'Add each one, then tell me what you have in the bank and how many free transfers you have saved.'),
    h('div.tiles',
      tile('Picked', `${players.length}/15`),
      tile('Squad value', formatPrice(spend)),
      tile('In the bank', formatPrice(state.team.bankTenths))),
    check.message ? notice('warn', check.message) : null,
    POSITIONS.map(positionBlock),
    resourcesCard(),
    chipsUsedCard(),
    h('button.btn.btn-primary.btn-wide', {
      type: 'button',
      disabled: !check.isValid,
      onclick: goToMain,
    }, check.isValid ? 'Use this squad' : 'Finish your squad first'),
    h('button.btn.btn-ghost.btn-sm', {
      type: 'button',
      onclick: () => { state.setupStage = 'import'; render(); },
    }, 'Import with my team ID instead'));
}

/** Bank and free transfers — the resources a transfer plan is built from. */
function resourcesCard() {
  const bank = h('input', {
    type: 'number', min: '0', step: '0.1',
    value: (state.team.bankTenths / 10).toFixed(1),
    oninput: (event) => {
      state.team.bankTenths = Math.max(0, Math.round(Number(event.target.value || 0) * 10));
      save('team', state.team);
    },
  });
  const transfers = h('select', {
    onchange: (event) => {
      state.team.freeTransfers = Number(event.target.value);
      save('team', state.team);
    },
  }, [0, 1, 2, 3, 4, 5].map((count) => {
    const option = h('option', { value: String(count) }, String(count));
    if (count === state.team.freeTransfers) option.selected = true;
    return option;
  }));

  return h('div.card.stack',
    h('h3', 'What you have to work with'),
    h('label.field', h('span', 'In the bank (£m)'), bank),
    h('label.field', h('span', 'Free transfers saved'), transfers));
}

/** Which chips have already been played. */
function chipsUsedCard() {
  const currentGameweek = state.data.nextEvent?.id ?? 1;
  const halves = currentGameweek >= 20 ? [true] : [false, true];

  const block = (secondHalf) => h('div.stack',
    h('div.small.muted', secondHalf ? 'Second half (gameweek 20 onwards)' : 'First half (up to gameweek 19)'),
    h('div.stack', CHIPS.map((chip) => {
      const used = hasUsedChip(state.team.chipsUsed, chip, secondHalf);
      return switchRow(CHIP_META[chip].name, used, () => {
        toggleChip(state.team.chipsUsed, chip, secondHalf);
        save('team', state.team);
        render();
      });
    })));

  return h('div.card.stack',
    h('h3', 'Chips you have already played'),
    h('p.small.muted', "Each chip comes twice a season. Tick the ones that are gone so I don't suggest them."),
    halves.map(block));
}

function renderPrefsSetup() {
  setSub('Set it up');
  return h('div.stack',
    h('h1', 'Build me a squad'),
    h('p.muted', state.prefs.mode === 'auto'
      ? 'Nothing to set — I\'ll use the standard £100.0m budget and pick from the whole league.'
      : 'Set what you care about. Everything else falls back to the game\'s defaults.'),
    preferencesCard({ showApply: false }),
    h('button.btn.btn-primary.btn-wide', { type: 'button', onclick: goToMain }, 'Build my squad'),
    h('button.btn.btn-ghost.btn-sm', {
      type: 'button',
      onclick: () => { state.setupStage = 'import'; render(); },
    }, 'I already have a team'));
}

// ------------------------------------------------------------------ main shell

function renderMain() {
  switch (state.tab) {
    case 'transfers': return renderTransfers();
    case 'chips': return renderChips();
    case 'saved': return renderSaved();
    case 'settings': return renderSettings();
    default: return renderSquad();
  }
}

// ------------------------------------------------------------------ squad tab

function renderSquad() {
  const next = state.data.nextEvent;
  setSub(next ? `${next.name} · ${state.data.elements.length} players priced live` : 'Live data');

  if (state.error) {
    return h('div.stack',
      h('h1', 'Squad'),
      notice('error', state.error),
      h('button.btn.btn-wide', { type: 'button', onclick: () => { state.tab = 'settings'; render(); } },
        'Change your settings'));
  }
  if (!state.squad) return notice('info', 'No squad yet.');

  const squad = state.squad;
  const options = cardOptions();
  const pitchNode = pitch(squad, options, showPlayer);
  const benchNode = benchStrip(squad, options, showPlayer);

  const overBudget = squad.remainingTenths < 0;

  return h('div.stack',
    h('div.row.wrap',
      h('h1', hasTeam() ? (state.team.teamName || 'Your squad') : 'Your suggested squad'),
      h('span.spacer'),
      hasTeam() ? pill('Your team') : pill(MODE_META[state.prefs.mode].title, 'accent')),
    state.team.managerName ? h('p.small.muted', state.team.managerName) : null,

    h('div.tiles',
      tile('Projected', `${squad.projectedPoints.toFixed(1)} pts`),
      tile('Formation', squad.formation),
      tile('Spent', formatPrice(squad.totalCostTenths)),
      tile(overBudget ? 'Over by' : 'Left', formatPrice(Math.abs(squad.remainingTenths))),
      tile('Captain', squad.captain.element.web_name)),

    h('p.tiny.muted', 'Projected points are for one gameweek, counting the XI with the captain doubled.'),

    squad.notes.length ? notice('info', squad.notes.join(' ')) : null,
    overBudget ? notice('warn', 'This squad costs more than your budget.') : null,

    h('div.two-col',
      h('div.stack', pitchNode, benchNode, fixtureTickerCard(squad)),
      h('div.stack',
        h('div.card.stack',
          h('h3', 'Actions'),
          h('button.btn.btn-wide', { type: 'button', onclick: rebuildSuggestion },
            hasTeam() ? 'Suggest a fresh squad from scratch' : 'Rebuild with current settings'),
          h('button.btn.btn-wide', { type: 'button', onclick: saveCurrentSquad }, 'Save this squad'),
          h('button.btn.btn-wide', { type: 'button', onclick: shareCurrentSquad }, 'Share'),
          h('p.tiny.muted', 'Tap any player to see the reasoning or swap them out.')),
        state.transferPlan && !state.transferPlan.isEmpty
          ? h('div.card.stack',
            h('h3', 'Transfers waiting'),
            h('p.small.muted', `${state.transferPlan.moves.length} suggested, worth ${state.transferPlan.netGain.toFixed(1)} pts a week after any hit.`),
            h('button.btn.btn-sm.btn-wide', {
              type: 'button',
              onclick: () => { state.tab = 'transfers'; render(); },
            }, 'See them'))
          : null,
        bestChipCard())));
}

/**
 * The next five gameweeks for everyone in the starting XI.
 *
 * Sitting next to the pitch, this answers the question the projection can only
 * summarise: who each player actually faces. The model already weighs fixture
 * difficulty, but a manager wants to see the run before trusting it.
 */
function fixtureTickerCard(squad, count = 5) {
  const planner = state.fixturePlanner;
  const gameweeks = planner ? planner.actionableGameweeks.slice(0, count) : [];

  if (!gameweeks.length) {
    return h('div.card.stack',
      h('h3', `Next ${count} fixtures`),
      h('p.small.muted', 'No fixtures scheduled yet.'));
  }

  const benchIDs = new Set(squad.bench.map((player) => player.id));
  const players = state.showBenchFixtures ? [...squad.starting, ...squad.bench] : squad.starting;

  return h('div.card.stack',
    h('div.row.wrap',
      h('h3', `Next ${count} fixtures`),
      h('span.spacer'),
      h('button.btn.btn-sm.btn-ghost', {
        type: 'button',
        onclick: () => { state.showBenchFixtures = !state.showBenchFixtures; render(); },
      }, state.showBenchFixtures ? 'XI only' : 'Show bench')),

    h('div.ticker',
      h('div.ticker-row.head',
        h('span', ''),
        h('span.fx-run', gameweeks.map((gameweek) => h('span.gw', `GW${gameweek}`)))),
      players.map((player) => h('div.ticker-row', {
        class: benchIDs.has(player.id) ? 'benched' : null,
      },
      h('span.who',
        h('span.n', player.element.web_name),
        h('span.c', player.team.short_name)),
      fixtureRun(planner.next(count, player.element.team), { compact: true })))),

    fixtureLegend());
}

function bestChipCard() {
  const plays = (state.chipAdvice || []).filter((advice) => advice.verdict === 'play');
  if (!plays.length) return null;
  return h('div.card.stack',
    h('h3', 'Chip to play'),
    plays.map((advice) => h('div.small',
      h('strong', CHIP_META[advice.chip].name), ` — ${advice.headline}`)),
    h('button.btn.btn-sm.btn-wide', {
      type: 'button',
      onclick: () => { state.tab = 'chips'; render(); },
    }, 'See the reasoning'));
}

function rebuildSuggestion() {
  withBusy('Searching for a better squad…', () => {
    // A fresh suggestion ignores the owned squad on purpose — that's what makes
    // it a suggestion rather than a report on what you already have.
    const keptTeam = state.team;
    state.team = { ...emptyTeam(), chipsUsed: keptTeam.chipsUsed };
    buildSquad();
    state.team = keptTeam;
    if (state.squad) state.squad.edited = false;
  });
}

// -------------------------------------------------------------- transfers tab

function renderTransfers() {
  setSub('Transfers');

  if (!hasTeam()) {
    return h('div.stack',
      h('h1', 'Transfers'),
      notice('info', 'Transfer advice works from the squad you already own. Import your team, or enter your 15 by hand, and I\'ll suggest swaps from it.'),
      h('button.btn.btn-primary.btn-wide', {
        type: 'button',
        onclick: () => { state.screen = 'setup'; state.setupStage = 'import'; render(); },
      }, 'Import my team'),
      h('button.btn.btn-wide', {
        type: 'button',
        onclick: () => { state.screen = 'setup'; state.setupStage = 'manual'; render(); },
      }, 'Enter my 15 players by hand'));
  }

  const plan = state.transferPlan;
  const planner = state.transferPlanner;
  if (!plan || !planner) return notice('info', 'No plan yet.');

  const offered = [...plan.moves, ...plan.alternatives];
  const chosen = () => offered.filter((move) => state.selectedMoves.has(move.id));

  // The outlook panel is redrawn on its own as moves are ticked, so the page
  // doesn't jump back to the top on every tap.
  const outlookSlot = h('div.outlook');
  const drawOutlook = () => mount(outlookSlot, outlookPanel(planner.outlook(chosen())));

  const toggle = (move, row) => {
    if (state.selectedMoves.has(move.id)) state.selectedMoves.delete(move.id);
    else state.selectedMoves.add(move.id);
    row.setAttribute('aria-pressed', state.selectedMoves.has(move.id) ? 'true' : 'false');
    drawOutlook();
  };

  const pickRow = (move, recommended) => {
    const row = h('button.pick-row', {
      type: 'button',
      'aria-pressed': state.selectedMoves.has(move.id) ? 'true' : 'false',
    },
    h('span.tick', '✓'),
    h('span.body',
      h('span.names',
        h('span.out', move.outgoing.element.web_name),
        ' → ',
        h('span.in', move.incoming.element.web_name)),
      h('span.tiny.muted', `${move.outgoing.team.short_name} ${formatPrice(move.outgoing.priceTenths)} → ${move.incoming.team.short_name} ${formatPrice(move.incoming.priceTenths)} · ${positionShort(move.outgoing.position)}`),
      h('span.row',
        h('span.tiny.good', { style: { fontWeight: '700', flex: 'none' } }, `+${move.gain.toFixed(1)} pts/GW`),
        state.fixturePlanner
          ? h('span', { style: { flex: '1', minWidth: '0', maxWidth: '150px' } },
            fixtureRun(state.fixturePlanner.next(3, move.incoming.element.team), { compact: true }))
          : null)),
    recommended ? pill('Pick', 'accent') : null);

    row.addEventListener('click', () => toggle(move, row));
    return row;
  };

  const body = plan.isEmpty && !plan.alternatives.length
    ? notice('info', 'Nothing worth doing. No single swap improves your projected points by enough to bother — holding your free transfer is the better move.')
    : h('div.stack',
      h('p.small.muted', "Tick the ones you'd make. The projection updates as you go."),
      plan.moves.map((move) => pickRow(move, true)),
      plan.alternatives.length
        ? h('details.disclose',
          h('summary', 'Other moves worth a look'),
          h('div.stack', { style: { marginTop: '8px' } },
            h('p.tiny.muted', 'Each of these is legal on its own, applied to the squad after the recommended plan.'),
            plan.alternatives.map((move) => pickRow(move, false))))
        : null,
      outlookSlot);

  drawOutlook();

  return h('div.stack',
    h('h1', 'Transfers'),
    h('div.tiles',
      tile('Free transfers', String(plan.freeTransfers)),
      tile('In the bank', formatPrice(plan.bankTenths)),
      tile('Suggested', String(plan.moves.length)),
      tile('Alternatives', String(plan.alternatives.length))),
    h('div.card', body),
    resourcesCard());
}

/** What the ticked transfers would do to the squad's projected score. */
function outlookPanel(outlook) {
  const figure = (label, value, tone) => h('div.outlook-figure',
    h('div.k', label),
    h('div.v', { class: tone || null }, value.toFixed(1)));

  const apply = () => {
    const moves = outlook.applied;
    if (!moves.length) return;
    for (const move of moves) {
      state.team.playerIDs = state.team.playerIDs.map((id) => (id === move.outgoing.id ? move.incoming.id : id));
      state.team.bankTenths -= move.priceDelta;
    }
    save('team', state.team);
    withBusy('Reworking the plan…', buildSquad);
  };

  return h('div.outlook',
    h('div.outlook-top',
      figure('Now', outlook.before),
      h('span.arrow', '→'),
      figure('After', outlook.after, outlook.gain >= 0 ? 'good' : 'bad-text'),
      h('div.outlook-delta',
        h('div.v', { class: outlook.gain >= 0 ? 'good' : 'bad-text' },
          `${outlook.gain >= 0 ? '+' : ''}${outlook.gain.toFixed(1)}`),
        h('div.k', 'pts / gameweek'))),

    outlook.isEmpty
      ? h('p.small.muted', "Nothing ticked — this is what you'd score as you are.")
      : h('div.stack',
        h('div.chips',
          pill(`${outlook.count} transfer${outlook.count === 1 ? '' : 's'}`),
          outlook.pointsHit > 0 ? pill(`−${outlook.pointsHit} hit`, 'warn') : pill('No hit', 'accent'),
          pill(`net ${outlook.net >= 0 ? '+' : ''}${outlook.net.toFixed(1)}`, outlook.net >= 0 ? 'accent' : 'warn'),
          pill(`bank ${formatPrice(outlook.bankAfter)}`)),

        outlook.weeksToBreakEven
          ? h('p.small.warn-text', { style: { color: 'var(--warn)' } },
            `The hit pays for itself after ${outlook.weeksToBreakEven} gameweek${outlook.weeksToBreakEven === 1 ? '' : 's'} if the gain holds.`)
          : null,

        outlook.rejected.length
          ? h('p.small', { style: { color: 'var(--warn)' } },
            `${outlook.rejected.length} of your picks can't be made alongside the others — same player out, or it would break the ${state.prefs.maxPerClub}-per-club limit. ${outlook.rejected.map((move) => move.incoming.element.web_name).join(', ')} left out.`)
          : null,

        h('button.btn.btn-primary.btn-wide', { type: 'button', onclick: apply },
          `Apply ${outlook.count} transfer${outlook.count === 1 ? '' : 's'}`)),

    h('p.tiny.muted', 'Projected points are the best legal XI with the captain doubled, for one gameweek.'));
}

// ------------------------------------------------------------------ chips tab

function renderChips() {
  setSub('Chip strategy');
  const advice = state.chipAdvice || [];

  const planner = state.squad
    ? new ChipPlanner({ squad: state.squad, rated: state.rated, data: state.data, usage: state.team.chipsUsed })
    : null;
  const weeks = planner ? planner.upcomingGameweeks : [];

  const card = (item) => {
    const meta = CHIP_META[item.chip];
    return h(`div.card.chip-card.${item.verdict}`,
      h('div.row.wrap',
        h('h3', meta.name),
        h('span.spacer'),
        pill(item.headline, item.verdict === 'play' ? 'accent' : item.verdict === 'hold' ? 'warn' : null)),
      h('p.small.muted', { style: { marginTop: '8px' } }, meta.summary),
      h('p.small', { style: { marginTop: '8px' } }, item.detail),
      item.verdict === 'play' || item.verdict === 'hold'
        ? h('details.disclose',
          h('summary', 'How this was judged'),
          h('div.stack',
            h('p.small.muted', meta.ideal),
            h('p.small.muted', `Best week looks ${item.multiple.toFixed(2)}× an ordinary one. This chip needs ${meta.playMultiple.toFixed(2)}× before it's worth burning.`),
            item.ranked.length
              ? h('div.chips', item.ranked.map((entry) => pill(
                `GW${entry.gameweek}: ${item.chip === 'wildcard' ? `${((entry.gain - 1) * 100).toFixed(0)}%` : `${entry.gain.toFixed(1)} pts`}`,
              )))
              : null))
        : null);
  };

  return h('div.stack',
    h('h1', 'Chips'),
    h('p.muted', 'Four one-off boosts, each available twice a season. Most of their value sits in double and blank gameweeks, so "hold" is usually the right answer until the fixtures move.'),
    weeks.length
      ? h('p.small.muted', `Looking at gameweeks ${weeks[0]}–${weeks[weeks.length - 1]}.`)
      : notice('info', 'No gameweeks left with a deadline still ahead.'),
    advice.map(card),
    chipsUsedCard());
}

// ------------------------------------------------------------------ saved tab

function saveCurrentSquad() {
  if (!state.squad) return;
  const defaultName = hasTeam()
    ? `${state.team.teamName || 'My squad'} — ${new Date().toLocaleDateString()}`
    : `${MODE_META[state.prefs.mode].title} — ${new Date().toLocaleDateString()}`;
  const squad = state.squad;

  promptSheet({
    title: 'Save this squad',
    body: 'Kept in this browser only — nothing is uploaded.',
    value: defaultName,
    onConfirm: (name) => {
      const entry = {
        id: `${Date.now()}`,
        name: name || defaultName,
        savedAt: new Date().toISOString(),
        playerIDs: squad.squad.map((player) => player.id),
        captainID: squad.captain.id,
        budgetTenths: squad.budgetTenths,
        formation: squad.formation,
        projected: squad.projectedPoints,
      };
      state.savedTeams = [entry, ...state.savedTeams].slice(0, 40);
      save('saved', state.savedTeams);
      state.tab = 'saved';
      render();
      toast('Squad saved.');
    },
  });
}

function renderSaved() {
  setSub('Saved squads');

  if (!state.savedTeams.length) {
    return h('div.stack',
      h('h1', 'Saved'),
      notice('info', 'Nothing saved yet. Build a squad and press Save to keep it here. Saved squads live in this browser only — they are never uploaded.'));
  }

  const restore = (entry) => {
    const players = entry.playerIDs.map((id) => state.ratedByID.get(id)).filter(Boolean);
    if (players.length !== 15) {
      toast('Some of those players are no longer in the game, so this squad can’t be restored.');
      return;
    }
    withBusy('Loading that squad…', () => {
      state.squad = rebuild(players, entry.budgetTenths, [`Restored from "${entry.name}".`], true);
      state.chipAdvice = new ChipPlanner({
        squad: state.squad, rated: state.rated, data: state.data, usage: state.team.chipsUsed,
      }).plan();
      state.tab = 'squad';
    });
  };

  const remove = (entry) => confirmSheet({
    title: 'Delete this squad?',
    body: `"${entry.name}" is removed from this browser.`,
    confirmLabel: 'Delete',
    destructive: true,
    onConfirm: () => {
      state.savedTeams = state.savedTeams.filter((item) => item.id !== entry.id);
      save('saved', state.savedTeams);
      render();
      toast('Deleted.');
    },
  });

  const useAsMyTeam = (entry) => {
    state.team.playerIDs = entry.playerIDs.slice();
    save('team', state.team);
    withBusy('Loading that squad…', () => { buildSquad(); state.tab = 'squad'; });
  };

  return h('div.stack',
    h('h1', 'Saved'),
    h('p.small.muted', 'Stored in this browser only.'),
    state.savedTeams.map((entry) => h('div.card.stack',
      h('div.row.wrap',
        h('h3', entry.name),
        h('span.spacer'),
        pill(entry.formation)),
      h('p.small.muted', `${new Date(entry.savedAt).toLocaleString()} · projected ${entry.projected.toFixed(1)} pts · budget ${formatPrice(entry.budgetTenths)}`),
      h('div.row.wrap',
        h('button.btn.btn-sm', { type: 'button', onclick: () => restore(entry) }, 'Open'),
        h('button.btn.btn-sm', { type: 'button', onclick: () => useAsMyTeam(entry) }, 'Use as my team'),
        h('button.btn.btn-sm.btn-ghost', { type: 'button', onclick: () => remove(entry) }, 'Delete')))));
}

// ---------------------------------------------------------------------- share

function squadAsText() {
  const squad = state.squad;
  if (!squad) return '';
  const lines = [];
  lines.push(`Squad XI — ${squad.formation}, ${squad.projectedPoints.toFixed(1)} projected points`);
  lines.push(`Cost ${formatPrice(squad.totalCostTenths)} of ${formatPrice(squad.budgetTenths)}`);
  lines.push('');
  for (const position of POSITIONS) {
    const line = squad.starting.filter((player) => player.position === position);
    if (!line.length) continue;
    lines.push(`${positionShort(position)}  ${line.map((player) => {
      const mark = player.id === squad.captain.id ? ' (C)' : player.id === squad.viceCaptain.id ? ' (V)' : '';
      return `${player.element.web_name} ${formatPrice(player.priceTenths)}${mark}`;
    }).join(', ')}`);
  }
  lines.push('');
  lines.push(`Bench: ${squad.bench.map((player) => player.element.web_name).join(', ')}`);
  return lines.join('\n');
}

async function shareCurrentSquad() {
  const body = squadAsText();
  if (!body) return;
  if (navigator.share) {
    try {
      await navigator.share({ title: 'Squad XI', text: body });
      return;
    } catch { /* the user dismissed the share sheet */ }
  }
  try {
    await navigator.clipboard.writeText(body);
    toast('Squad copied to your clipboard.');
  } catch {
    openSheet('Your squad', (panel) => mount(panel,
      h('p.small.muted', 'Copy this and paste it wherever you like.'),
      h('textarea', {
        rows: '16',
        readonly: true,
        style: {
          width: '100%', background: 'var(--surface)', color: 'var(--text)',
          border: '1px solid var(--hairline)', borderRadius: '10px', padding: '12px',
          font: '13px ui-monospace, SFMono-Regular, Menlo, monospace',
        },
      }, body)));
  }
}

// ------------------------------------------------------------------- settings

function renderSettings() {
  setSub('Settings');

  const resetEverything = () => confirmSheet({
    title: 'Clear everything?',
    body: 'Your survey answers, preferences, squad and saved teams are removed from this browser. This cannot be undone.',
    confirmLabel: 'Clear everything',
    destructive: true,
    onConfirm: () => {
      for (const name of ['survey', 'prefs', 'settings', 'team', 'saved']) {
        try { localStorage.removeItem(KEY + name); } catch { /* nothing to clear */ }
      }
      location.reload();
    },
  });

  const forgetTeam = () => confirmSheet({
    title: 'Forget your squad?',
    body: 'I\u2019ll go back to suggesting a squad from scratch. Your preferences and saved squads stay.',
    confirmLabel: 'Forget it',
    destructive: true,
    onConfirm: () => {
      state.team = emptyTeam();
      save('team', state.team);
      withBusy('Building a fresh suggestion…', () => { buildSquad(); state.tab = 'squad'; });
    },
  });

  return h('div.stack',
    h('h1', 'Settings'),

    h('div.card.stack',
      h('h3', 'How much I decide'),
      Object.keys(MODE_META).map((mode) => choice({
        title: MODE_META[mode].title,
        detail: MODE_META[mode].blurb,
        selected: state.prefs.mode === mode,
        onSelect: () => {
          state.prefs.mode = mode;
          save('prefs', state.prefs);
          withBusy('Reworking…', () => { rateAll(); buildSquad(); });
        },
      }))),

    preferencesCard(),

    h('div.card.stack',
      h('h3', 'Appearance'),
      h('label.field', h('span', 'Accent'),
        h('div.chips', ['mint', 'sky', 'sunset', 'magenta', 'lime'].map((accent) => h('button.btn.btn-sm', {
          type: 'button',
          style: state.settings.accent === accent
            ? { background: 'linear-gradient(135deg, var(--accent-1), var(--accent-2))', color: '#0d0218', fontWeight: '700' }
            : null,
          onclick: () => { state.settings.accent = accent; save('settings', state.settings); render(); },
        }, accent[0].toUpperCase() + accent.slice(1))))),
      h('label.field', h('span', 'Theme'),
        h('div.chips', ['dark', 'light'].map((theme) => h('button.btn.btn-sm', {
          type: 'button',
          'aria-pressed': state.settings.theme === theme ? 'true' : 'false',
          style: state.settings.theme === theme ? { borderColor: 'var(--accent-1)' } : null,
          onclick: () => { state.settings.theme = theme; save('settings', state.settings); render(); },
        }, theme === 'dark' ? 'Dark' : 'Light')))),
      h('label.field', h('span', 'Player card detail'),
        h('div.chips', ['minimal', 'standard', 'full'].map((detail) => h('button.btn.btn-sm', {
          type: 'button',
          style: state.settings.cardDetail === detail ? { borderColor: 'var(--accent-1)' } : null,
          onclick: () => { state.settings.cardDetail = detail; save('settings', state.settings); render(); },
        }, detail[0].toUpperCase() + detail.slice(1))))),
      switchRow('Show player photos', state.settings.showPlayerPhotos, (value) => {
        state.settings.showPlayerPhotos = value;
        save('settings', state.settings);
        render();
      }),
      h('p.tiny.muted', 'Photos are loaded from the league’s own image server, which means that server sees a request from your browser. Turn them off to avoid that.')),

    h('div.card.stack',
      h('h3', 'Your team'),
      hasTeam()
        ? h('div.stack',
          h('p.small.muted', state.team.entryID
            ? `Imported from team ID ${state.team.entryID}${state.team.teamName ? ` — ${state.team.teamName}` : ''}.`
            : 'Entered by hand.'),
          h('button.btn.btn-sm.btn-wide', {
            type: 'button',
            onclick: () => { state.screen = 'setup'; state.setupStage = 'manual'; render(); },
          }, 'Edit my squad'),
          h('button.btn.btn-sm.btn-wide', { type: 'button', onclick: forgetTeam }, 'Forget my squad'))
        : h('div.stack',
          h('p.small.muted', 'No squad imported, so I’m suggesting one from scratch.'),
          h('button.btn.btn-sm.btn-wide', {
            type: 'button',
            onclick: () => { state.screen = 'setup'; state.setupStage = 'import'; render(); },
          }, 'Import my team'))),

    h('div.card.stack',
      h('h3', 'Help'),
      h('button.btn.btn-sm.btn-wide', { type: 'button', onclick: showGlossary }, 'Read the jargon buster'),
      h('button.btn.btn-sm.btn-wide', {
        type: 'button',
        onclick: () => {
          state.screen = 'survey';
          state.surveyIndex = 0;
          state.surveyAnswers = [];
          state.surveyResult = null;
          render();
        },
      }, 'Retake the survey'),
      h('button.btn.btn-sm.btn-wide', { type: 'button', onclick: refreshData }, 'Refresh live data'),
      h('p.tiny.muted', state.data.fetchedAt
        ? `Data fetched ${state.data.fetchedAt.toLocaleTimeString()}.`
        : null)),

    h('div.card.stack',
      h('h3', 'Privacy'),
      h('p.small.muted', 'Everything you enter stays in this browser. There is no account, no third-party analytics and no third-party advertising. The only network requests are for the public fantasy data and, if photos are on, player images.'),
      h('button.btn.btn-sm.btn-wide', { type: 'button', onclick: resetEverything }, 'Clear everything from this browser')),

    h('p.center.muted.small', 'Squad XI 2.1 — by Anish Gupta'),
    h('p.center.tiny.muted', 'An independent tool. Not affiliated with, endorsed by or connected to any league, club or fantasy game operator.'));
}

/** The dials — shown in setup and in settings, so they live in one function. */
function preferencesCard({ showApply = true } = {}) {
  const prefs = state.prefs;
  if (prefs.mode === 'auto') {
    return h('div.card.stack',
      h('h3', 'Preferences'),
      h('p.small.muted', `Standard ${formatPrice(1000)} budget, whole league, three per club, injured players avoided. Switch to Guided or Full Control to change any of it.`));
  }

  // The dials are gathered up and applied together: re-rating every player and
  // re-running the search on each drag of a slider would be a lot of work to
  // throw away, and the squad would jump around under the user's finger.
  const apply = () => {
    save('prefs', prefs);
    withBusy('Reworking with your settings…', () => { rateAll(); buildSquad(); });
  };

  const clubGrid = h('div.club-grid', state.data.teams
    .slice()
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((team) => h('button.club', {
      type: 'button',
      'aria-pressed': prefs.preferredTeams.includes(team.id) ? 'true' : 'false',
      title: team.name,
      onclick: (event) => {
        prefs.preferredTeams = prefs.preferredTeams.includes(team.id)
          ? prefs.preferredTeams.filter((id) => id !== team.id)
          : [...prefs.preferredTeams, team.id];
        save('prefs', prefs);
        const button = event.currentTarget;
        button.setAttribute('aria-pressed', prefs.preferredTeams.includes(team.id) ? 'true' : 'false');
      },
    },
    h('span.dot', { style: { background: clubColour(team.short_name) } }),
    team.short_name)));

  const clubModeRows = h('div.stack');
  const drawClubModes = () => mount(clubModeRows, ['bias', 'only'].map((mode) => choice({
    title: mode === 'bias' ? 'Favour them' : 'Only these clubs',
    detail: mode === 'bias'
      ? 'Players from these clubs get a boost, but I can still pick elsewhere.'
      : `Every one of the 15 must come from these clubs (pick at least ${Math.ceil(15 / Math.max(1, prefs.maxPerClub))}).`,
    selected: prefs.teamMode === mode,
    onSelect: () => { prefs.teamMode = mode; save('prefs', prefs); drawClubModes(); },
  })));
  drawClubModes();

  const expert = prefs.mode === 'expert' ? [
    sliderRow({
      label: 'Risk appetite',
      min: -1, max: 1, step: 0.1, value: prefs.riskAppetite,
      format: (value) => (value < -0.25 ? `Template (${value.toFixed(1)})` : value > 0.25 ? `Differential (+${value.toFixed(1)})` : 'Balanced'),
      onInput: (value) => { prefs.riskAppetite = value; },
    }),
    sliderRow({
      label: 'Fixture horizon',
      min: 1, max: 10, step: 1, value: prefs.fixtureHorizon,
      format: (value) => `${value} gameweek${value === 1 ? '' : 's'}`,
      onInput: (value) => { prefs.fixtureHorizon = value; },
    }),
    sliderRow({
      label: 'Weight on recent form',
      min: 0, max: 1, step: 0.05, value: prefs.formWeight,
      format: (value) => `${Math.round(value * 100)}% form, ${Math.round((1 - value) * 100)}% season`,
      onInput: (value) => { prefs.formWeight = value; },
    }),
    sliderRow({
      label: 'Maximum per club',
      min: 1, max: 3, step: 1, value: prefs.maxPerClub,
      format: (value) => `${value} player${value === 1 ? '' : 's'}`,
      onInput: (value) => { prefs.maxPerClub = value; drawClubModes(); },
    }),
    switchRow('Avoid injured and doubtful players', prefs.avoidInjuryRisk, (value) => {
      prefs.avoidInjuryRisk = value;
      save('prefs', prefs);
    }),
    h('div.row.wrap',
      h('button.btn.btn-sm', { type: 'button', onclick: () => openListEditor('mustInclude') },
        `Must-haves (${prefs.mustInclude.length})`),
      h('button.btn.btn-sm', { type: 'button', onclick: () => openListEditor('exclude') },
        `Blocklist (${prefs.exclude.length})`)),
  ] : [];

  return h('div.card.stack',
    h('h3', 'Preferences'),
    sliderRow({
      label: 'Budget',
      min: 800, max: 1200, step: 1, value: prefs.budgetTenths,
      format: formatPrice,
      onInput: (value) => { prefs.budgetTenths = value; save('prefs', prefs); },
    }),
    h('label.field', h('span', 'Clubs you want players from'), clubGrid),
    clubModeRows,
    expert,
    // In setup the screen's own Build button does the applying.
    showApply ? h('button.btn.btn-primary.btn-wide', { type: 'button', onclick: apply }, 'Apply preferences') : null);
}

/** Must-have and blocklist editor. */
function openListEditor(which) {
  const label = which === 'mustInclude' ? 'Must-haves' : 'Blocklist';
  openSheet(label, (panel) => {
    const draw = () => {
      const ids = state.prefs[which];
      const chosen = ids.map((id) => state.ratedByID.get(id)).filter(Boolean);
      mount(panel,
        h('p.small.muted', which === 'mustInclude'
          ? 'These players are locked into every squad I build.'
          : 'These players are never picked.'),
        chosen.length
          ? h('div.plist', chosen.map((player) => playerRow(player, {
            trailing: h('span.pill', 'Remove'),
            onSelect: () => {
              state.prefs[which] = ids.filter((id) => id !== player.id);
              save('prefs', state.prefs);
              draw();
            },
          })))
          : h('p.small.muted', 'Nobody yet.'),
        h('button.btn.btn-wide', {
          type: 'button',
          onclick: () => openPlayerPicker({
            title: `Add to ${label.toLowerCase()}`,
            exclude: new Set(ids),
            onPick: (player) => {
              state.prefs[which] = [...state.prefs[which], player.id];
              save('prefs', state.prefs);
              openListEditor(which);
            },
          }),
        }, 'Add a player'),
        h('button.btn.btn-primary.btn-wide', {
          type: 'button',
          onclick: () => {
            closeSheet();
            withBusy('Reworking…', () => { rateAll(); buildSquad(); });
          },
        }, 'Apply'));
    };
    draw();
  });
}

// ------------------------------------------------------------- player details

function showPlayer(player) {
  const squad = state.squad;
  const inSquad = squad?.squad.some((item) => item.id === player.id);

  openSheet(player.element.web_name, (panel) => {
    const element = player.element;
    const stat = (label, value) => h('div.tile', h('div.k', label), h('div.v', value));

    const swap = () => {
      closeSheet();
      const others = squad.squad.filter((item) => item.id !== player.id);
      const headroom = squad.budgetTenths - others.reduce((sum, item) => sum + item.priceTenths, 0);
      openPlayerPicker({
        title: `Replace ${player.element.web_name}`,
        position: player.position,
        exclude: new Set(squad.squad.map((item) => item.id)),
        clubLimitSquad: others,
        maxPriceTenths: headroom,
        onPick: (incoming) => {
          closeSheet();
          withBusy('Reworking the squad…', () => {
            const next = squad.squad.map((item) => (item.id === player.id ? incoming : item));
            if (hasTeam()) {
              state.team.playerIDs = state.team.playerIDs.map((id) => (id === player.id ? incoming.id : id));
              state.team.bankTenths -= incoming.priceTenths - player.priceTenths;
              save('team', state.team);
              buildSquad();
            } else {
              state.squad = rebuild(next, squad.budgetTenths, ['Changed by hand.'], true);
              state.chipAdvice = new ChipPlanner({
                squad: state.squad, rated: state.rated, data: state.data, usage: state.team.chipsUsed,
              }).plan();
            }
          });
        },
      });
    };

    mount(panel,
      h('div.row',
        h('span.pill', { style: { background: clubColour(player.team.short_name), color: '#fff', borderColor: 'transparent' } },
          player.team.short_name),
        h('span.pill', positionShort(player.position)),
        h('span.pill', formatPrice(player.priceTenths)),
        player.availability.label ? pill(player.availability.label, player.availability.kind === 'out' ? 'bad' : 'warn') : null),
      h('p.small.muted', `${element.first_name} ${element.second_name} — ${player.team.name}`),

      h('div.tiles',
        stat('Proj. pts/GW', player.projected.toFixed(2)),
        stat('Form', num(element.form).toFixed(1)),
        stat('Points', String(element.total_points)),
        stat('Per game', num(element.points_per_game).toFixed(1)),
        stat('Minutes', String(element.minutes)),
        stat('Owned', `${num(element.selected_by_percent).toFixed(1)}%`)),

      h('div.tiles',
        stat('xG / 90', num(element.expected_goals_per_90).toFixed(2)),
        stat('xA / 90', num(element.expected_assists_per_90).toFixed(2)),
        stat('Avg FDR', player.fixtureScore.toFixed(1)),
        stat('Goals', String(element.goals_scored)),
        stat('Assists', String(element.assists)),
        stat('Clean sheets', String(element.clean_sheets))),

      fixtureCardFor(player),

      player.reasons.length
        ? h('div.card.stack', h('h3', 'Why'), h('div.chips', player.reasons.map((reason) => pill(reason))))
        : null,

      element.news ? notice('warn', element.news) : null,

      h('p.tiny.muted', 'The projection blends recent form, season-long returns and underlying per-90 numbers, then adjusts for fixtures, minutes and availability. Early in a season it is pulled toward a prior, because one match is weak evidence.'),

      inSquad ? h('button.btn.btn-wide', { type: 'button', onclick: swap }, 'Replace this player') : null,
      h('div.row.wrap',
        h('button.btn.btn-sm', {
          type: 'button',
          onclick: () => {
            if (!state.prefs.mustInclude.includes(player.id)) state.prefs.mustInclude.push(player.id);
            state.prefs.exclude = state.prefs.exclude.filter((id) => id !== player.id);
            save('prefs', state.prefs);
            closeSheet();
            withBusy('Locking them in…', () => { rateAll(); buildSquad(); });
          },
        }, 'Always pick'),
        h('button.btn.btn-sm', {
          type: 'button',
          onclick: () => {
            if (!state.prefs.exclude.includes(player.id)) state.prefs.exclude.push(player.id);
            state.prefs.mustInclude = state.prefs.mustInclude.filter((id) => id !== player.id);
            save('prefs', state.prefs);
            closeSheet();
            withBusy('Blocking them…', () => { rateAll(); buildSquad(); });
          },
        }, 'Never pick')),
      state.prefs.mode !== 'expert'
        ? h('p.tiny.muted', 'Must-haves and the blocklist only take effect in Full Control mode.')
        : null);
  });
}

/**
 * The club's next five gameweeks. The projection already weighs fixture
 * difficulty, but seeing the actual opponents is what makes it trustworthy.
 */
function fixtureCardFor(player) {
  const planner = state.fixturePlanner;
  if (!planner) return null;
  const weeks = planner.next(5, player.element.team);
  if (!weeks.length) return null;

  return h('div.card.stack',
    h('div.row.wrap',
      h('h3', 'Next 5 fixtures'),
      h('span.spacer'),
      h('span.tiny.muted', player.team.short_name)),
    h('div.ticker',
      h('div.ticker-row.head', h('span', ''),
        h('span.fx-run', weeks.map((week) => h('span.gw', `GW${week.gameweek}`)))),
      h('div.ticker-row', h('span', ''), fixtureRun(weeks))),
    h('p.small.muted', planner.summary(5, player.element.team)),
    h('p.tiny.muted', 'Home in capitals, away in lower case. A dash is a blank gameweek.'));
}

/** Searchable, sorted, legality-filtered player list. */
function openPlayerPicker({ title, position, exclude = new Set(), clubLimitSquad = null, maxPriceTenths = null, onPick }) {
  let query = '';
  let sort = 'projected';
  let positionFilter = position ?? null;

  openSheet(title, (panel) => {
    const list = h('div.plist');
    const count = h('p.small.muted');

    const clubCounts = new Map();
    if (clubLimitSquad) {
      for (const player of clubLimitSquad) {
        clubCounts.set(player.element.team, (clubCounts.get(player.element.team) || 0) + 1);
      }
    }

    const draw = () => {
      const needle = query.trim().toLowerCase();
      let matches = state.rated.filter((player) => {
        if (exclude.has(player.id)) return false;
        if (positionFilter && player.position !== positionFilter) return false;
        if (maxPriceTenths !== null && player.priceTenths > maxPriceTenths) return false;
        if (clubLimitSquad && (clubCounts.get(player.element.team) || 0) >= state.prefs.maxPerClub) return false;
        if (!needle) return true;
        return `${player.element.web_name} ${player.element.first_name} ${player.element.second_name} ${player.team.name} ${player.team.short_name}`
          .toLowerCase().includes(needle);
      });

      const comparators = {
        projected: (a, b) => b.projected - a.projected,
        value: (a, b) => b.valueRatio - a.valueRatio,
        price: (a, b) => b.priceTenths - a.priceTenths,
        cheap: (a, b) => a.priceTenths - b.priceTenths,
        points: (a, b) => b.element.total_points - a.element.total_points,
        owned: (a, b) => num(b.element.selected_by_percent) - num(a.element.selected_by_percent),
      };
      matches.sort(comparators[sort]);

      count.textContent = `${matches.length} available${maxPriceTenths !== null ? `, up to ${formatPrice(maxPriceTenths)}` : ''}`;
      mount(list, matches.slice(0, 120).map((player) => playerRow(player, {
        onSelect: () => onPick(player),
        trailing: h('span.nums',
          h('span.pr', formatPrice(player.priceTenths)),
          h('span.pj', `${player.projected.toFixed(1)} pts · ${isOut(player) ? 'out' : `${player.element.total_points} tot`}`)),
      })));
      if (matches.length > 120) list.append(h('p.tiny.muted.center', `Showing the top 120. Search to narrow it down.`));
    };

    const search = h('input', {
      type: 'search', placeholder: 'Search by player or club',
      oninput: (event) => { query = event.target.value; draw(); },
    });

    const sortSelect = h('select', { onchange: (event) => { sort = event.target.value; draw(); } },
      [['projected', 'Projected points'], ['value', 'Points per £m'], ['points', 'Season points'],
        ['price', 'Most expensive'], ['cheap', 'Cheapest'], ['owned', 'Most owned']]
        .map(([value, label]) => h('option', { value }, label)));

    const positionFilters = position ? null : h('div.chips',
      [null, ...POSITIONS].map((item) => h('button.btn.btn-sm', {
        type: 'button',
        style: positionFilter === item ? { borderColor: 'var(--accent-1)' } : null,
        onclick: () => { positionFilter = item; draw(); },
      }, item === null ? 'All' : positionShort(item))));

    mount(panel, search, positionFilters, h('label.field', h('span', 'Sort by'), sortSelect), count, list);
    draw();
    search.focus();
  });
}

// -------------------------------------------------------------------- glossary

function showGlossary() {
  openSheet('Jargon buster', (panel) => {
    const list = h('div.stack');
    const draw = (query) => mount(list, searchGlossary(query).map((item) => h('div.card',
      h('div.row.wrap', h('h3', item.term), item.short ? h('span.pill', item.short) : null),
      h('p.small', { style: { marginTop: '8px' } }, item.definition),
      item.example ? h('p.small.muted', { style: { marginTop: '6px' } }, item.example) : null)));

    const search = h('input', {
      type: 'search', placeholder: 'Search the terms',
      oninput: (event) => draw(event.target.value),
    });
    mount(panel, search, list);
    draw('');
  });
}

// ------------------------------------------------------------------------ boot

async function refreshData() {
  state.busy = true;
  state.loadingNote = 'Fetching live prices, form and fixtures…';
  render();
  try {
    state.data = await loadLeagueData();
    rateAll();
    buildSquad();
    state.error = null;
  } catch (error) {
    state.error = error.message;
  }
  state.busy = false;
  render();
}

async function boot() {
  applyTheme();
  document.getElementById('glossary-button').addEventListener('click', showGlossary);

  state.screen = 'loading';
  render();

  try {
    state.data = await loadLeagueData();
  } catch (error) {
    state.screen = 'main';
    state.tab = 'squad';
    state.error = error.message;
    render();
    return;
  }

  rateAll();

  if (!state.survey) {
    state.screen = 'survey';
    render();
    return;
  }

  if (state.survey.teamStatus !== 'none' && !hasTeam()) {
    state.screen = 'setup';
    state.setupStage = state.survey.teamStatus === 'importByID' ? 'import' : 'manual';
    render();
    return;
  }

  withBusy('Working out the best legal squad…', () => {
    buildSquad();
    state.screen = 'main';
  });
}

boot();
