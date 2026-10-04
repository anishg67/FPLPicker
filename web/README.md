# Squad XI — web

The web version of the Squad XI iOS app. Same engine, same arithmetic: the
projection model, the squad optimizer, the transfer planner and the chip planner
are direct ports of `Sources/Engine/*.swift`, so both apps produce the same
squad from the same data.

Everything runs in the browser. There is no account, no database, no third-party
analytics and no third-party advertising. What you enter is kept in
`localStorage` on your own machine and never leaves it.

## Why there is a server part at all

The public fantasy JSON API sends no CORS headers, so a browser refuses to read
it. `api/fpl.js` is a small serverless function that makes the request
server-side and returns the JSON with the headers a browser needs. It only
forwards four read-only paths:

```
bootstrap-static/
fixtures/
entry/{id}/
entry/{id}/event/{gw}/picks/
```

Anything else is rejected, so it can't be used as an open proxy.

## Run it locally

```bash
cd web && npm run dev
```

Then open <http://localhost:4321>. No dependencies to install — `server.mjs`
uses only the Node standard library and serves the same proxy function the
deployed site uses. Needs Node 18 or newer.

## Deploy it

### Vercel (what this is set up for)

```bash
cd web && npx vercel deploy --prod
```

The static files publish as-is and `api/fpl.js` becomes a function at
`/api/fpl`. Nothing to configure.

### Netlify

Serverless functions live in a different directory, so move the proxy and point
Netlify at it:

```bash
cd web && mkdir -p netlify/functions && cp api/fpl.js netlify/functions/fpl.js
```

Then add a `netlify.toml` with a redirect from `/api/fpl` to
`/.netlify/functions/fpl`, and publish the `web` directory.

### Cloudflare Pages

Rename `api/fpl.js` to `functions/api/fpl.js` and change the export to
Cloudflare's `onRequest(context)` signature — the body of the function is
otherwise the same `fetch` call.

### A static-only host (GitHub Pages, S3, a plain web server)

A host with no serverless support can't run the proxy, so point the page at one
that is already deployed somewhere else:

```
https://your-static-site.example/?proxy=https://your-vercel-app.vercel.app/api/fpl
```

The value is remembered in `localStorage`, so the query string is only needed
once per browser.

## Files

| Path | What it is |
| --- | --- |
| `index.html` | The page shell. Everything else is built by script. |
| `styles.css` | The whole stylesheet: dark and light, five accents. |
| `js/models.js` | Positions, availability, chips, preferences, squad validation. |
| `js/projection.js` | Expected points per gameweek per player. |
| `js/optimizer.js` | The constrained squad search. |
| `js/transfers.js` | Transfer suggestions for a squad you already own. |
| `js/chips.js` | When to play Bench Boost, Triple Captain, Free Hit, Wildcard. |
| `js/fixtures.js` | The next few gameweeks per club, for the fixture ticker. |
| `js/content.js` | Survey questions and the jargon buster. |
| `js/ui.js` | DOM helpers and the shared components. |
| `js/app.js` | State, screens and routing. |
| `api/fpl.js` | The CORS proxy. |
| `server.mjs` | Local dev server; serves the static files and the proxy. |

## Keeping it in step with the iOS app

The four engine modules are ports, not re-interpretations. If the Swift model
changes — the shrinkage prior, the bench weight, a chip threshold — change the
JavaScript to match, or the two apps will quietly disagree. The constants that
matter are named the same in both.
