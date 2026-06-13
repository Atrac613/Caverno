# LL6 Prefix-Stable Live Measurement

Generated: 2026-06-14T01:53:09.201979

## Scenario

- Endpoint: `http://192.168.100.241:1234/v1`
- Model: `gemma-4-26B-A4B-it-Q4_K_M.gguf`
- Tool count: 30 synthetic tools plus `tool_search`
- Max tokens: 16
- Slot isolation: default mode used `id_slot=22`; prefix-stable mode used
  `id_slot=23`
- Runner:
  `fvm dart run tool/ll6_prefix_stability_measurement.dart --base-url http://192.168.100.241:1234/v1 --api-key no-key --model gemma-4-26B-A4B-it-Q4_K_M.gguf --tool-count 30 --max-tokens 16 --id-slot 22 --timeout-seconds 180 --output /tmp/caverno_ll6_prefix_stability_measurement.json --format markdown`

The default mode mimics dynamic tool loading by sending `tool_search` on the
initial request and only the selected target tool on the follow-up request. The
prefix-stable mode sends the same full tool list on both requests.

## Result

| Mode | Initial tools | Follow-up tools | id_slot | Initial cache_n / prompt_n | Follow-up cache_n / prompt_n | Follow-up cached share | Follow-up prompt_ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `default_dynamic` | 1 | 1 | 22 | 0 / 308 | 0 / 374 | 0.0% | 255.571 |
| `prefix_stable` | 31 | 31 | 23 | 0 / 2308 | 2279 / 88 | 96.3% | 128.025 |

## Acceptance Evidence

- The default follow-up request had no prompt cache reuse:
  `cache_n=0`, `prompt_n=374`.
- The prefix-stable follow-up request reused nearly all of the previous prompt:
  `cache_n=2279`, `prompt_n=88`.
- The raw acceptance ratio `timings.cache_n / prompt_n` improved from `0.0` to
  `25.8977`.
- The cached share `cache_n / (cache_n + prompt_n)` improved from `0.0%` to
  `96.3%`.
- Follow-up prompt prefill time dropped from `255.571 ms` to `128.025 ms` in
  this small-token measurement.

## Notes

llama.cpp reports `prompt_n` as the non-cached prompt work for this endpoint, so
`cache_n / prompt_n` can exceed `1.0` when most of the prompt is cached. The
runner records both the raw acceptance ratio and cached share to make the result
easy to interpret.
