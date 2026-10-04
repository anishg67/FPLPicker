// Looks up what each club has coming, for the fixture ticker.
// Ported from Sources/Engine/FixturePlanner.swift.
//
// Works in gameweeks rather than matches so that doubles and blanks show up as
// themselves. Five matches ahead and five gameweeks ahead are different things
// once fixtures start moving around, and the gameweek is the unit a manager
// actually plans in.

export class FixturePlanner {
  constructor(data) {
    this.data = data;
    const teamsByID = data.teamsByID;

    // gameweek -> team -> fixtures
    const table = new Map();
    const add = (gameweek, team, fixture) => {
      if (!table.has(gameweek)) table.set(gameweek, new Map());
      const week = table.get(gameweek);
      if (!week.has(team)) week.set(team, []);
      week.get(team).push(fixture);
    };

    for (const fixture of data.fixtures) {
      if (fixture.finished) continue;
      const gameweek = fixture.event;
      if (gameweek === null || gameweek === undefined) continue;

      const home = teamsByID.get(fixture.team_h);
      const away = teamsByID.get(fixture.team_a);
      if (away) {
        add(gameweek, fixture.team_h, {
          id: fixture.id, gameweek, opponent: away, isHome: true, difficulty: fixture.team_h_difficulty,
        });
      }
      if (home) {
        add(gameweek, fixture.team_a, {
          id: fixture.id, gameweek, opponent: home, isHome: false, difficulty: fixture.team_a_difficulty,
        });
      }
    }
    this.byGameweek = table;

    const now = Date.now();
    /** Gameweeks whose deadline hasn't passed, soonest first. */
    this.actionableGameweeks = data.events
      .filter((event) => !event.finished)
      .filter((event) => (event.deadline_time ? Date.parse(event.deadline_time) : -Infinity) > now)
      .map((event) => event.id)
      .sort((a, b) => a - b);
  }

  /** The next `count` gameweeks for a club, blanks included. */
  next(count = 5, team) {
    return this.actionableGameweeks.slice(0, count).map((gameweek) => {
      const fixtures = this.byGameweek.get(gameweek)?.get(team) || [];
      return {
        gameweek,
        fixtures,
        isBlank: fixtures.length === 0,
        isDouble: fixtures.length > 1,
        // A blank is the worst case: no points at all, so it scores worse than
        // the hardest single fixture.
        difficulty: fixtures.length
          ? fixtures.reduce((sum, item) => sum + item.difficulty, 0) / fixtures.length
          : 5,
        ticker: fixtures.length ? fixtures.map(tickerLabel).join(' ') : '—',
      };
    });
  }

  /** Average difficulty over that run. */
  averageDifficulty(count = 5, team) {
    const weeks = this.next(count, team);
    if (!weeks.length) return 3;
    return weeks.reduce((sum, week) => sum + week.difficulty, 0) / weeks.length;
  }

  /** Plain-English read on a run of fixtures. */
  summary(count = 5, team) {
    const weeks = this.next(count, team);
    if (!weeks.length) return 'No fixtures scheduled yet.';
    const blanks = weeks.filter((week) => week.isBlank).length;
    const doubles = weeks.filter((week) => week.isDouble).length;
    const average = this.averageDifficulty(count, team);

    const parts = [];
    if (average < 2.5) parts.push('Kind run');
    else if (average < 3.5) parts.push('Average run');
    else parts.push('Tough run');
    parts.push(`avg FDR ${average.toFixed(1)}`);
    if (doubles) parts.push(`${doubles} double${doubles === 1 ? '' : 's'}`);
    if (blanks) parts.push(`${blanks} blank${blanks === 1 ? '' : 's'}`);
    return parts.join(' · ');
  }
}

/** Home fixtures in capitals, away in lower case, the way tickers show them. */
export function tickerLabel(fixture) {
  return fixture.isHome ? fixture.opponent.short_name.toUpperCase() : fixture.opponent.short_name.toLowerCase();
}

export function fixtureLabel(fixture) {
  return `${fixture.opponent.short_name} (${fixture.isHome ? 'H' : 'A'})`;
}

/**
 * The game's own 1-to-5 difficulty palette. A blank gameweek is drawn darker
 * than the worst fixture, because no match at all is worse than a hard one.
 */
export function difficultyColour(difficulty, isBlank) {
  if (isBlank) return '#29292f';
  if (difficulty < 2.0) return '#00ad6b';
  if (difficulty < 2.75) return '#6bc759';
  if (difficulty < 3.25) return '#6b6b80';
  if (difficulty < 4.25) return '#e36b3d';
  return '#d62e42';
}

export function difficultyLabel(difficulty) {
  if (difficulty < 2.0) return 'Very kind';
  if (difficulty < 2.75) return 'Kind';
  if (difficulty < 3.25) return 'Even';
  if (difficulty < 4.25) return 'Hard';
  return 'Very hard';
}
