// Serverless proxy for the public fantasy football JSON API.
//
// The browser can't call that API directly: it sends no CORS headers, so every
// fetch from a web page is blocked before it leaves. This function makes the
// request server-side and hands the JSON back with the headers a browser needs.
//
// Only the handful of read-only paths the app actually uses are allowed
// through, so this can't be used as an open proxy for arbitrary URLs.

const ORIGIN = 'https://fantasy.premierleague.com/api/';

const ALLOWED = [
  /^bootstrap-static\/$/,
  /^fixtures\/$/,
  /^entry\/\d{1,10}\/$/,
  /^entry\/\d{1,10}\/event\/\d{1,2}\/picks\/$/,
];

// Long enough that a page reload is instant, short enough that prices and
// injury news stay current. Picks change only at a deadline.
function cacheFor(path) {
  if (path.startsWith('entry/')) return 'public, max-age=60, s-maxage=300';
  return 'public, max-age=120, s-maxage=600';
}

export default async function handler(request, response) {
  const path = (new URL(request.url, 'http://localhost').searchParams.get('path') || '').replace(/^\/+/, '');

  if (!ALLOWED.some((pattern) => pattern.test(path))) {
    response.status(400).json({ error: 'Unsupported path.' });
    return;
  }

  try {
    const upstream = await fetch(ORIGIN + path, {
      headers: {
        // The endpoint 403s requests without a browser-ish user agent.
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        Accept: 'application/json',
      },
    });

    if (!upstream.ok) {
      response.status(upstream.status).json({ error: `Upstream replied ${upstream.status}.`, status: upstream.status });
      return;
    }

    const body = await upstream.text();
    response.setHeader('Content-Type', 'application/json; charset=utf-8');
    response.setHeader('Cache-Control', cacheFor(path));
    response.setHeader('Access-Control-Allow-Origin', '*');
    response.status(200).send(body);
  } catch (error) {
    response.status(502).json({ error: `Couldn't reach the data server: ${error.message}` });
  }
}
