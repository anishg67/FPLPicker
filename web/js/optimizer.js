// Builds the best legal squad it can find under the user's constraints.
// Ported from Sources/Engine/SquadOptimizer.swift.
//
// The search starts from the cheapest legal squad (always feasible), then does
// best-improvement hill climbing on single-player swaps, with random
// perturbation restarts to escape local optima. Every candidate is scored by
// the value of its best starting XI, so bench spending is naturally minimised.

import {
  GOALKEEPER, DEFENDER, MIDFIELDER, FORWARD, POSITIONS,
  squadCount, positionShort, positionName, startingRange, formatPrice, isOut,
} from './models.js';

/** Bench points are worth much less than XI points, but not nothing. */
const BENCH_WEIGHT = 0.12;
const RESTARTS = 8;
const MAX_PASSES = 40;

/** Fixed seed keeps the perturbation restarts reproducible run to run. */
const OPTIMIZER_SEED = 20260821;

export class OptimizerError extends Error {
  constructor(message) {
    super(message);
    this.name = 'OptimizerError';
  }
}

/** Deterministic RNG so the same inputs always produce the same suggestion. */
class SeededRandom {
  constructor(seed) {
    this.state = seed >>> 0;
  }

  next() {
    // mulberry32 — same role as the Swift splitmix64, within JS integer range.
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let z = this.state;
    z = Math.imul(z ^ (z >>> 15), z | 1);
    z ^= z + Math.imul(z ^ (z >>> 7), z | 61);
    return ((z ^ (z >>> 14)) >>> 0);
  }

  upTo(bound) {
    if (bound <= 0) return 0;
    return this.next() % bound;
  }
}

/**
 * The player who should wear the armband. Goalkeepers are excluded: their
 * ceiling is far below an attacker's even when the projections sit close
 * together, which they do early in a season.
 */
export function bestCaptain(starting, excludedID = null) {
  let best = null;
  for (const player of starting) {
    if (player.position === GOALKEEPER) continue;
    if (player.id === excludedID) continue;
    if (!best || player.projected > best.projected) best = player;
  }
  if (best) return best;
  const rest = starting.filter((player) => player.id !== excludedID);
  return rest.reduce((top, player) => (!top || player.projected > top.projected ? player : top), null);
}

/** Picks the best legal XI out of the 15 and scores the squad. */
export function evaluate(squad) {
  const byPosition = new Map(POSITIONS.map((position) => [position, []]));
  for (const player of squad) byPosition.get(player.position).push(player);
  for (const list of byPosition.values()) list.sort((a, b) => b.projected - a.projected);

  const keepers = byPosition.get(GOALKEEPER);
  const defenders = byPosition.get(DEFENDER);
  const midfielders = byPosition.get(MIDFIELDER);
  const forwards = byPosition.get(FORWARD);

  const prefixSums = (players) => {
    const sums = [0];
    for (const player of players) sums.push(sums[sums.length - 1] + player.projected);
    return sums;
  };
  const defSums = prefixSums(defenders);
  const midSums = prefixSums(midfielders);
  const fwdSums = prefixSums(forwards);

  let bestTotal = -Infinity;
  let bestShape = { def: 3, mid: 4, fwd: 3 };

  for (const def of startingRange(DEFENDER)) {
    if (def >= defSums.length) continue;
    for (const mid of startingRange(MIDFIELDER)) {
      if (mid >= midSums.length) continue;
      const fwd = 10 - def - mid;
      if (!startingRange(FORWARD).includes(fwd) || fwd >= fwdSums.length) continue;
      const total = defSums[def] + midSums[mid] + fwdSums[fwd];
      if (total > bestTotal) {
        bestTotal = total;
        bestShape = { def, mid, fwd };
      }
    }
  }

  const starting = [];
  if (keepers.length) starting.push(keepers[0]);
  starting.push(...defenders.slice(0, bestShape.def));
  starting.push(...midfielders.slice(0, bestShape.mid));
  starting.push(...forwards.slice(0, bestShape.fwd));

  const startingIDs = new Set(starting.map((player) => player.id));
  const bench = squad.filter((player) => !startingIDs.has(player.id));

  const startingSum = starting.reduce((sum, player) => sum + player.projected, 0);
  const benchSum = bench.reduce((sum, player) => sum + player.projected, 0);
  const captain = bestCaptain(starting) || squad[0];

  return {
    score: startingSum + captain.projected + BENCH_WEIGHT * benchSum,
    startingSum,
    starting,
    bench,
    captain,
    formation: `${bestShape.def}-${bestShape.mid}-${bestShape.fwd}`,
  };
}

export class SquadOptimizer {
  constructor(rated, prefs) {
    this.rated = rated;
    this.prefs = prefs;
  }

  optimize() {
    const prefs = this.prefs;
    const notes = [];
    const budget = prefs.budgetTenths;

    if (prefs.teamMode === 'only') {
      const clubs = prefs.preferredTeams.length;
      const needed = Math.ceil(15 / Math.max(1, prefs.maxPerClub));
      if (clubs < needed) {
        throw new OptimizerError(
          `With a limit of ${prefs.maxPerClub} players per club you need at least ${needed} clubs selected to fill a 15-man squad.`,
        );
      }
    }

    const locked = this.lockedPlayers();
    const pool = this.buildPool(locked);

    let best = this.cheapestFeasible(pool, locked, budget);
    let bestScore = evaluate(best).score;
    const rng = new SeededRandom(OPTIMIZER_SEED);

    for (let restart = 0; restart < RESTARTS; restart += 1) {
      let current = restart === 0 ? best : this.perturb(best, pool, locked, budget, rng);
      let currentScore = evaluate(current).score;

      for (let pass = 0; pass < MAX_PASSES; pass += 1) {
        const move = this.bestSwap(current, currentScore, pool, locked, budget);
        if (!move) break;
        current = current.slice();
        current[move.index] = move.incoming;
        currentScore = move.score;
      }

      if (currentScore > bestScore) {
        best = current;
        bestScore = currentScore;
      }
    }

    const evaluation = evaluate(best);
    const cost = best.reduce((sum, player) => sum + player.priceTenths, 0);

    if (locked.length) {
      notes.push(`Locked in ${locked.length} must-have ${locked.length === 1 ? 'player' : 'players'}.`);
    }
    if (prefs.teamMode === 'only' && prefs.preferredTeams.length) {
      notes.push(`Restricted to your ${prefs.preferredTeams.length} selected clubs.`);
    }

    const starting = evaluation.starting.slice().sort((a, b) => (
      a.position === b.position ? b.projected - a.projected : a.position - b.position
    ));
    const captain = evaluation.captain;
    const vice = bestCaptain(evaluation.starting, captain.id) || captain;

    // Bench order: goalkeeper always sits at slot 0, then most likely to
    // deliver if someone doesn't play.
    const benchOutfield = evaluation.bench
      .filter((player) => player.position !== GOALKEEPER)
      .sort((a, b) => b.projected - a.projected);
    const benchGK = evaluation.bench.filter((player) => player.position === GOALKEEPER);

    return {
      squad: best,
      starting,
      bench: [...benchGK, ...benchOutfield],
      captain,
      viceCaptain: vice,
      formation: evaluation.formation,
      totalCostTenths: cost,
      budgetTenths: budget,
      projectedPoints: evaluation.startingSum + captain.projected,
      startingPoints: evaluation.startingSum,
      remainingTenths: budget - cost,
      notes,
      edited: false,
    };
  }

  // MARK: - Candidate pool

  lockedPlayers() {
    const prefs = this.prefs;
    const locked = this.rated.filter((player) => prefs.mustInclude.includes(player.id));

    const byPosition = new Map();
    const byClub = new Map();
    for (const player of locked) {
      byPosition.set(player.position, (byPosition.get(player.position) || 0) + 1);
      byClub.set(player.element.team, (byClub.get(player.element.team) || 0) + 1);
    }
    for (const [position, count] of byPosition) {
      if (count > squadCount(position)) {
        throw new OptimizerError(
          `Your must-have list doesn't fit a legal squad: ${count} ${positionShort(position)} selected, only ${squadCount(position)} fit.`,
        );
      }
    }
    for (const [club, count] of byClub) {
      if (count > prefs.maxPerClub) {
        const name = locked.find((player) => player.element.team === club)?.team.name || 'one club';
        throw new OptimizerError(
          `Your must-have list doesn't fit a legal squad: ${count} players from ${name}, limit is ${prefs.maxPerClub}.`,
        );
      }
    }
    const cost = locked.reduce((sum, player) => sum + player.priceTenths, 0);
    if (cost > prefs.budgetTenths) {
      throw new OptimizerError(`That budget can't cover a legal 15-man squad: your must-haves alone cost ${formatPrice(cost)}.`);
    }
    return locked;
  }

  /**
   * A trimmed shortlist per position: the best scorers, the best value, and
   * the cheapest bodies needed to fund them.
   */
  buildPool(locked) {
    const prefs = this.prefs;
    const pool = new Map();

    for (const position of POSITIONS) {
      const eligible = this.rated.filter((player) => {
        if (player.position !== position) return false;
        if (prefs.exclude.includes(player.id)) return false;
        if (prefs.mustInclude.includes(player.id)) return false;   // locked separately
        if (prefs.teamMode === 'only' && prefs.preferredTeams.length
          && !prefs.preferredTeams.includes(player.element.team)) return false;
        if (prefs.avoidInjuryRisk && isOut(player)) return false;
        return true;
      });

      if (!eligible.length) {
        throw new OptimizerError(`No ${positionName(position).toLowerCase()}s match your filters.`);
      }

      const byPoints = eligible.slice().sort((a, b) => b.projected - a.projected).slice(0, 45);
      const byValue = eligible.slice().sort((a, b) => b.valueRatio - a.valueRatio).slice(0, 45);
      const cheapest = eligible.slice().sort((a, b) => a.priceTenths - b.priceTenths).slice(0, 14);

      const seen = new Set();
      const shortlist = [];
      for (const player of [...byPoints, ...byValue, ...cheapest]) {
        if (seen.has(player.id)) continue;
        seen.add(player.id);
        shortlist.push(player);
      }
      pool.set(position, shortlist);
    }
    return pool;
  }

  // MARK: - Feasible starting point

  cheapestFeasible(pool, locked, budget) {
    const prefs = this.prefs;
    const squad = locked.slice();
    const clubCounts = new Map();
    for (const player of locked) clubCounts.set(player.element.team, (clubCounts.get(player.element.team) || 0) + 1);
    const chosen = new Set(locked.map((player) => player.id));

    for (const position of POSITIONS) {
      const needed = squadCount(position) - locked.filter((player) => player.position === position).length;
      if (needed <= 0) continue;
      const candidates = (pool.get(position) || []).slice().sort((a, b) => a.priceTenths - b.priceTenths);
      let added = 0;
      for (const player of candidates) {
        if (added >= needed) break;
        if (chosen.has(player.id)) continue;
        if ((clubCounts.get(player.element.team) || 0) >= prefs.maxPerClub) continue;
        squad.push(player);
        chosen.add(player.id);
        clubCounts.set(player.element.team, (clubCounts.get(player.element.team) || 0) + 1);
        added += 1;
      }
      if (added !== needed) {
        throw new OptimizerError(
          `Your must-have list doesn't fit a legal squad: not enough ${positionName(position).toLowerCase()}s available under the per-club limit.`,
        );
      }
    }

    const cost = squad.reduce((sum, player) => sum + player.priceTenths, 0);
    if (cost > budget) {
      throw new OptimizerError(`That budget can't cover a legal 15-man squad: the cheapest legal squad under your filters costs ${formatPrice(cost)}.`);
    }
    return squad;
  }

  // MARK: - Local search

  bestSwap(squad, score, pool, locked, budget) {
    const prefs = this.prefs;
    const lockedIDs = new Set(locked.map((player) => player.id));
    const squadIDs = new Set(squad.map((player) => player.id));
    const cost = squad.reduce((sum, player) => sum + player.priceTenths, 0);
    const clubCounts = new Map();
    for (const player of squad) clubCounts.set(player.element.team, (clubCounts.get(player.element.team) || 0) + 1);

    let best = null;
    let bestScore = score;
    const trial = squad.slice();

    for (let index = 0; index < squad.length; index += 1) {
      const outgoing = squad[index];
      if (lockedIDs.has(outgoing.id)) continue;
      const candidates = pool.get(outgoing.position) || [];
      const headroom = budget - cost + outgoing.priceTenths;

      for (const incoming of candidates) {
        if (squadIDs.has(incoming.id)) continue;
        if (incoming.priceTenths > headroom) continue;
        if (incoming.element.team !== outgoing.element.team
          && (clubCounts.get(incoming.element.team) || 0) >= prefs.maxPerClub) continue;
        trial[index] = incoming;
        const candidateScore = evaluate(trial).score;
        if (candidateScore > bestScore + 0.0001) {
          bestScore = candidateScore;
          best = { index, incoming, score: candidateScore };
        }
      }
      trial[index] = outgoing;
    }
    return best;
  }

  perturb(squad, pool, locked, budget, rng) {
    const prefs = this.prefs;
    const lockedIDs = new Set(locked.map((player) => player.id));
    const result = squad.slice();
    const squadIDs = new Set(squad.map((player) => player.id));
    const clubCounts = new Map();
    for (const player of squad) clubCounts.set(player.element.team, (clubCounts.get(player.element.team) || 0) + 1);
    let cost = squad.reduce((sum, player) => sum + player.priceTenths, 0);

    const swappable = squad.map((player, index) => index).filter((index) => !lockedIDs.has(squad[index].id));
    if (swappable.length < 2) return squad;

    for (let step = 0; step < 2; step += 1) {
      const index = swappable[rng.upTo(swappable.length)];
      const outgoing = result[index];
      const candidates = (pool.get(outgoing.position) || []).filter((candidate) => (
        !squadIDs.has(candidate.id)
        && candidate.priceTenths <= budget - cost + outgoing.priceTenths
        && (candidate.element.team === outgoing.element.team
          || (clubCounts.get(candidate.element.team) || 0) < prefs.maxPerClub)
      ));
      if (!candidates.length) continue;
      const incoming = candidates[rng.upTo(candidates.length)];

      squadIDs.delete(outgoing.id);
      squadIDs.add(incoming.id);
      clubCounts.set(outgoing.element.team, (clubCounts.get(outgoing.element.team) || 1) - 1);
      clubCounts.set(incoming.element.team, (clubCounts.get(incoming.element.team) || 0) + 1);
      cost += incoming.priceTenths - outgoing.priceTenths;
      result[index] = incoming;
    }
    return result;
  }
}

/**
 * Rebuilds the derived parts of a squad after the user has changed a player by
 * hand, so the XI, captain, bench order and totals stay consistent.
 */
export function rebuild(squad, budgetTenths, notes = [], edited = true) {
  const evaluation = evaluate(squad);
  const captain = evaluation.captain;
  const vice = bestCaptain(evaluation.starting, captain.id) || captain;
  const starting = evaluation.starting.slice().sort((a, b) => (
    a.position === b.position ? b.projected - a.projected : a.position - b.position
  ));
  const benchOutfield = evaluation.bench
    .filter((player) => player.position !== GOALKEEPER)
    .sort((a, b) => b.projected - a.projected);
  const benchGK = evaluation.bench.filter((player) => player.position === GOALKEEPER);
  const cost = squad.reduce((sum, player) => sum + player.priceTenths, 0);

  return {
    squad,
    starting,
    bench: [...benchGK, ...benchOutfield],
    captain,
    viceCaptain: vice,
    formation: evaluation.formation,
    totalCostTenths: cost,
    budgetTenths,
    projectedPoints: evaluation.startingSum + captain.projected,
    startingPoints: evaluation.startingSum,
    remainingTenths: budgetTenths - cost,
    notes,
    edited,
  };
}
