// Works out when to play each chip.
// Ported from Sources/Engine/ChipPlanner.swift.
//
// Every chip is valued in the same currency — points it would add over playing
// the gameweek normally — so the four can be compared against each other and
// against the rules of thumb for holding on.

import {
  GOALKEEPER, DEFENDER, MIDFIELDER, FORWARD, POSITIONS,
  CHIPS, CHIP_META, squadCount, startingRange, hasUsedChip, defaultPreferences,
} from './models.js';
import { SquadOptimizer } from './optimizer.js';

export class ChipPlanner {
  constructor({ squad, rated, data, usage, horizon = 8 }) {
    this.squad = squad;
    this.rated = rated;
    this.data = data;
    this.usage = usage;
    this.horizon = horizon;

    const matches = new Map();        // gameweek -> Map(team -> fixtures)
    const difficulty = new Map();     // gameweek -> Map(team -> [fdr])
    for (const fixture of data.fixtures) {
      if (fixture.finished) continue;
      const gameweek = fixture.event;
      if (gameweek === null || gameweek === undefined) continue;
      if (!matches.has(gameweek)) matches.set(gameweek, new Map());
      if (!difficulty.has(gameweek)) difficulty.set(gameweek, new Map());
      const week = matches.get(gameweek);
      const fdr = difficulty.get(gameweek);
      for (const [team, value] of [[fixture.team_h, fixture.team_h_difficulty], [fixture.team_a, fixture.team_a_difficulty]]) {
        week.set(team, (week.get(team) || 0) + 1);
        if (!fdr.has(team)) fdr.set(team, []);
        fdr.get(team).push(value);
      }
    }
    this.matchesByTeam = matches;
    this.difficultyByTeam = new Map(
      [...difficulty].map(([gameweek, perTeam]) => [
        gameweek,
        new Map([...perTeam].map(([team, list]) => [
          team,
          list.length ? list.reduce((sum, value) => sum + value, 0) / list.length : 3.0,
        ])),
      ]),
    );
  }

  // MARK: - Gameweek arithmetic

  /**
   * Gameweeks you can still act on. A gameweek that has kicked off is no use
   * for chip advice even though the game hasn't marked it finished — its
   * deadline has gone.
   */
  get upcomingGameweeks() {
    const now = Date.now();
    return this.data.events
      .filter((event) => !event.finished)
      .filter((event) => {
        const deadline = event.deadline_time ? Date.parse(event.deadline_time) : -Infinity;
        return deadline > now;
      })
      .map((event) => event.id)
      .sort((a, b) => a - b)
      .slice(0, this.horizon);
  }

  matches(team, gameweek) {
    return this.matchesByTeam.get(gameweek)?.get(team) ?? 0;
  }

  /**
   * Expected points for a player in one specific gameweek, which is their
   * per-match rate scaled by how many fixtures they have and how hard those
   * fixtures are. A blank returns zero; a double roughly doubles.
   */
  expected(player, gameweek) {
    const count = this.matches(player.element.team, gameweek);
    if (count === 0) return 0;
    const fdr = this.difficultyByTeam.get(gameweek)?.get(player.element.team) ?? 3.0;
    const swing = Math.min(1.35, Math.max(0.7, 1.0 + (3.0 - fdr) * 0.10));
    return player.perMatch * count * swing;
  }

  /** Teams with two or more fixtures in a gameweek. */
  doubles(gameweek) {
    const week = this.matchesByTeam.get(gameweek) || new Map();
    return [...week]
      .filter(([, count]) => count > 1)
      .map(([team]) => this.data.teamsByID.get(team)?.short_name)
      .filter(Boolean)
      .sort();
  }

  /** Teams with no fixture in a gameweek. */
  blanks(gameweek) {
    return this.data.teams
      .filter((team) => this.matches(team.id, gameweek) === 0)
      .map((team) => team.short_name)
      .sort();
  }

  // MARK: - Plan

  plan() {
    return CHIPS.map((chip) => this.advice(chip));
  }

  window(chip) {
    // The half a chip belongs to is decided by the gameweeks it covers, so pick
    // whichever of the season's two windows still has room ahead.
    const gameweeks = this.upcomingGameweeks;
    if (!gameweeks.length) return null;
    const first = gameweeks[0];
    return this.data.chipWindows
      .filter((window) => window.name === chip && window.stop_event >= first)
      .sort((a, b) => a.start_event - b.start_event)[0] || null;
  }

  advice(chip) {
    const window = this.window(chip);
    if (!window) {
      return {
        chip, verdict: 'expired', gameweek: null, gain: 0, multiple: 1,
        headline: 'No window left',
        detail: "This chip's window has closed for the season.",
        ranked: [],
      };
    }
    const secondHalf = window.start_event >= 20;
    if (hasUsedChip(this.usage, chip, secondHalf)) {
      return {
        chip, verdict: 'used', gameweek: null, gain: 0, multiple: 1,
        headline: 'Already played',
        detail: secondHalf
          ? "You've used this one. It doesn't come back."
          : "You've used the first-half one. A second becomes available in gameweek 20.",
        ranked: [],
      };
    }

    const covers = (gameweek) => gameweek >= window.start_event && gameweek <= window.stop_event;
    const candidates = this.upcomingGameweeks.filter(covers);
    if (!candidates.length) {
      return {
        chip, verdict: 'hold', gameweek: null, gain: 0, multiple: 1,
        headline: 'Not yet',
        detail: `This chip opens in gameweek ${window.start_event}.`,
        ranked: [],
      };
    }

    const values = candidates.map((gameweek) => ({ gameweek, value: this.value(chip, gameweek) }));
    const scored = values.slice().sort((a, b) => b.value - a.value);
    const best = scored[0];

    if (!best || best.value <= 0) {
      return {
        chip, verdict: 'hold', gameweek: null, gain: 0, multiple: 1,
        headline: 'Hold', detail: 'Nothing to weigh yet.', ranked: [],
      };
    }

    // An ordinary week for this chip, so a candidate can be judged against it
    // rather than against a points total whose scale drifts.
    const ordered = values.map((item) => item.value).sort((a, b) => a - b);
    // The wildcard is judged against the squad you own rather than against
    // other gameweeks, so its value is already a ratio.
    const typical = chip === 'wildcard' ? 1.0 : Math.max(0.01, ordered[Math.floor(ordered.length / 2)]);
    const multiple = best.value / typical;

    // A multiple alone isn't enough: when a typical week is worth almost
    // nothing, dividing by it turns a one-point gain into "95x better". The
    // chip must also move the needle against what the squad scores that week —
    // at least a tenth of it.
    const weekScale = Math.max(1, this.bestEleven(this.squad.squad, best.gameweek));
    const significant = chip === 'wildcard' || (best.value - typical) >= 0.10 * weekScale;
    const worthIt = multiple >= CHIP_META[chip].playMultiple && significant;

    return {
      chip,
      verdict: worthIt ? 'play' : 'hold',
      gameweek: worthIt ? best.gameweek : null,
      gain: chip === 'wildcard' ? (best.value - 1) * 100 : Math.max(0, best.value - typical),
      multiple,
      headline: worthIt ? `Play in gameweek ${best.gameweek}` : 'Hold',
      detail: this.reasoning(chip, best.gameweek, best.value, typical, worthIt),
      ranked: scored.slice(0, 3).map((item) => ({ gameweek: item.gameweek, gain: item.value })),
    };
  }

  // MARK: - What each chip is worth

  value(chip, gameweek) {
    switch (chip) {
      case 'bboost': return this.benchBoostValue(gameweek);
      case '3xc': return this.tripleCaptainValue(gameweek);
      case 'freehit': return this.freeHitValue(gameweek);
      case 'wildcard': return this.wildcardValue();
      default: return 0;
    }
  }

  /** Bench Boost is simply what the four bench players would score. */
  benchBoostValue(gameweek) {
    return this.squad.bench.reduce((sum, player) => sum + this.expected(player, gameweek), 0);
  }

  /** Triple Captain adds one more helping of your best captain. */
  tripleCaptainValue(gameweek) {
    const values = this.squad.starting
      .filter((player) => player.position !== GOALKEEPER)
      .map((player) => this.expected(player, gameweek));
    return values.length ? Math.max(...values) : 0;
  }

  /**
   * Free Hit is worth the gap between the XI you could field for one week and
   * the XI you actually have. The replacement XI is built greedily from players
   * who have a fixture, respecting the three-per-club limit and the squad's own
   * budget, so it stays a team you could really assemble.
   */
  freeHitValue(gameweek) {
    const yours = this.bestEleven(this.squad.squad, gameweek);
    const budget = this.squad.budgetTenths;
    const clubs = new Map();
    let spend = 0;
    const picked = [];

    const pool = this.rated
      .map((player) => ({ player, value: this.expected(player, gameweek) }))
      .filter((entry) => entry.value > 0)
      .sort((a, b) => b.value - a.value)
      .map((entry) => entry.player);

    for (const position of POSITIONS) {
      const need = squadCount(position);
      let taken = 0;
      for (const player of pool) {
        if (taken >= need) break;
        if (player.position !== position) continue;
        if ((clubs.get(player.element.team) || 0) >= 3) continue;
        // Leave enough for the cheapest bodies still to come.
        if (spend + player.priceTenths > budget - (15 - picked.length - 1) * 40) continue;
        picked.push(player);
        clubs.set(player.element.team, (clubs.get(player.element.team) || 0) + 1);
        spend += player.priceTenths;
        taken += 1;
      }
    }
    if (picked.length !== 15) return 0;
    return Math.max(0, this.bestEleven(picked, gameweek) - yours);
  }

  /**
   * Wildcard is judged over the whole horizon rather than one gameweek: how
   * much better the optimizer's squad is than the one you own, per gameweek.
   */
  wildcardValue() {
    if (this.cachedWildcard !== undefined) return this.cachedWildcard;
    const prefs = defaultPreferences();
    prefs.budgetTenths = this.squad.budgetTenths;
    let ideal;
    try {
      ideal = new SquadOptimizer(this.rated, prefs).optimize();
    } catch {
      this.cachedWildcard = 0;
      return 0;
    }
    // Expressed as a ratio against the squad you already own, so the threshold
    // ("8% better") holds whatever the projection scale is.
    if (this.squad.startingPoints <= 0) {
      this.cachedWildcard = 0;
      return 0;
    }
    this.cachedWildcard = ideal.startingPoints / this.squad.startingPoints;
    return this.cachedWildcard;
  }

  /** Best legal XI out of a 15 for one gameweek, using that week's fixtures. */
  bestEleven(players, gameweek) {
    const byPosition = new Map(POSITIONS.map((position) => [position, []]));
    for (const player of players) {
      byPosition.get(player.position)?.push(this.expected(player, gameweek));
    }
    for (const list of byPosition.values()) list.sort((a, b) => b - a);

    const take = (position, count) => (byPosition.get(position) || [])
      .slice(0, count)
      .reduce((sum, value) => sum + value, 0);

    const keepers = byPosition.get(GOALKEEPER);
    if (!keepers.length) return 0;
    const keeper = keepers[0];

    let best = 0;
    for (const defenders of startingRange(DEFENDER)) {
      for (const midfielders of startingRange(MIDFIELDER)) {
        const forwards = 10 - defenders - midfielders;
        if (!startingRange(FORWARD).includes(forwards)) continue;
        if (byPosition.get(DEFENDER).length < defenders) continue;
        if (byPosition.get(MIDFIELDER).length < midfielders) continue;
        if (byPosition.get(FORWARD).length < forwards) continue;
        const total = keeper + take(DEFENDER, defenders) + take(MIDFIELDER, midfielders) + take(FORWARD, forwards);
        best = Math.max(best, total);
      }
    }
    return best;
  }

  // MARK: - Explanations

  /** "1 pt" rather than "1 pts". */
  points(value) {
    const rounded = Math.round(value);
    return `${rounded} pt${rounded === 1 ? '' : 's'}`;
  }

  reasoning(chip, gameweek, value, typical, worthIt) {
    const extra = value - typical;
    const doubled = this.doubles(gameweek);
    const blanked = this.blanks(gameweek);
    const notes = [];

    switch (chip) {
      case 'bboost':
        notes.push(`Gameweek ${gameweek} is your bench's best week — about ${this.points(extra)} more than a typical one.`);
        break;
      case '3xc':
        notes.push(`Gameweek ${gameweek} is your captain's best week — about ${this.points(extra)} more than a typical one.`);
        break;
      case 'freehit':
        notes.push(`Gameweek ${gameweek} is where a one-week rebuild gains most — about ${this.points(extra)}.`);
        break;
      case 'wildcard':
        notes.push(`A rebuilt squad projects about ${((value - 1) * 100).toFixed(0)}% more per gameweek than yours.`);
        break;
      default: break;
    }

    if (doubled.length) notes.push(`Double gameweek for ${doubled.slice(0, 4).join(', ')}.`);
    if (blanked.length && chip === 'freehit') notes.push(`${blanked.length} clubs blank.`);

    if (!worthIt) {
      if (chip === 'wildcard') {
        notes.push("Your squad is close enough to the best available one that a rebuild wouldn't pay for itself yet.");
      } else {
        notes.push(doubled.length === 0 && blanked.length === 0
          ? "No doubles or blanks are scheduled yet — they're usually announced later, and that's normally when this chip pays."
          : 'Not enough better than an ordinary week to justify burning the chip.');
      }
    }
    return notes.join(' ');
  }
}
