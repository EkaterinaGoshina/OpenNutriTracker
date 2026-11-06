// The web app's Worker (docs/WEB_ARCHITECTURE.md). It serves the Flutter web
// build from static assets and answers /api/* itself:
//
//   /api/off/<host><path>  read-only proxy to Open Food Facts, which sends no
//                          CORS headers, so the browser cannot call it
//                          directly. Only the endpoints the app uses pass.
//
// Photos (/api/photos/*) and the AI proxy come later.

const OFF_ALLOWED = {
  'search.openfoodfacts.org': [/^\/search$/],
  'world.openfoodfacts.org': [
    /^\/cgi\/search\.pl$/,
    /^\/api\/v2\/product\/[0-9A-Za-z]{1,32}$/,
  ],
};

// Open Food Facts asks every client to identify itself. A browser cannot set
// User-Agent, so the proxy does.
const USER_AGENT =
  'OpenNutriTracker-Web/1.0 (+https://github.com/EkaterinaGoshina/OpenNutriTracker)';

// Search results and products change slowly; an hour at the edge spares Open
// Food Facts repeat requests for the same query.
const OFF_CACHE_SECONDS = 3600;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/api/off/')) {
      return proxyOpenFoodFacts(request, url);
    }
    if (url.pathname.startsWith('/api/')) {
      return json({ error: 'not_found' }, 404);
    }
    return env.ASSETS.fetch(request);
  },
};

/** Returns the upstream URL for an allowed /api/off/ request, or null. */
export function openFoodFactsTarget(url) {
  const rest = url.pathname.slice('/api/off/'.length);
  const slash = rest.indexOf('/');
  if (slash <= 0) return null;
  const host = rest.slice(0, slash);
  const path = rest.slice(slash);
  const allowed = Object.hasOwn(OFF_ALLOWED, host) ? OFF_ALLOWED[host] : null;
  if (!allowed || !allowed.some((pattern) => pattern.test(path))) return null;
  return new URL(`https://${host}${path}${url.search}`);
}

async function proxyOpenFoodFacts(request, url) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return json({ error: 'method_not_allowed' }, 405);
  }
  const target = openFoodFactsTarget(url);
  if (!target) return json({ error: 'not_found' }, 404);

  const upstream = await fetch(target, {
    method: request.method,
    headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
    cf: { cacheTtl: OFF_CACHE_SECONDS, cacheEverything: true },
  });

  const headers = new Headers();
  for (const name of ['content-type', 'content-encoding', 'etag', 'last-modified']) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  headers.set('cache-control', `public, max-age=${OFF_CACHE_SECONDS}`);
  return new Response(upstream.body, { status: upstream.status, headers });
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
