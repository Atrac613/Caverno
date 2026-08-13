# LL37 Verifier Fidelity Probe

- Gate: `go`
- Mode: `live_llm`
- Model: `qwen3.6-27b-vision`
- Base URL: `http://192.168.100.241:1234/v1`
- Eligible pairs: `5`
- Eligible objectives: `5`
- Eligible source surfaces: `2`

## Metrics

| Population | Cases | Correct | Broken | False refutes | Broken recall | Unverifiable | Invalid |
|------------|------:|--------:|-------:|--------------:|--------------:|-------------:|--------:|
| All | 10 | 5 | 5 | 0.0% | 100.0% | 0 | 0 |
| Eligible | 10 | 5 | 5 | 0.0% | 100.0% | 0 | 0 |

## Cases

| Case | Surface | Expected | Verdict | Confidence | Result |
|------|---------|----------|---------|-----------:|--------|
| ll37-worktree-agent-live-1786546710457-candidate-a | worktree_agent | not_refuted | not_refuted | 1.00 | match |
| ll37-worktree-agent-live-1786546710457-candidate-b | worktree_agent | refuted | refuted | 1.00 | match |
| ll37-routine-live-1786579269294-candidate-a | routine | not_refuted | not_refuted | 1.00 | match |
| ll37-routine-live-1786579269294-candidate-b | routine | refuted | refuted | 1.00 | match |
| ll37-routine-feature_flag-1786582713294-candidate-a | routine | not_refuted | not_refuted | 1.00 | match |
| ll37-routine-feature_flag-1786582713294-candidate-b | routine | refuted | refuted | 1.00 | match |
| ll37-routine-retry_limit-1786582744226-candidate-a | routine | not_refuted | not_refuted | 1.00 | match |
| ll37-routine-retry_limit-1786582744226-candidate-b | routine | refuted | refuted | 1.00 | match |
| ll37-routine-display_format-1786583171158-candidate-a | routine | not_refuted | not_refuted | 1.00 | match |
| ll37-routine-display_format-1786583171158-candidate-b | routine | refuted | refuted | 1.00 | match |
