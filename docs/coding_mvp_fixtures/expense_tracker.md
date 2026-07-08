# CMVP-4 · Expense tracker

Difficulty: **Intermediate** · Core skill: stateful records, aggregation, CSV
export

Combines the persistence of CMVP-1 with real aggregation and a second output
format. Money makes correctness objective: category totals and a grand total
either add up or they don't, and rounding mistakes surface immediately.

## Brief

> Build a command-line expense tracker. I want to record expenses with an
> amount, a category, and a short note, see a summary of how much I've spent per
> category, and export everything to a CSV I can open in a spreadsheet. My
> expenses should persist between runs.

## Scope

In scope:

- Add an expense: amount, category, note.
- List recorded expenses.
- A summary: total per category and a grand total.
- Export all expenses to a CSV file.
- Persist expenses between runs to a local file.

Out of scope:

- Budgets, recurring expenses, multi-currency, date filtering.
- Charts, GUI, network sync.

## Functional requirements

1. `add <amount> <category> <note...>` records an expense; amount is a positive
   number with up to 2 decimal places. Reject non-numeric or negative amounts
   with a clear error and non-zero exit.
2. Amounts are stored and summed without floating-point drift (use integer minor
   units or a decimal type; `0.1 + 0.2` must total `0.30`, not `0.30000004`).
3. `list` shows each expense with amount, category, and note.
4. `summary` prints each category with its total and a final grand total; the
   grand total equals the sum of the category totals.
5. `export <path>` writes a CSV with a header row and one row per expense;
   notes containing commas or quotes are properly quoted per CSV rules.
6. State persists between runs; a missing state file is an empty tracker, not a
   crash.

## Acceptance criteria

- [ ] Adding `10.00 food lunch`, `5.50 food coffee`, `20.00 transport taxi`
      gives a summary of `food 15.50`, `transport 20.00`, grand total `35.50`.
- [ ] Adding `0.10 food a` and `0.20 food b` reports `food 0.30` exactly — no
      binary-float artifact.
- [ ] Grand total always equals the sum of category totals.
- [ ] `add -5 food x` and `add abc food x` are rejected with a clear message and
      non-zero exit; nothing is recorded.
- [ ] A note containing a comma (e.g. `dinner, with team`) round-trips through
      the CSV without breaking columns (proper quoting).
- [ ] Expenses persist across a fresh process run.

## Suggested verification

```bash
<run> add 10.00 food lunch
<run> add 5.50 food coffee
<run> add 20.00 transport taxi
<run> summary            # -> food 15.50 / transport 20.00 / total 35.50
<run> add 0.10 food a
<run> add 0.20 food b
<run> summary            # -> food total ends in .80 exactly, no .8000001
<run> add -5 food x; echo "exit=$?"    # -> rejected, non-zero, not recorded
<run> add 3.00 misc "dinner, with team"
<run> export out.csv
# open out.csv: header + rows, the comma-containing note stays in one field
<run> summary            # NEW process -> totals unchanged (persistence)
```

Open the CSV in a spreadsheet or `csv`-parse it; a note with a comma landing in
two columns is a fail even if the terminal output looked fine.

## Common failure modes

- **Float money**: totals like `0.30000000000000004` or `35.5` vs `35.50`
  formatting inconsistencies; summing cents-as-floats instead of integers/decimal.
- **Broken CSV quoting**: notes with commas or quotes shift columns because the
  export just joins with `,`.
- **Summary that doesn't reconcile**: category totals and grand total computed
  from different passes and disagreeing.
- **No input validation**: negative or non-numeric amounts recorded silently,
  poisoning the totals.
- **In-memory only**: same trap as CMVP-1 — nothing persists across runs.
