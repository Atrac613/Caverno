# LL37 Second-Route Input Inventory

This inventory freezes the evidence inputs prepared for the distinct
`qwen3.6-27b-vision` verifier measurement. It records hashes only; the
consented case and manifest bodies remain in the ignored local integration-test
artifacts and are not committed.

- Candidate route: `http://192.168.100.241:1234/v1`,
  `qwen3.6-27b-vision`
- Probe schema: `caverno_ll37_verifier_fidelity_report` v3
- Input population: 10 cases, 5 objective-distinct pairs, 2 unattended source
  surfaces
- Consent: every manifest has `explicitUserConsent: true` with scope
  `personal_eval_case_recording`
- Local fixture validation: `go` with 5 correct, 5 broken, 5 objectives, 2
  surfaces, 0 invalid, and 0 unverifiable results. This validates corpus shape
  only and is not verifier-fidelity evidence.

| Case ID | Case SHA-256 | Manifest SHA-256 |
|---------|--------------|------------------|
| `ll37-worktree-agent-live-1786546710457-candidate-a` | `5486abb17284bfab9a4fb4a7b1bc6508398bb2e3c280ff4df0b0c425eed871a2` | `82017e7bb27faa8311e76d87ae4d67e76f7843ded61ae2724c433b2bde7b4c96` |
| `ll37-worktree-agent-live-1786546710457-candidate-b` | `5484bf95bc94415d68ec0ad40b918dfc2941bba32862341a1df3f2d5e8dc2c30` | `76aa35b3bab4498fe22e7564aa60285c4889c8faa9ce264fe13c515e32fb2588` |
| `ll37-routine-live-1786579269294-candidate-a` | `62c1995f9976ab509f96c0ad74c5eaca13112f5d74ee969ba287f3feaf4e04a3` | `40a580a97d2c39758904c21abe3ee945de4c072886d5a94d938eb67e0d66a612` |
| `ll37-routine-live-1786579269294-candidate-b` | `2288c6ddf1ebbeadeab449a24d93b0b0f7f9038d7c938aaea022a3d2390eb437` | `98eed695e2c9eab2740ee75c9443bda2f06d8ef9f4caf634bb9bf32c77939958` |
| `ll37-routine-feature_flag-1786582713294-candidate-a` | `355308d6cf414154cf060f9b9d29c96bf62de52ac90efd400c4f551ddb98c95d` | `82b1dab92f9b04094a88e3d4d0a11dbf4ffa4d59d3f8738adbde364ba02c871b` |
| `ll37-routine-feature_flag-1786582713294-candidate-b` | `0e465bf93ccc904b5e38d0bc69b3f0f203cca9bbd6cb054acae5ed58363917dd` | `77d597ec7a23ac8e56e7123b06c31a8ea58f2487ef88bc40f208784dbd4eb3fb` |
| `ll37-routine-retry_limit-1786582744226-candidate-a` | `7304a429772881f64de0ae060bd62ea1a7f18002a954d3f62cde5e71fc48cc4e` | `c49dcf6a9562b436624fe28470e3e369b486599693f40e1e0ded8b9a5594e6ba` |
| `ll37-routine-retry_limit-1786582744226-candidate-b` | `0022f77531b2bf707df4e476c1ba1aac8b64107641476e4934a2e51d820c2def` | `01bd9d30b387eedcd7db61a2db7ff20d1b0c3ad084df2a12b32904967e7f3c36` |
| `ll37-routine-display_format-1786583171158-candidate-a` | `f554eeece1b4c5acb15a6b5d81e055659c03392ba4b28ecdc1176318447e3584` | `e28ee71d378f95bccee42a6d1511683029f929a8d585a8ee2a2adc71ccd67390` |
| `ll37-routine-display_format-1786583171158-candidate-b` | `3518a9b7e87728bfb6a630238f1433203377fb88c372dfd22e7aa8110d5f4a55` | `4ebce7dff23aaffe6ebfcf149555b6c0a0da2f0c802ab01e66e19bf5d77203b0` |

## Live-Measurement Boundary

The live probe sends each case's objective, acceptance criteria, changed-file
evidence, and implementation evidence to the LAN endpoint. No live report was
accepted in this preparation pass because that concrete payload-to-destination
transfer requires explicit authorization in the active conversation. Do not
infer a Go decision from the fixture result.
