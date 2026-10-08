# LL14 Model-Switch Handoff Live Measurement

Date: 2026-06-14

## Command

```bash
fvm dart run tool/ll14_model_switch_handoff_measurement.dart \
  --base-url http://192.168.100.241:1234/v1 \
  --api-key no-key \
  --model qwen3.6-35b-a3b-vision \
  --previous-model previous-local-model \
  --turn-count 64 \
  --turn-detail-chars 320 \
  --max-tokens 16 \
  --timeout-seconds 240 \
  --output /tmp/caverno_ll14_model_switch_handoff_measurement_2026-06-14.json \
  --format markdown
```

Raw JSON artifact:

```text
/tmp/caverno_ll14_model_switch_handoff_measurement_2026-06-14.json
```

## Result

Endpoint model: `qwen3.6-35b-a3b-vision`

| Mode | Messages | Estimated prompt tokens | prompt_n | prompt_ms |
| --- | ---: | ---: | ---: | ---: |
| `full_history_replay` | 66 | 7291 | 5382 | 2045.685 |
| `model_switch_handoff` | 12 | 2253 | 1294 | 586.408 |

## Comparison

- Estimated prompt-token reduction: `5038` (`69.1%`).
- Live `timings.prompt_ms` reduction: `1459.277 ms` (`71.3%`).
- `timings.prompt_n` dropped from `5382` to `1294`.
- The model-switch handoff path improved the first-token proxy for this long-conversation fixture.

## Acceptance Notes

- The measurement used `cache_prompt: false` for both requests so the result reflects cold model-switch prompt work rather than slot cache reuse.
- Stale tool-result mutation remains limited to compact prompt boundaries; focused tests cover protected current-task paths, mixed protected/unprotected duplicate reads, command results, and side-effect results.
