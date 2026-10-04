// Thin client over the public (unauthenticated) fantasy football JSON API,
// reached through this site's own /api/fpl proxy because the upstream endpoints
// send no CORS headers.

/**
 * Where the proxy lives. Defaults to this site's own function. A static host
 * with no serverless support can point at a deployed one by setting
 * `squadxi.proxy` in localStorage, or passing ?proxy= once.
 */
function proxyBase() {
  const fromQuery = new URLSearchParams(location.search).get('proxy');
  if (fromQuery) {
    try { localStorage.setItem('squadxi.proxy', fromQuery); } catch { /* private mode */ }
    return fromQuery;
  }
  try {
    return localStorage.getItem('squadxi.proxy') || '/api/fpl';
  } catch {
    return '/api/fpl';
  }
}

export class FPLError extends Error {
  constructor(message, { kind = 'transport', status = null } = {}) {
    super(message);
    this.name = 'FPLError';
    this.kind = kind;
    this.status = status;
  }
}

async function fetchPath(path) {
  const url = `${proxyBase()}?path=${encodeURIComponent(path)}`;
  let response;
  try {
    response = await fetch(url, { headers: { Accept: 'application/json' } });
  } catch (error) {
    throw new FPLError(
      `Couldn't reach the data server. ${error.message}. If you opened this file directly, run it from a server instead — the live data needs the /api/fpl proxy.`,
    );
  }

  if (!response.ok) {
    if (response.status === 404) throw new FPLError('Not found.', { kind: 'notFound', status: 404 });
    let detail = '';
    try {
      detail = (await response.json()).error || '';
    } catch { /* non-JSON error body */ }
    throw new FPLError(
      `The data server replied with status ${response.status}.${detail ? ` ${detail}` : ''}`,
      { kind: 'badStatus', status: response.status },
    );
  }

  try {
    return await response.json();
  } catch (error) {
    throw new FPLError(`Couldn't read the player data: ${error.message}`);
  }
}

/** Everything the engine needs, fetched from the live endpoints. */
export async function loadLeagueData() {
  const [bootstrap, fixtures] = await Promise.all([
    fetchPath('bootstrap-static/'),
    fetchPath('fixtures/'),
  ]);

  const next = bootstrap.events.find((event) => event.is_next)
    || bootstrap.events.find((event) => event.is_current)
    || bootstrap.events.find((event) => !event.finished)
    || null;

  return {
    elements: bootstrap.elements,
    teams: bootstrap.teams,
    fixtures,
    events: bootstrap.events,
    chipWindows: bootstrap.chips || [],
    nextEvent: next,
    teamsByID: new Map(bootstrap.teams.map((team) => [team.id, team])),
    fetchedAt: new Date(),
  };
}

/**
 * Pulls a real team by its ID: the squad, what's in the bank and who wore the
 * armband last week.
 */
export async function loadTeam(id) {
  let entry;
  try {
    entry = await fetchPath(`entry/${id}/`);
  } catch (error) {
    if (error.kind === 'notFound') {
      throw new FPLError(
        `No team was found with the ID ${id}. It's the number in the address bar when you view your own team on the web.`,
        { kind: 'unknownTeamID' },
      );
    }
    throw error;
  }

  const event = entry.current_event;
  if (event === null || event === undefined) {
    throw new FPLError(
      "The season hasn't kicked off yet, so squads aren't published yet. Enter your 15 players by hand instead — it takes a minute.",
      { kind: 'seasonNotStarted' },
    );
  }

  let picks;
  try {
    picks = await fetchPath(`entry/${id}/event/${event}/picks/`);
  } catch (error) {
    if (error.kind === 'notFound') {
      throw new FPLError(
        "The season hasn't kicked off yet, so squads aren't published yet. Enter your 15 players by hand instead — it takes a minute.",
        { kind: 'seasonNotStarted' },
      );
    }
    throw error;
  }

  return {
    playerIDs: picks.picks.map((pick) => pick.element),
    bankTenths: picks.entry_history.bank,
    // The game doesn't publish how many transfers you have saved, so start from
    // one and let the user correct it.
    freeTransfers: 1,
    entryID: entry.id,
    teamName: entry.name,
    managerName: `${entry.player_first_name} ${entry.player_last_name}`,
    reportedValueTenths: picks.entry_history.value,
  };
}
