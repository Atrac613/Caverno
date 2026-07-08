# CMVP-2 · Word frequency counter

Difficulty: **Starter** · Core skill: pure text processing, deterministic
tie-breaking

A pure-logic fixture with no persistence and no I/O beyond reading input. Its
value is that "as intended" is fully deterministic: for a given input there is
exactly one correct top-N list, so partial credit is easy to spot and the model
cannot hide behind vague output.

## Brief

> Write a command-line tool that reads a text file and prints the most common
> words with their counts. I want the top 10 by default, and I should be able to
> ask for a different number. Punctuation and capitalization shouldn't split the
> same word into different entries.

## Scope

In scope:

- Read text from a file path argument (or stdin).
- Count words case-insensitively, ignoring surrounding punctuation.
- Print the top N (default 10) as `word count`, most frequent first.
- An optional argument/flag to change N.

Out of scope:

- Stemming, lemmatization, stop-word lists, language detection.
- Any persistence, network, or UI.

## Functional requirements

1. Tokenize on whitespace, then normalize each token: lowercase and strip
   leading/trailing punctuation. `Hello,` and `hello` count as the same word.
2. Empty tokens (produced by stripping punctuation-only strings) are dropped.
3. Output is sorted by count descending; ties are broken alphabetically so the
   output is deterministic.
4. N defaults to 10 and is configurable via an argument/flag; N larger than the
   vocabulary prints the whole vocabulary without error.
5. Empty input prints nothing (or a clear "no words" note) and exits 0.
6. Missing file argument prints usage and exits non-zero.

## Acceptance criteria

- [ ] `"The cat sat on THE mat. The cat."` yields `the 3`, `cat 2`, then the
      singletons `mat`, `on`, `sat` — case-folded and punctuation-stripped.
- [ ] Ties are ordered alphabetically (`mat`, `on`, `sat` above), giving the
      same output on every run.
- [ ] Requesting top 2 returns exactly `the 3` and `cat 2`.
- [ ] Requesting top 100 on that input returns all 5 distinct words, no crash.
- [ ] Empty input exits 0 with no spurious rows.
- [ ] Missing/unreadable file exits non-zero with a clear message.

## Suggested verification

```bash
printf 'The cat sat on THE mat. The cat.\n' > sample.txt
<run> sample.txt          # -> the 3 / cat 2 / mat 1 / on 1 / sat 1
<run> sample.txt 2        # -> the 3 / cat 2   (exact top-N cut)
<run> sample.txt 100      # -> all 5 words, no error
printf '' > empty.txt
<run> empty.txt; echo "exit=$?"   # -> no rows, exit 0
<run> ; echo "exit=$?"            # -> usage, exit non-zero
```

The tie-break criterion is the discriminator: run the same input twice and
confirm byte-identical output. Non-deterministic ordering (hash-map iteration
order) is a fail even if the counts are right.

## Common failure modes

- **Non-deterministic ties**: counts are correct but equal-count words come out
  in arbitrary map order, so "as intended" can't be pinned down.
- **Punctuation attached**: `cat.` and `cat` counted separately because only
  whitespace splitting was done.
- **Over-aggressive stripping**: internal punctuation (e.g. `don't`, `state-of`)
  mangled, or all non-letters removed mid-token, changing the vocabulary.
- **Off-by-one N**: top 2 returns 1 or 3 rows.
- **Crash on N > vocabulary**: slicing past the end throws instead of clamping.
