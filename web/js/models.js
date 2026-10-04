// Domain types and the raw-API shim, ported from Sources/Models.

export const GOALKEEPER = 1;
export const DEFENDER = 2;
export const MIDFIELDER = 3;
export const FORWARD = 4;

export const POSITIONS = [GOALKEEPER, DEFENDER, MIDFIELDER, FORWARD];

const POSITION_META = {
  [GOALKEEPER]: { short: 'GKP', name: 'Goalkeeper', squadCount: 2, starting: [1, 1] },
  [DEFENDER]: { short: 'DEF', name: 'Defender', squadCount: 5, starting: [3, 5] },
  [MIDFIELDER]: { short: 'MID', name: 'Midfielder', squadCount: 5, starting: [2, 5] },
  [FORWARD]: { short: 'FWD', name: 'Forward', squadCount: 3, starting: [1, 3] },
};

export const positionShort = (p) => POSITION_META[p].short;
export const positionName = (p) => POSITION_META[p].name;
export const squadCount = (p) => POSITION_META[p].squadCount;

/** Legal counts for the starting XI, as a list. */
export function startingRange(position) {
  const [low, high] = POSITION_META[position].starting;
  const range = [];
  for (let value = low; value <= high; value += 1) range.push(value);
  return range;
}

/** A stat the API may send as a string, a number, or null. */
export function num(value) {
  if (value === null || value === undefined) return 0;
  const parsed = typeof value === 'number' ? value : Number.parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function formatPrice(tenths) {
  return `£${(tenths / 10).toFixed(1)}m`;
}

/**
 * Availability from the player's status flag.
 * a=available d=doubtful i=injured s=suspended u/n=unavailable
 */
export function availabilityOf(element) {
  if (element.status === 'a') return { kind: 'available', multiplier: 1.0, label: null };
  const chance = element.chance_of_playing_next_round;
  if (element.status === 'd') {
    const value = chance === null || chance === undefined ? 50 : chance;
    return { kind: 'doubtful', multiplier: Math.max(0.15, value / 100), label: `${value}% fit` };
  }
  if (typeof chance === 'number' && chance > 0) {
    return { kind: 'doubtful', multiplier: Math.max(0.15, chance / 100), label: `${chance}% fit` };
  }
  return { kind: 'out', multiplier: 0.03, label: 'Unavailable' };
}

export const isOut = (player) => player.availability.kind === 'out';

export function photoURL(element) {
  return `https://resources.premierleague.com/premierleague/photos/players/110x140/p${element.code}.png`;
}

// MARK: - Chips

export const CHIPS = ['bboost', '3xc', 'freehit', 'wildcard'];

export const CHIP_META = {
  bboost: {
    name: 'Bench Boost',
    summary: 'Your four bench players score as well as your XI, for one gameweek.',
    ideal: 'Best when all 15 have fixtures — ideally a double gameweek.',
    playMultiple: 1.40,
  },
  '3xc': {
    name: 'Triple Captain',
    summary: 'Your captain scores triple instead of double, for one gameweek.',
    ideal: 'Best on a premium with two fixtures, or one very kind one.',
    playMultiple: 1.25,
  },
  freehit: {
    name: 'Free Hit',
    summary: 'Unlimited transfers for one gameweek. Your squad reverts afterwards.',
    ideal: "Best in a blank gameweek, when much of your squad isn't playing.",
    playMultiple: 1.35,
  },
  wildcard: {
    name: 'Wildcard',
    summary: 'Unlimited transfers that you keep. Rebuild the squad without taking hits.',
    ideal: 'Best when your squad has drifted far from the best available one.',
    playMultiple: 1.08,
  },
};

export function emptyChipUsage() {
  return { usedFirstHalf: [], usedSecondHalf: [] };
}

export function hasUsedChip(usage, chip, secondHalf) {
  const list = secondHalf ? usage.usedSecondHalf : usage.usedFirstHalf;
  return list.includes(chip);
}

export function toggleChip(usage, chip, secondHalf) {
  const key = secondHalf ? 'usedSecondHalf' : 'usedFirstHalf';
  const list = usage[key];
  usage[key] = list.includes(chip) ? list.filter((item) => item !== chip) : [...list, chip];
  return usage;
}

// MARK: - Preferences

export function defaultPreferences() {
  return {
    mode: 'auto',
    budgetTenths: 1000,
    preferredTeams: [],
    teamMode: 'bias',
    maxPerClub: 3,
    riskAppetite: 0,
    fixtureHorizon: 5,
    formWeight: 0.35,
    avoidInjuryRisk: true,
    mustInclude: [],
    exclude: [],
  };
}

/** Expert dials collapse to sane defaults for the simpler modes. */
export function effectivePreferences(prefs) {
  if (prefs.mode === 'auto') return { ...defaultPreferences(), mode: 'auto' };
  if (prefs.mode === 'guided') {
    return {
      ...defaultPreferences(),
      mode: 'guided',
      budgetTenths: prefs.budgetTenths,
      preferredTeams: [...prefs.preferredTeams],
      teamMode: prefs.teamMode,
    };
  }
  return { ...prefs };
}

export const MODE_META = {
  auto: {
    title: 'Do It For Me',
    blurb: 'You tell me nothing. I pick a full legal squad, starting XI and captain using live prices, form and fixtures.',
  },
  guided: {
    title: 'Guided',
    blurb: 'You set your budget and the clubs you want players from. I handle the rest.',
  },
  expert: {
    title: 'Full Control',
    blurb: 'Every dial: risk appetite, fixture horizon, form weighting, club caps, must-haves and blocklist.',
  },
};

/** What the user still has to fix before a hand-entered squad is usable. */
export function validateSquad(players, maxPerClub = 3) {
  const missing = [];
  for (const position of POSITIONS) {
    const have = players.filter((player) => player.position === position).length;
    if (have < squadCount(position)) {
      missing.push({ position, short: positionShort(position), count: squadCount(position) - have });
    }
  }
  const counts = new Map();
  for (const player of players) counts.set(player.element.team, (counts.get(player.element.team) || 0) + 1);
  const overClubLimit = [];
  for (const [team, count] of counts) {
    if (count > maxPerClub) {
      const name = players.find((player) => player.element.team === team)?.team.name;
      if (name) overClubLimit.push(name);
    }
  }

  const parts = [];
  if (missing.length) parts.push(`Still need ${missing.map((item) => `${item.count} more ${item.short}`).join(', ')}`);
  for (const club of overClubLimit) parts.push(`More than ${maxPerClub} players from ${club}`);

  return {
    missing,
    overClubLimit,
    isValid: missing.length === 0 && overClubLimit.length === 0,
    message: parts.length ? parts.join(' · ') : null,
  };
}
