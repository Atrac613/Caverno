# CMVP-3 · Markdown table-of-contents generator

Difficulty: **Intermediate** · Core skill: line parsing, slugify, nesting,
code-fence skipping

The first fixture with genuinely tricky edge cases. Heading detection looks
trivial until fenced code blocks and `#`-in-code enter the picture, so it
separates models that parse structurally from ones that grep for `#`.

## Brief

> Write a tool that reads a Markdown file and generates a table of contents from
> its headings. Each entry should be a link to that heading, and the list should
> be indented to reflect heading levels. Don't pick up things that only look like
> headings because they're inside a code block.

## Scope

In scope:

- Detect ATX headings (`#` .. `######`) and their levels.
- Produce a nested Markdown bullet list, indented by heading depth.
- Each entry is a link `- [Heading text](#slug)` using GitHub-style anchor
  slugs.
- Ignore `#` lines inside fenced code blocks (``` ``` ``` ``` or `~~~`).

Out of scope:

- Setext headings (underline style), HTML headings.
- Rewriting the document / inserting the TOC in place (print it is enough).
- Configurable min/max heading level (a fixed range is fine).

## Functional requirements

1. A heading is a line beginning with 1–6 `#` characters followed by a space;
   the level is the count of `#`.
2. Lines inside fenced code blocks are never headings, even if they start with
   `#`. Track fence open/close with ``` ``` ``` ``` and `~~~`.
3. Slug rules (GitHub-flavored): lowercase, spaces to `-`, drop characters that
   are not alphanumeric/`-`/space. Duplicate slugs get `-1`, `-2`, ... suffixes
   in document order.
4. Indentation reflects depth: the shallowest heading present sits at indent 0,
   and each deeper level adds one indent step (two spaces).
5. A document with no headings produces empty output and exits 0.

## Acceptance criteria

- [ ] Given `# Title`, `## Setup`, `## Usage`, `### Flags`, output nests `Setup`
      and `Usage` one level under `Title`, and `Flags` one level under `Usage`.
- [ ] Links use correct slugs: `## API Reference` → `- [API Reference](#api-reference)`.
- [ ] A `#`-prefixed line inside a ``` ``` ``` fenced block is **not** in the
      TOC.
- [ ] Two headings named `Notes` produce anchors `#notes` and `#notes-1`.
- [ ] A file with no headings produces no output and exits 0.
- [ ] `####### Seven hashes` (7 `#`) is not treated as a heading (only 1–6).

## Suggested verification

Feed a document that combines the traps (the inner ` ``` ` pair is a fenced
code block *inside* the sample document):

````markdown
# Title
## Setup
Some prose.
```
# not a heading, this is code
```
## Notes
### Detail
## Notes
````

Expected TOC (indent = two spaces per level below the shallowest heading):

```markdown
- [Title](#title)
  - [Setup](#setup)
  - [Notes](#notes)
    - [Detail](#detail)
  - [Notes](#notes-1)
```

Check three things specifically: the in-code `#` line is absent, the duplicate
`Notes` disambiguates to `#notes-1`, and `Detail` is indented under the first
`Notes`.

## Common failure modes

- **Fence blindness**: `#` lines inside code blocks leak into the TOC — the most
  common structural miss.
- **Naive slugs**: keeping punctuation or not lowercasing, so anchors don't match
  what GitHub would generate.
- **No duplicate handling**: both `Notes` link to `#notes`, so the second link is
  dead.
- **Wrong indentation base**: assuming the document starts at `#` (level 1); a
  doc whose shallowest heading is `##` should still start at indent 0.
- **`#`-count off-by-one**: `#### ` (4) mislevelled, or 7+ hashes accepted as a
  level-6 heading.
