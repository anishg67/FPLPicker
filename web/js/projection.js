// Turns raw stats into a single expected-points-per-gameweek number.
// Ported from Sources/Engine/ProjectionEngine.swift — same arithmetic, so the
// web app and the iOS app agree on every projection.

import { GOALKEEPER, DEFENDER, MIDFIELDER, FORWARD, num, availabilityOf, formatPrice } from './models.js';

/**
 * How many full matches of evidence it takes before a player's own scoring
 * outweighs the prior. Higher = more conservative early in a season.
 */
export const PRIOR_STRENGTH = 5.0;

/** Fixtures for the next `horizon` scheduled gameweeks. */
function upcomingFixtures(fixtures, horizon) {
  const pending = fixtures.filter((fixture) => !fixture.finished);
  const events = [...new Set(pending.map((fixture) => fixture.event).filter((event) => event !== null))].sort((a, b) => a - b);
  if (!events.length) return pending;
  const window = new Set(events.filter((event) => event < events[0] + horizon));
  return pending.filter((fixture) => fixture.event !== null && window.has(fixture.event));
}

/** Expected points per 90 implied by underlying stats, by position. */
function underlyingRate(element) {
  if (element.minutes < 270) return 0;
  const xg = num(element.expected_goals_per_90);
  const xa = num(element.expected_assists_per_90);
  const cs = num(element.clean_sheets_per_90);
  const saves = num(element.saves_per_90);
  const defensive = num(element.defensive_contribution_per_90);

  switch (element.element_type) {
    case GOALKEEPER: return 2.0 + cs * 4.0 + saves / 3.0;
    case DEFENDER: return 2.0 + cs * 4.0 + xg * 6.0 + xa * 3.0 + defensive * 0.15;
    case MIDFIELDER: return 2.0 + cs * 1.0 + xg * 5.0 + xa * 3.0 + defensive * 0.12;
    case FORWARD: return 2.0 + xg * 4.0 + xa * 3.0;
    default: return 0;
  }
}

export class ProjectionEngine {
  constructor(data, prefs) {
    this.data = data;
    this.prefs = prefs;
    this.teamsByID = data.teamsByID;

    const horizon = Math.max(1, Math.min(10, prefs.fixtureHorizon));
    const upcoming = upcomingFixtures(data.fixtures, horizon);

    const difficultySum = new Map();
    const counts = new Map();
    for (const fixture of upcoming) {
      difficultySum.set(fixture.team_h, (difficultySum.get(fixture.team_h) || 0) + fixture.team_h_difficulty);
      counts.set(fixture.team_h, (counts.get(fixture.team_h) || 0) + 1);
      difficultySum.set(fixture.team_a, (difficultySum.get(fixture.team_a) || 0) + fixture.team_a_difficulty);
      counts.set(fixture.team_a, (counts.get(fixture.team_a) || 0) + 1);
    }
    this.fdrByTeam = new Map();
    for (const [team, sum] of difficultySum) {
      this.fdrByTeam.set(team, sum / Math.max(1, counts.get(team) || 1));
    }
    this.fixtureCountByTeam = counts;
    this.maxMinutes = Math.max(90, ...data.elements.map((element) => element.minutes), 90);
  }

  rateAll() {
    return this.data.elements.map((element) => this.rate(element)).filter(Boolean);
  }

  rate(element) {
    const team = this.teamsByID.get(element.team);
    if (!team) return null;
    const prefs = this.prefs;
    const reasons = [];

    // 1. Scoring rate ------------------------------------------------------
    // What the player has actually produced so far this season.
    const perGame = num(element.points_per_game);
    const per90 = element.minutes >= 270 ? element.total_points / (element.minutes / 90) : perGame;
    const seasonRate = element.minutes >= 270 ? 0.5 * perGame + 0.5 * per90 : perGame;

    const formRate = num(element.form);
    const formWeight = formRate > 0 ? Math.max(0, Math.min(1, prefs.formWeight)) : 0;
    let observed = formWeight * formRate + (1 - formWeight) * seasonRate;

    // Underlying numbers catch players whose returns haven't landed yet.
    const underlying = underlyingRate(element);
    if (underlying > 0) observed = 0.75 * observed + 0.25 * underlying;

    // What to expect of the player before this season's sample means anything.
    // The game's own expected points for the next gameweek is already regressed
    // and exists even for players yet to kick a ball; price is the fallback,
    // since the market prices quality in.
    const epNext = num(element.ep_next);
    const prior = epNext > 0 ? epNext : 1.5 + Math.max(0, element.now_cost / 10 - 4.0) * 0.22;

    // Shrink the observed rate toward that prior by how much football we have
    // actually seen. One match is weak evidence — it makes a 14-point cameo
    // look like a 14-point-per-week striker, and a £15m forward who hasn't
    // played yet look worthless. As minutes pile up the prior fades on its own.
    const ninetiesPlayed = element.minutes / 90;
    const reliability = ninetiesPlayed / (ninetiesPlayed + PRIOR_STRENGTH);
    let base = reliability * observed + (1 - reliability) * prior;

    // Nudge for penalty duty — the single biggest source of cheap points.
    if (element.penalties_order === 1 && element.element_type !== GOALKEEPER) {
      base *= 1.08;
      reasons.push('On penalties');
    }

    // 2. Fixtures ----------------------------------------------------------
    const fdr = this.fdrByTeam.get(element.team) ?? 3.0;
    const games = this.fixtureCountByTeam.get(element.team) ?? 1;
    let fixtureMultiplier = 1.0 + (3.0 - fdr) * 0.10;
    // A double gameweek (or a blank) genuinely changes expected returns.
    const horizon = Math.max(1, Math.min(10, prefs.fixtureHorizon));
    const gamesPerWeek = games / horizon;
    if (gamesPerWeek > 1.05) fixtureMultiplier *= Math.min(1.35, gamesPerWeek);
    if (gamesPerWeek < 0.95) fixtureMultiplier *= Math.max(0.6, gamesPerWeek);
    fixtureMultiplier = Math.min(1.45, Math.max(0.6, fixtureMultiplier));

    if (fdr <= 2.4) reasons.push(`Kind fixtures (avg FDR ${fdr.toFixed(1)})`);
    if (fdr >= 3.8) reasons.push(`Tough run (avg FDR ${fdr.toFixed(1)})`);

    // 3. Minutes security ---------------------------------------------------
    const minutesShare = Math.min(1.0, element.minutes / this.maxMinutes);
    // The same small-sample problem: after one round a single start makes a
    // squad player look nailed, and a rested regular look dropped.
    const leagueNineties = this.maxMinutes / 90;
    const minutesConfidence = leagueNineties / (leagueNineties + 3.0);
    const trustedShare = minutesConfidence * minutesShare + (1 - minutesConfidence) * 0.75;
    const strictness = prefs.avoidInjuryRisk ? 0.45 : 0.25;
    const minutesFactor = (1 - strictness) + strictness * trustedShare;
    if (minutesConfidence > 0.5) {
      if (minutesShare > 0.85) reasons.push('Nailed starter');
      else if (minutesShare < 0.35 && element.minutes > 0) reasons.push('Rotation risk');
    }

    // 4. Availability -------------------------------------------------------
    const availability = availabilityOf(element);
    let availabilityFactor = availability.multiplier;
    if (prefs.avoidInjuryRisk && availability.kind === 'doubtful') availabilityFactor *= 0.8;
    if (availability.label) reasons.push(availability.label);

    // 5. Risk appetite ------------------------------------------------------
    // Positive appetite rewards low ownership, negative rewards the template.
    const ownership = num(element.selected_by_percent);
    const ownershipTilt = (15.0 - Math.min(60.0, ownership)) / 100.0;
    const riskFactor = 1.0 + prefs.riskAppetite * ownershipTilt * 0.9;
    if (prefs.riskAppetite > 0.25 && ownership < 8) reasons.push(`Differential (${ownership.toFixed(1)}% owned)`);
    if (prefs.riskAppetite < -0.25 && ownership > 25) reasons.push(`Template pick (${ownership.toFixed(0)}% owned)`);

    // 6. Club preference (soft bias mode only) ------------------------------
    let teamBias = 1.0;
    if (prefs.teamMode === 'bias' && prefs.preferredTeams.includes(element.team)) {
      teamBias = 1.12;
      reasons.push(`Your club: ${team.short_name}`);
    }

    // Everything except the horizon-averaged fixture multiplier, so a specific
    // gameweek's fixture count can be applied instead.
    const perMatch = Math.max(0, base * minutesFactor * availabilityFactor * riskFactor * teamBias);
    const projected = Math.max(0, perMatch * fixtureMultiplier);

    if (formRate >= 6 && reliability > 0.3) reasons.unshift(`Hot form (${formRate.toFixed(1)})`);
    if (element.now_cost <= 45 && projected >= 2.6) reasons.push(`Great value at ${formatPrice(element.now_cost)}`);

    return {
      element,
      team,
      id: element.id,
      position: element.element_type,
      priceTenths: element.now_cost,
      projected,
      perMatch,
      baseRate: base,
      fixtureScore: fdr,
      minutesShare,
      availability,
      reasons: reasons.slice(0, 3),
      /** Points per gameweek per £1m — the value metric the optimizer leans on. */
      valueRatio: projected / Math.max(0.1, element.now_cost / 10),
    };
  }
}
