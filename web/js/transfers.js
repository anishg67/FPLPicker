// Suggests transfers for a squad the user already owns.
// Ported from Sources/Engine/TransferPlanner.swift.
//
// Works the same way the optimizer scores squads — best legal XI plus captain,
// bench discounted — so a transfer only scores well if it improves the team the
// user actually fields.

import { evaluate } from './optimizer.js';
import { isOut } from './models.js';

/** Deep enough to catch value picks, shallow enough to stay instant. */
const CANDIDATES_PER_POSITION = 70;

export class TransferPlanner {
  constructor({ squad, rated, bankTenths, freeTransfers, maxPerClub }) {
    this.squad = squad;
    this.rated = rated;
    this.bankTenths = bankTenths;
    this.freeTransfers = freeTransfers;
    this.maxPerClub = maxPerClub;
    this.pools = new Map();
  }

  plan() {
    let current = this.squad.slice();
    let bank = this.bankTenths;
    const moves = [];

    // One transfer beyond the free ones is considered, but only if it beats the
    // 4-point charge on its own.
    const ceiling = Math.max(this.freeTransfers, 1) + 1;

    for (let step = 0; step < ceiling; step += 1) {
      const best = this.rankedMoves(current, bank)[0];
      if (!best) break;
      const payingAHit = step >= this.freeTransfers;
      if (payingAHit && best.gain <= 4.0) break;
      if (best.gain <= 0.05) break;

      if (!this.isLegal(best, current, bank)) break;
      moves.push(best);
      bank -= best.priceDelta;
      current = current.map((player) => (player.id === best.outgoing.id ? best.incoming : player));
    }

    // Alternatives are offered alongside the plan, so they have to be legal
    // *after* it — the plan's own moves have already changed the club counts
    // and the bank. Ranking them against the original squad produced
    // suggestions that would break the three-per-club limit once applied.
    const takenOut = new Set(moves.map((move) => move.outgoing.id));
    const alternatives = this.rankedMoves(current, bank)
      .filter((move) => !takenOut.has(move.outgoing.id))
      .filter((move) => this.isLegal(move, current, bank))
      .slice(0, 5);

    const hits = Math.max(0, moves.length - this.freeTransfers);
    const pointsHit = hits * 4;
    const grossGain = moves.reduce((sum, move) => sum + move.gain, 0);

    return {
      moves,
      alternatives,
      freeTransfers: this.freeTransfers,
      bankTenths: this.bankTenths,
      hits,
      pointsHit,
      grossGain,
      /**
       * Gain per gameweek once the −4s are paid for. Hits are one-off, so this
       * is deliberately pessimistic: it charges the whole hit against one week.
       */
      netGain: grossGain - pointsHit,
      isEmpty: moves.length === 0,
      bankAfter: this.bankTenths - moves.reduce((sum, move) => sum + move.priceDelta, 0),
    };
  }

  // MARK: - What a chosen set of transfers would be worth

  /**
   * Applies moves one at a time, skipping any that stops being legal once the
   * earlier ones have landed.
   *
   * The user ticks moves in any order, and two perfectly good suggestions can
   * be illegal together — both buying into the same club, or both selling the
   * same player. Rather than refuse the whole selection, this takes what it can
   * and reports what it dropped.
   */
  resolve(moves, bank) {
    let current = this.squad.slice();
    let remaining = bank;
    const applied = [];
    const rejected = [];

    for (const move of moves) {
      if (!this.isLegal(move, current, remaining)) {
        rejected.push(move);
        continue;
      }
      applied.push(move);
      remaining -= move.priceDelta;
      current = current.map((player) => (player.id === move.outgoing.id ? move.incoming : player));
    }
    return { applied, rejected, squad: current, bank: remaining };
  }

  /**
   * What the squad would score with `moves` applied, and what it scores now.
   *
   * Expressed in the same currency as everything else on the squad screen — the
   * best legal XI with the captain doubled — so before and after are directly
   * comparable.
   */
  outlook(moves) {
    const resolved = this.resolve(moves, this.bankTenths);
    const before = projectedPoints(this.squad);
    const after = projectedPoints(resolved.squad);
    const count = resolved.applied.length;
    const hits = Math.max(0, count - this.freeTransfers);
    const pointsHit = hits * 4;
    const gain = after - before;

    return {
      before,
      after,
      applied: resolved.applied,
      rejected: resolved.rejected,
      freeTransfers: this.freeTransfers,
      bankBefore: this.bankTenths,
      bankAfter: resolved.bank,
      count,
      hits,
      pointsHit,
      gain,
      /** What you actually bank this week, with the hit paid for. */
      net: gain - pointsHit,
      isEmpty: count === 0,
      /**
       * How many gameweeks the gain has to hold for the hit to pay for itself.
       * Null when there's no hit, or when the move loses points anyway.
       */
      weeksToBreakEven: pointsHit > 0 && gain > 0 ? Math.ceil(pointsHit / gain) : null,
    };
  }

  // MARK: - Search

  /**
   * Whether a move would still be legal applied to this squad: same position,
   * inside the bank, and within the club limit.
   *
   * The ranking already enforces all three, but every suggestion is checked
   * again before it is offered. A move is generated against one squad and may
   * be shown beside others that have since changed it, and an illegal
   * suggestion is worse than a missing one.
   */
  isLegal(move, squad, bank) {
    if (move.outgoing.position !== move.incoming.position) return false;
    if (!squad.some((player) => player.id === move.outgoing.id)) return false;
    if (squad.some((player) => player.id === move.incoming.id)) return false;
    if (move.priceDelta > bank) return false;
    if (move.incoming.element.team !== move.outgoing.element.team) {
      const atClub = squad.filter((player) => player.element.team === move.incoming.element.team).length;
      if (atClub >= this.maxPerClub) return false;
    }
    return true;
  }

  /** Every legal single swap, best first. */
  rankedMoves(squad, bank) {
    const squadIDs = new Set(squad.map((player) => player.id));
    const clubCounts = new Map();
    for (const player of squad) clubCounts.set(player.element.team, (clubCounts.get(player.element.team) || 0) + 1);

    const baseline = evaluate(squad).score;
    const moves = [];
    const trial = squad.slice();

    for (let index = 0; index < squad.length; index += 1) {
      const outgoing = squad[index];
      const headroom = bank + outgoing.priceTenths;
      const candidates = this.pool(outgoing.position);

      for (const incoming of candidates) {
        if (squadIDs.has(incoming.id)) continue;
        if (incoming.priceTenths > headroom) continue;
        if (incoming.element.team !== outgoing.element.team
          && (clubCounts.get(incoming.element.team) || 0) >= this.maxPerClub) continue;
        trial[index] = incoming;
        const gain = evaluate(trial).score - baseline;
        if (gain > 0.05) {
          moves.push({
            id: `${outgoing.id}->${incoming.id}`,
            outgoing,
            incoming,
            gain,
            priceDelta: incoming.priceTenths - outgoing.priceTenths,
          });
        }
      }
      trial[index] = outgoing;
    }
    return moves.sort((a, b) => b.gain - a.gain);
  }

  pool(position) {
    if (this.pools.has(position)) return this.pools.get(position);
    const list = this.rated
      .filter((player) => player.position === position)
      .filter((player) => !isOut(player))
      .sort((a, b) => b.projected - a.projected)
      .slice(0, CANDIDATES_PER_POSITION);
    this.pools.set(position, list);
    return list;
  }
}

/** Projected points — best legal XI, captain doubled — for any 15. */
export function projectedPoints(squad) {
  const evaluation = evaluate(squad);
  return evaluation.startingSum + evaluation.captain.projected;
}
