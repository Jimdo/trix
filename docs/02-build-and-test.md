# Build and test

## Prerequisites

- Ruby. `.ruby-version` pins to `2.3.4`. That matches the Gemfile's 2.x-era
  gems. Use rbenv, rvm, or asdf; `bin/setup` calls `rbenv install
  --skip-existing` if rbenv is on `PATH` (`bin/setup:39-41`).
- Bundler.
- Node + npm (only needed because the `svgo` binary is a dev dependency).
- Homebrew on macOS makes `bin/setup` smoother (it will brew-install missing
  ruby/npm).

## First-time setup

```
bin/setup
```

This script (`bin/setup:1-72`):

1. Ensures Ruby is installed (uses rbenv if present).
2. Installs bundler if missing.
3. Runs `bundle install`.
4. Runs `npm install`.
5. If Pow is installed, symlinks the app at `http://trix.dev`.

Pass `-v` to see the full output (`bin/setup:11`).

## Building `dist/`

```
bin/blade build
```

This invokes Blade's build task which reads `.blade.yml` and compiles:

- `assets/trix.coffee` → `dist/trix.js`
- `assets/trix-core.coffee` → `dist/trix-core.js`
- `assets/trix.scss` → `dist/trix.css`

The logical paths and output directory are declared in `.blade.yml:11-16`:

```yaml
build:
  logical_paths:
    - trix.js
    - trix-core.js
    - trix.css
  path: dist
  js_compressor: uglifier
```

The pinned Sprockets version (3.6.0, `Gemfile:4`) matters — 3.7+ strips the
copyright banner comments that are prepended to the bundle.

## Running locally

```
bin/rackup
```

The Rack app is defined in `config.ru`:

- `/` serves the live-compiled Sprockets environment.
- `/test` serves the Blade test harness.
- `/attachments` is a tiny content-addressed blob store that accepts POSTs
  (writes to `tmp/attachments/{md5}`) and serves back on GET (`config.ru:10-29`).

Visit `http://localhost:9292/` to see `assets/index.html` with a working
`<trix-editor>`.

## Tests

Tests are browser-driven via Blade. Two trees:

- `test/src/unit/` — pure model tests (document, text, block, piece,
  html_parser, serialization, composition, mutation_observer, location_mapper).
- `test/src/system/` — black-box tests that drive the `<trix-editor>` custom
  element (text_formatting, block_formatting, list_formatting, undo, pasting,
  basic_input, composition_input, cursor_movement, attachment, etc.).

Run locally:

```
bin/blade
```

The CI entrypoint is `bin/ci`, invoked by `.travis.yml:3` via `travis_wait`
(`.travis.yml:3`). `bin/ci` routes between Basecamp's SauceLabs credentials and
a dev account depending on the repo slug (`bin/ci:4-20`).

## Publishing

Publishing from this fork is to the Jimdo private npm registry, not to the
public one. From `README.md`:

1. Add an npm token with publish rights to `.npmrc`.
2. `npm publish --dry-run` to verify.
3. `npm publish`.

`package.json:6` restricts the published payload to `dist/*.css` and
`dist/*.js` — that means `dist/` **must be up to date before publishing**, and
should be a committed build artifact.

`bin/release` is the upstream Basecamp release script and does more than
Jimdo needs (it creates GitHub releases, uploads assets, updates copyright
years). For Jimdo-only publishing, the README's three steps are what the team
actually runs.

## Known friction points

- **Old gems**: `github_api ~> 0.13.1` and `aws-sdk` may not install cleanly on
  current Ruby versions. For the Jimdo npm publish path they are not needed.
- **SauceLabs credentials** are embedded base64-encoded in `bin/ci:5-7`. These
  are Basecamp's, not Jimdo's; they will not work for forks.
- **v0 Custom Elements polyfill** (`polyfills/vendor/`) is shipped and needed
  for older Safari / older Chromium. Removing it breaks IE 11 and Safari 9.
- **No TypeScript, no ESLint, no Prettier.** There is no linter configured;
  rely on test coverage.
