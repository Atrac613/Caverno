# iPhone Video Attachments Reach The Server And Decode To Nothing (2026-08-21)

Question this answers: **a video attaches fine, the endpoint downloads all of
it, and the model answers "no video was provided". Where does it go?**

Nowhere. It arrives whole. `ffmpeg` on the server cannot open it, because
iPhone `.mov` files put the `moov` atom at the **end** and llama.cpp feeds
video to `ffmpeg` through a pipe.

Status: **diagnosed, not fixed.** Caverno needs no correction; the fix is
either upstream or a client-side remux (below).

## Reproduction

llama.cpp decodes video with this exact command
(`tools/mtmd/mtmd-helper.cpp`, `is_buf_input()` branch):

```
ffmpeg -nostdin -i cache:pipe:0 -vf fps=4.000000 -f rawvideo -pix_fmt rgb24 pipe:1 -loglevel error
```

Run it against an untouched iPhone recording:

```
$ cat IMG_8129.mov | ffmpeg -nostdin -i cache:pipe:0 -vf fps=4.0 \
    -f rawvideo -pix_fmt rgb24 pipe:1 -loglevel error | wc -c
0
[cache @ ...] Inner protocol failed to seekback end : -78
[mov,mp4,m4a,3gp,3g2,mj2 @ ...] moov atom not found
Error opening input file cache:pipe:0.
```

The file is fine; the box order is what breaks it:

```
IMG_8129.mov   ftyp  wide  mdat(7,914,252)  moov   <- moov last
```

llama.cpp is aware of the hazard. Its own comment reads:

> `cache:pipe:0` wraps stdin with a seekable in-memory cache, letting ffmpeg
> seek backwards for container headers (e.g. MP4 moov atom at end of file)

The wrapper does not work here, and **the failure is silent**: no error is
returned, the media chunk simply expands to zero frames and the turn answers
without it. That silence is what made this expensive to find.

## A/B against the live endpoint

Same video, same server (`qwen3.8-27b-vision`), only the box order differs:

| File | `prompt_tokens` | Answer |
|---|---:|---|
| `IMG_8129.mov` as recorded | **21** | "Since no video was provided, I cannot describe it." |
| same video, `moov` moved to the front | **38,465** | "A young boy in a striped shirt and red shorts hops across a series of large, flat stepping stones in a flowing river…" |

This is not an edge case. Every iPhone and QuickTime recording is written this
way, so it is the default shape of the most likely video a person attaches.

## Confirmed in the app

The same recording, converted to mp4 before attaching, went through the real
composer and worked on the first try:

```
"mediaType": "video/mp4", "sizeBytes": 7464597,
"path": "/Users/…/IMG_8129.mp4", "delivery": "url",
"deliveredAs": "http://192.168.100.5:62420/v/ATLh50bc…"

promptTokens: 49869
```

The answer describes the actual footage — 飛び石, the river, the stone walls and
the traditional houses behind it. So the feature is whole; what it cannot take
is the container as the phone writes it. **Converting before attaching is the
workaround until the fix below is taken.**

## What was ruled out

The server handles everything else. Each row was sent to the live endpoint:

| Probe | `prompt_tokens` | |
|---|---:|---|
| 3s h264 mp4, `input_video` | 7,300 | ok |
| the same via **`video_url`** | 7,300 | ok — this endpoint accepts the standard shape, no proxy needed |
| 3s HEVC `.mov` (hvc1) | 7,300 | ok |
| 5s 10-bit Main10 HEVC | 11,879 | ok |
| 20s 1080p HEVC | 41,473 | ok |
| served by Caverno's `MediaHostService` | 41,473 | ok |

Codec, container, bit depth, duration and delivery path are all innocent.

## Caverno's side is correct end to end

From the session log and the media host access log of the failing turn:

```
"delivery": "url",
"deliveredAs": "http://192.168.100.5:60626/v/sEYRRypb..."

16:44:03.496 [Video] serving /Users/…/IMG_8129.mov at http://192.168.100.5:60626/v/sEYRRypb…
16:44:03.829 [MediaHost] GET /v/sEYRRypb... -> 200 (sent 7932096 bytes) from 192.168.100.241
```

Byte count matches the file exactly, in 333 ms. Do not re-investigate the
attachment, the request shape, or the delivery path; they are proven.

## The fix, if it is taken

A **remux, not a re-encode**. Move `moov` ahead of `mdat` and add the resulting
delta to every chunk offset in `stco`/`co64`. No decoder, no quality change, no
`ffmpeg` dependency. Prototyped on the real file:

```
patched 111 chunk offsets by +17808 bytes

IMG_8129.mov   size=7932096  mdat=7914252  sha256=93517eff6c5c816c…
   boxes: ftyp wide mdat moov
pure.mov       size=7932096  mdat=7914252  sha256=93517eff6c5c816c…
   boxes: ftyp moov wide mdat
```

Identical size, byte-identical `mdat`, all four streams kept (audio, video and
both `mebx` metadata tracks). The rewritten file then yields 67,276,800 bytes
of frames from the command above, and 38,465 prompt tokens from the server.

Note that `ffmpeg -c copy -movflags +faststart` is **not** equivalent: it
rebuilds the container and drops the `mebx` tracks, shrinking `mdat` from
7,914,252 to 7,798,130 bytes. Relocating the box by hand loses nothing.

Boundary conditions the implementation has to answer for:

- **co64 promotion** — an offset that crosses 4 GB no longer fits `stco`.
  Unreachable under the 10 MB attachment cap; assert rather than silently wrap.
- **Fragmented MP4** (`moof`) — different layout; detect and pass through.
- **`moov` already first** — no-op, so a well-formed mp4 costs nothing.
- **Memory** — the transform needs the whole file resident. Fine at 10 MB;
  write the result into the attachments directory and serve that.

Roughly 200-300 lines plus tests. Tests can synthesise a moov-at-end file, so
no personal video needs to enter the repository.

## Upstream

Worth reporting to llama.cpp, with two parts:

1. `cache:pipe:0` does not seek back (`Inner protocol failed to seekback end :
   -78`), so a moov-at-end MP4 cannot be decoded from buffer input at all.
2. The decode failure is swallowed. Returning zero frames without an error
   makes the endpoint answer as though no media was sent, which is
   indistinguishable from a client that never attached one.

Note the non-buffer branch passes a real path and would seek fine, so
`--media-path` with `file://` is unaffected.
