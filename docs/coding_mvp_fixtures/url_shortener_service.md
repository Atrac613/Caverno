# CMVP-5 · URL shortener service

Difficulty: **Advanced** · Core skill: in-memory HTTP service, routing, status
codes

The most demanding fixture: the model must stand up a real HTTP server, route by
method and path, and return correct status codes — then the reviewer verifies it
by making live requests. It exercises the tool loop's ability to run a
long-lived process and check it while it's up (see
[long_running_process_mvp_tasks.md](../long_running_process_mvp_tasks.md)).

## Brief

> Build a tiny URL shortener as a local HTTP service. I can POST a long URL and
> get back a short code, and visiting that short code redirects me to the
> original URL. If a code doesn't exist, I should get a proper "not found". It
> can keep everything in memory — no database needed.

## Scope

In scope:

- An HTTP server on a configurable port (default fine).
- `POST /shorten` with a URL in the body → returns a short code (and/or the full
  short URL).
- `GET /<code>` → HTTP redirect to the original URL.
- Unknown code → `404`.
- In-memory storage.

Out of scope:

- Persistence across restarts, authentication, custom aliases, analytics.
- A front-end / HTML pages (JSON + redirects are enough).
- Rate limiting, TLS.

## Functional requirements

1. `POST /shorten` accepts a URL (JSON body `{"url": "..."}` or form field),
   generates a short code, stores the mapping, and returns the code (e.g.
   `{"code": "ab12"}` or `{"short_url": ".../ab12"}`) with `200`/`201`.
2. `GET /<code>` returns a `301`/`302` redirect whose `Location` header is the
   original URL.
3. `GET /<unknown>` returns `404`.
4. `POST /shorten` with a missing or malformed body returns `400`, not `500`.
5. The same input URL may reuse an existing code or mint a new one — either is
   acceptable — but a returned code must always resolve back to its URL.
6. Codes are URL-safe and collision-free within the process lifetime.

## Acceptance criteria

- [ ] `POST /shorten` with a valid URL returns `2xx` and a non-empty code.
- [ ] `GET /<that code>` returns a redirect (`301`/`302`) with `Location` equal
      to the original URL.
- [ ] Following the redirect end-to-end lands on the original URL.
- [ ] `GET /<never-created code>` returns `404`.
- [ ] `POST /shorten` with an empty/garbage body returns `400` (a client error),
      not `500` or a crash.
- [ ] Two different URLs shortened in the same session both resolve to their own
      originals (no code collision overwrite).

## Suggested verification

Start the server (as a background process so the tool loop can keep inspecting
it), then drive it with curl:

```bash
# 1. shorten
curl -s -X POST localhost:8080/shorten \
  -H 'content-type: application/json' \
  -d '{"url":"https://example.com/very/long/path"}'
# -> {"code":"ab12"} (or {"short_url":".../ab12"}), status 2xx

# 2. resolve (do NOT auto-follow, inspect the redirect itself)
curl -s -i localhost:8080/ab12 | head -1        # -> 301/302
curl -s -i localhost:8080/ab12 | grep -i location  # -> the original URL
curl -s -L localhost:8080/ab12                  # -> reaches example.com

# 3. unknown code
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/zzzz   # -> 404

# 4. bad request
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8080/shorten -d ''   # -> 400
```

Confirm the server is still running and the code claim is not premature: the
completion-claim guard should not accept "done" while the server process is down
or a request 500s.

## Common failure modes

- **200 instead of redirect**: `GET /<code>` returns the URL in the body rather
  than a `Location`-header redirect.
- **500 on bad input**: malformed body throws instead of returning `400`.
- **Code collision**: a weak generator reuses codes and a second shorten
  overwrites the first mapping, so an old code resolves to the wrong URL.
- **Premature completion**: model claims success without ever starting the
  server or issuing a request against it.
- **Blocking start**: server started in the foreground blocks the tool loop; it
  must run as a background process so it can be probed while alive.
- **Scope creep**: adding a database, HTML UI, or auth turns the advanced-but-
  bounded MVP into something the loop can't finish.
