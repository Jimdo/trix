# Overview

## What Trix is

Trix is a WYSIWYG rich-text editor originally written by Basecamp. Its central
design decision is to **avoid `document.execCommand` entirely** and treat the
browser's `contenteditable` behaviour as an I/O device:

1. Keystrokes, paste, and drop events are observed.
2. Events are translated into operations on an in-memory **document model**.
3. The model is re-rendered to the DOM; the DOM is never the source of truth.

This makes behaviour reproducible across browsers — every browser quirk lives on
the input side; the document model is a pure data structure.

## Fork history

This repository is a fork of `basecamp/trix`, published as `@jimdo/trix` on the
private Jimdo npm registry (`package.json:2`, `.npmrc`). Per the root
`README.md`, the fork was created because Trix was, at the time, the only
WYSIWYG editor with acceptable behaviour on Android GBoard. The fork adds
Jimdo-specific tweaks on top of upstream.

Recent Jimdo changes visible in `git log` include:
- Alignment block attributes (`alignRight`, `alignCenter`) added via
  `inheritFromPreviousBlock` + `role: "alignment"`
  (`src/trix/config/block_attributes.coffee:67-79`).
- List-delete semantics (`11750a9a fix(lists): change behavior of delete into lists`).
- Expanded `createContainerElement` so an `<a>` tag captures both `href` and
  `target` attributes simultaneously (`src/trix/views/piece_view.coffee:78-92`).
- Publish workflow to the Jimdo npm registry (README, `.npmrc`).

The last upstream-style release bump is `0.12.0` (`package.json:3`). Upstream
Trix has since moved to v2.x with a different toolchain — those changes have
**not** been ported here.

## Tech stack

| Area | Choice |
|---|---|
| Language | CoffeeScript 1.9.1 (`Gemfile:6`) |
| Styling | Sass (`Gemfile:9`) |
| Asset pipeline | Sprockets 3.6.0 (`Gemfile:4`; pinned because 3.7+ strips banners) |
| Test runner | Blade 0.7.x (`Gemfile:13`), with SauceLabs for cross-browser (`Gemfile:14`) |
| Minifier | Uglifier (`Gemfile:10`) |
| SVG optimization | svgo via `sprockets-svgo` (`Gemfile:5`) and the npm `svgo` devDep (`package.json:24`) |
| Runner | Rack + Blade Rack adapter for dev (`config.ru`) |
| CI | Travis (`.travis.yml`) |
| Custom elements | Native `<trix-editor>` / `<trix-toolbar>` with a v0 polyfill fallback (`polyfills/custom-elements-v0-fallback.js.erb`) |

The toolchain is Ruby-centric. There is no webpack, no rollup, no tsc, no
babel, no jest. The only node dependency is `svgo`. Everything happens through
Sprockets compiling CoffeeScript/Sass/ERB sources into a single JS bundle.

## Output artifacts

`bin/blade build` produces three files in `dist/`:

| File | Contents |
|---|---|
| `dist/trix.js` | Full bundle: Trix + polyfills (custom elements v0, Set, etc.). This is what most consumers use. |
| `dist/trix-core.js` | Trix without polyfills. Use if you already ship polyfills yourself. |
| `dist/trix.css` | Default toolbar styles and `.trix-content` stored-content styles. |

`dist/` is checked into the repo and updated at release time by
`bin/release` (`bin/release:31, 131`).

## Entry points

- `assets/trix.coffee` → includes polyfills, then `src/trix/index.coffee.erb`.
- `assets/trix-core.coffee` → same, minus polyfills.
- `src/trix/index.coffee.erb` → the real source root: imports `core`,
  `config`, and the two custom elements.
- `src/trix/elements/trix_editor_element.coffee:8` → registers the
  `<trix-editor>` custom element.
- `src/trix/elements/trix_toolbar_element.coffee` → registers the
  `<trix-toolbar>` custom element.

## Target browsers

Per `.blade.yml`, the test matrix includes Chrome, Firefox, Safari, Edge 16,
IE 11, iPhone (iOS 9.3–11.2), Android 4.4–6.0. A real port today would drop
IE 11 and old iOS/Android, but the current code still has polyfills and
branches for them — do not remove casually.

## Age / risk note

The repo has been untouched for years. Before making any change, expect:

- Ruby 2.x era dependencies. The pinned Sprockets (3.6.0) and coffee-script
  (1.9.1) need rbenv + an old Ruby.
- Gemfile.lock may need regeneration against a modern bundler, but the
  **versions must not float** — the Sprockets pin is load-bearing.
- `bin/release` assumes `github.user` and `github.token` in global git
  config and an old `github_api` gem; for the Jimdo publish flow, only
  steps 1–4 and the `npm publish` tail matter (see
  [02-build-and-test.md](02-build-and-test.md)).
