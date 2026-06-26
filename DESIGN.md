---
# Machine-readable design tokens. Mirror these in lib/core/theme/ as
# ThemeExtension classes (AppRadii, AppSpacing, AppSemanticColors). Dark is the
# default and primary mode; light values are provided so the tokens stay
# mode-complete (see "Colors").
name: Caverno
description: >-
  Dark-first, near-monochrome agentic coding client with a single indigo accent.
  Flat over boxed, tight density, modest corners. Taste reference: the Codex
  desktop app.
mode_default: dark

color:
  # Indigo / violet accent (the only saturated hue in the UI).
  accent:           "#6D6AF0"
  accent_hover:     "#5B57E8"
  accent_pressed:   "#4A46D6"
  on_accent:        "#FFFFFF"
  # Surfaces — stepped value, not borders, separate layers (dark).
  bg:               "#0E0E11"   # page canvas
  surface_1:        "#161619"   # sidebar, in-flow cards
  surface_2:        "#1D1D21"   # raised cards, inputs, panels
  surface_3:        "#26262B"   # popovers, menus, dialogs
  # Hairlines.
  border:           "#2A2A30"
  border_strong:    "#36363D"
  # Text hierarchy.
  text_primary:     "#ECECEE"
  text_secondary:   "#A2A2AC"
  text_muted:       "#6E6E78"
  # Semantic (muted, GitHub-like; reserved for state, never decoration).
  success:          "#3FB950"
  danger:           "#F85149"
  warning:          "#D29922"
  diff_added:       "#2EA04326"   # 15% green wash
  diff_removed:     "#F8514926"   # 15% red wash

typography:
  font_ui:   "Inter"
  font_mono: "JetBrains Mono"
  # size / weight / line-height — compact scale (Material defaults are looser).
  display: { size: 20, weight: 500, height: 1.3 }
  title:   { size: 16, weight: 500, height: 1.35 }
  body:    { size: 13, weight: 400, height: 1.5 }
  label:   { size: 12, weight: 500, height: 1.4 }
  caption: { size: 11, weight: 400, height: 1.4 }
  code:    { size: 12, weight: 400, height: 1.5, family: mono }

spacing:        # 4px base, compact density
  xxs: 2
  xs:  4
  sm:  6
  md:  8
  lg:  12
  xl:  16
  xxl: 24
  xxxl: 32

radius:
  xs: 4     # chips, code blocks, diff tiles
  sm: 6     # buttons, list rows, small controls
  md: 10    # cards, inputs, text fields
  lg: 14    # dialogs, bottom sheets

components:
  control_padding:   { h: 12, v: 8 }   # FilledButton / TextButton default
  page_gutter:       16
  drawer_row_padding: { h: 10, v: 7 }
  visual_density:    compact
  hairline_thickness: 0.5
---

# Caverno Design System

The visual contract for Caverno's Flutter UI. Read this before adding a screen,
dialog, sheet, button, or any styled widget. It exists so a contributor — human
or coding agent — produces UI that fits the system instead of inventing a new
look per widget.

The taste reference is the **Codex desktop app**: dark, near-monochrome, flat,
information-dense, modest corners, one accent. Caverno should feel like a
focused developer tool, not a consumer app.

## Overview

### Status: target vs. now

This document describes where the UI is **deliberately heading**. The current
code does not match it yet — label the gap honestly:

| Concern | Now (`main`) | Target |
| --- | --- | --- |
| Theme source | inline 14 lines in `lib/main.dart` (`ColorScheme.fromSeed(Colors.blue)`, dark-locked) | `lib/core/theme/` with `ThemeData` component themes + `ThemeExtension` tokens |
| Design tokens | none | `AppRadii`, `AppSpacing`, `AppSemanticColors` extensions |
| Hardcoded `Colors.*` | ~84 | 0 (tokens / `ColorScheme` only) |
| `EdgeInsets` literals | ~472 | reference `AppSpacing` |
| `BorderRadius.circular` | ~177, inconsistent | reference `AppRadii` (4 / 6 / 10 / 14) |
| Accent | stock `Colors.blue` | indigo / violet `#6D6AF0` |

Migration is incremental: land the theme + token foundation first, then move the
highest-offender widgets (`voice_mode_overlay.dart`, `chat_page.dart`,
`conversation_drawer.dart`) onto the tokens. Do not block a feature PR on a
full repo sweep.

### Principles

1. **Flat, not boxed.** No card-in-card, no border around a group that already
   has a background. Group with whitespace and one hairline (`AppDivider`),
   never nested rounded boxes.
2. **Tokens, not literals.** Reference `ColorScheme`, the `ThemeExtension`
   tokens, or a component theme. Never a raw `Colors.*`, `Color(0x..)`, ad-hoc
   `EdgeInsets`, or magic-number `BorderRadius`.
3. **One source per concern.** Style lives in the `ThemeData` component theme or
   a shared widget. Call sites pass intent (a variant), not padding/radius/color
   overrides.
4. **Restraint.** One accent-filled control per view; everything else is quiet
   (text / ghost / surface). Default to the lighter option — "too busy" is the
   common failure.
5. **Density adapts to a dev tool.** Compact spacing and `VisualDensity.compact`
   globally; trust the scale instead of padding things out.

## Colors

Dark is the default and the designed-for mode. Light values exist so the token
set is mode-complete, but dark is what we tune first.

The palette is **near-monochrome**: surfaces are stepped grays separated by
value (not borders), and a single indigo accent carries all brand/interactive
emphasis. Reserve `success` / `danger` / `warning` for genuine state — never for
decoration.

### Roles

- **Accent (`#6D6AF0`)** — primary buttons, focused inputs, active nav, links,
  the send action. The only saturated hue. `on_accent` is white.
- **Surfaces** — `bg` (page) < `surface_1` (sidebar, in-flow cards) <
  `surface_2` (raised cards, inputs, panels) < `surface_3` (popovers, menus,
  dialogs). Elevation reads as a lighter surface, not a heavy shadow.
- **Hairlines** — `border` for default dividers/edges; `border_strong` for
  hover/emphasis. 0.5px.
- **Text** — `text_primary` (body), `text_secondary` (supporting, timestamps),
  `text_muted` (placeholders, captions). Use color for muting, never `opacity`.
- **Diff** — `diff_added` / `diff_removed` washes behind `success` / `danger`
  text for code review surfaces.

### Flutter mapping

Map roles onto a dark `ColorScheme` so Material widgets inherit correctly, and
put everything Material's `ColorScheme` cannot express into
`AppSemanticColors extends ThemeExtension<AppSemanticColors>`:

```
ColorScheme.dark(
  primary: accent, onPrimary: onAccent,
  surface: surface_1, onSurface: textPrimary,
  surfaceContainerHighest: surface_3,
  error: danger, ...
)
```

`AppSemanticColors` carries: `surface2`, `surface3`, `hairline`,
`hairlineStrong`, `textSecondary`, `textMuted`, `success`, `warning`,
`diffAddedBg`, `diffRemovedBg`, `accentHover`, `accentPressed`. Implement
`copyWith` and `lerp` so theme animation interpolates cleanly.

Read them as `Theme.of(context).extension<AppSemanticColors>()!`.

## Typography

One UI sans (`Inter` via `google_fonts`) and one mono (`JetBrains Mono`) for
code, commit SHAs, branch names, diffs, and logs. The scale is tighter than
Material's defaults to suit a dense dev tool.

| Token | Size / weight | Use |
| --- | --- | --- |
| display | 20 / 500 | screen titles, dialog headers |
| title | 16 / 500 | section headers, card titles |
| body | 13 / 400 | default UI text, list rows |
| label | 12 / 500 | buttons, chips, field labels |
| caption | 11 / 400 | timestamps, hints, metadata |
| code | 12 / 400 mono | code, SHAs, branches, diffs |

Two weights only: 400 and 500. Avoid 600/700 — they read heavy against the dark
surfaces. Build the `TextTheme` once in `app_theme.dart`; widgets pull from
`Theme.of(context).textTheme`, never inline `TextStyle(fontSize: ..)`.

Copy is sentence case, verb-first, no terminal punctuation on labels/buttons.
Every user-facing string goes through `easy_localization` and updates **both**
`assets/translations/en.json` and `assets/translations/ja.json` — a string that
lands in one locale only is a regression.

## Layout

- **Spacing scale** (4px base): 2 / 4 / 6 / 8 / 12 / 16 / 24 / 32, exposed as
  `AppSpacing` (`xxs`…`xxxl`). All padding, gaps, and insets reference it. No
  bare `EdgeInsets.all(13)`.
- **Density:** set `visualDensity: VisualDensity.compact` on `ThemeData`.
- **Page gutter:** 16 horizontal. Don't hardcode per-screen page padding.
- **Drawer / list rows:** 10h × 7v padding, flat, flush-left, no per-row box.
- **Dividers:** prefer spacing; when a divider is genuinely needed it's one
  `AppDivider` (0.5px `hairline`), never a border ringing a section.

## Elevation & Depth

Flat-first. In dark mode, depth is communicated by **moving to a lighter
surface**, not by stacking shadows.

- In-flow cards: `surface_1` / `surface_2`, elevation 0, optional 0.5px hairline.
  No shadow.
- Floating overlays (dialog, menu, bottom sheet, popover): `surface_3` + a 0.5px
  `hairline` + a single soft shadow token. At most two floating layers at once;
  a third means a dialog, not popover-on-popover.
- Never card-in-card. Never a shadow on an in-flow tile.

## Shapes

Corners are **modest** — the most common past mistake was over-rounding
(Material's default `Dialog` radius is 28; that reads soft and consumer-y).

| Token | Radius | Applies to |
| --- | --- | --- |
| `radius.xs` | 4 | chips, code blocks, diff tiles, badges |
| `radius.sm` | 6 | buttons, list rows, small controls |
| `radius.md` | 10 | cards, text fields, inputs |
| `radius.lg` | 14 | dialogs, bottom sheets (top corners) |

Pills (`StadiumBorder`) are reserved for status dots and avatars only — never
buttons. Expose the scale as `AppRadii` and read
`Theme.of(context).extension<AppRadii>()!`.

## Components

Style each component **once** in a `ThemeData` component theme; for composite
patterns, wrap a small shared widget. Call sites choose a variant, not padding.

`ThemeData` component themes to define in `app_theme.dart`:

- `filledButtonTheme` — accent fill, `on_accent` text, `radius.sm`, padding
  `12h × 8v`, compact. The one primary action.
- `textButtonTheme` / `outlinedButtonTheme` — quiet secondary/tertiary. Text
  for "Cancel" / "Undo"; outlined (1px hairline, no fill) where a boundary helps.
- `inputDecorationTheme` — `filled` on `surface_2`, `radius.md`, 0.5px
  `hairline` border, focus border = accent.
- `cardTheme` — `surface_1`, elevation 0, `radius.md`, optional hairline.
- `dialogTheme` — `surface_3`, `radius.lg`, padding `16`.
- `bottomSheetTheme` — `surface_3`, top corners `radius.lg`.
- `appBarTheme` — `surface_1`, elevation 0, 0.5px bottom hairline.
- `listTileTheme` — dense, compact, `radius.sm` on hover/selection.
- `dividerTheme` — `hairline`, thickness 0.5.
- `menuTheme` / `popupMenuTheme` — `surface_3`, `radius.sm`.

Shared widgets to introduce (Caverno has no `lib/shared/`; place these in
`lib/core/theme/widgets/` or the owning feature):

- `AppButton` — primary / secondary / ghost / danger variants over the button
  themes; the single button entry point.
- `AppDialog`, `AppBottomSheet` — consistent radius, padding, and dismiss.
- `AppDrawerRow` — the flat sidebar/history row (icon + title + muted trailing
  timestamp), matching the Codex sidebar.
- `AppEmptyState`, `AppLoader`, `AppDivider`.

## Do's and Don'ts

**Do**

- Read color from `ColorScheme` or `AppSemanticColors`; spacing from
  `AppSpacing`; radius from `AppRadii`; text from `textTheme`.
- Style in the component theme or a shared widget; pass a variant at the call
  site.
- Keep one accent-filled control per view; everything else quiet.
- Use mono (`code` style) for SHAs, branches, paths, diffs, logs.
- Update `en.json` and `ja.json` together for every string.

**Don't**

- Hardcode `Colors.*` or `Color(0x..)` in a widget (≈84 to remove).
- Write ad-hoc `EdgeInsets` literals (≈472 to migrate) — use `AppSpacing`.
- Call `BorderRadius.circular(<magic>)` (≈177 to unify) — use `AppRadii`.
- Over-round: no 24–28px dialog corners; dialogs are `radius.lg` (14).
- Make pill buttons; pills are for status/avatars only.
- Override a component theme's padding / radius / color at the call site.
- Nest cards or ring a section with a border when whitespace + one hairline does
  the job.
- Mute text with `opacity` — use `text_secondary` / `text_muted`.

## Implementation pointers

- Tokens + theme live in `lib/core/theme/` (`app_theme.dart`, `app_tokens.dart`).
- Replace the inline theme in `lib/main.dart` with `theme: AppTheme.dark` (light
  kept mode-complete; `themeMode` stays dark for now).
- Caverno uses Riverpod — if theme mode becomes user-selectable later, drive it
  from a `Notifier`, not a global.
- Migrate offenders in priority order:
  `voice_mode_overlay.dart` → `chat_page.dart` → `conversation_drawer.dart` →
  `message_input.dart` → the rest.
