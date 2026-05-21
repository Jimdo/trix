# Feature proposal: text colour attribute driven by an external CMS

## Goal

Let a user select a portion of text in the Trix editor and apply an arbitrary
colour to it. The colour picker UI lives in the host CMS, not in the Trix
toolbar. The editor must:

1. Accept a colour value from outside and apply it to the current selection.
2. Round-trip the colour through HTML (serialise, reload, re-edit).
3. Tell the CMS which colour is currently at the cursor, so the CMS's picker
   can reflect state.
4. Support undo / redo.
5. Coexist with other attributes (bold, italic, link, …) on the same text.

## TL;DR

Adding the feature is **roughly 6 lines of CoffeeScript** plus CMS-side glue.
Register a new text attribute with `styleProperty: "color"`, drive it via the
existing `element.editor.activateAttribute` / `deactivateAttribute` API, and
listen to `trix-selection-change` / `trix-attributes-change` from the CMS.

The system's existing round-trip (see
[04-attribute-system.md](04-attribute-system.md)) already covers everything
else: storage, rendering, serialisation, parsing, toolbar sync.

## Design

### The editor change

Extend `src/trix/config/text_attributes.coffee` with a `color` entry:

```coffee
# src/trix/config/text_attributes.coffee (proposed addition after `frozen:`)
color:
  styleProperty: "color"
  inheritable: true
  parser: (element) ->
    return if element is element.ownerDocument?.body
    value = element.style.color
    value if value? and value isnt ""
```

That's the entire source change. Six lines (plus a comment). Everything else
is driven by iteration over `Trix.config.textAttributes` in the existing
pipeline.

Naming: `color` is the CSS property and the most obvious API name. If the
intent is to anticipate future additions (background colour, border colour),
consider `foregroundColor` / `textColor` instead — but I would only do that
if the richer set is actually planned, per the "don't design for hypothetical
future" principle. This proposal uses `color`.

### Why this works, stage by stage

Referencing the 7 stages from
[04-attribute-system.md § The seven stages of round-trip](04-attribute-system.md#the-seven-stages-of-round-trip).

1. **Declaration.** The new entry exists. `getAllAttributeNames()`
   (`src/trix/core/helpers/config.coffee`) now includes `color`.

2. **Toolbar wiring.** Skipped by design — the CMS owns the UI.

3. **Activation.** When the CMS calls
   `element.editor.activateAttribute("color", "#ff0000")`
   (`editor.coffee:82-83`):
   - Expanded selection: `setTextAttribute` at `composition.coffee:267-268`
     dispatches to `document.addAttributeAtRange("color", "#ff0000", range)`.
   - Collapsed selection: `setTextAttribute` falls through (lines 263-266
     special-case only `href`), but `setCurrentAttribute` at line 257 still
     sets `@currentAttributes.color = "#ff0000"`. The next typed character
     will pick this up via `getCurrentTextAttributes`
     (`composition.coffee:350-353`) → `Text.textForStringWithAttributes`.
     This is the correct behaviour.

4. **Storage.** `Piece.copyWithAdditionalAttributes` (`piece.coffee:19-20`)
   merges `{color: "#ff0000"}` into the piece's `Trix.Hash`. Adjacent pieces
   with identical attribute hashes consolidate automatically via
   `pieceList.consolidate()` (invoked from `text.copyWithPieceList`).

5. **Rendering.** `PieceView.createElement` (`piece_view.coffee:67-68`):

   ```coffee
   if config.styleProperty
     styles[config.styleProperty] = value
   ```

   For `{color: "#ff0000"}`, `styles.color = "#ff0000"`. Lines 73-75 then
   apply the style to either the innermost `tagName` element (if other
   attributes like `bold` created one) or a fresh `<span>`. Output DOM:

   - `{color: "#ff0000"}` only → `<span style="color: #ff0000;">text</span>`
   - `{color: "#ff0000", bold: true}` → `<strong style="color: #ff0000;">text</strong>`
   - `{color: "#ff0000", href: "u"}` → `<a href="u"><span style="color: #ff0000;">text</span></a>`
     (the group `<a>` comes from `groupTagName`, handled separately in
     `createContainerElement`).

6. **Serialisation.** `style` is in the default sanitiser allow-list
   (`html_sanitizer.coffee:4`) and is **not** in the unserialisable attribute
   list (`serialization.coffee:2`). The `<span style="color: …">` survives
   `Trix.serializers["text/html"]` untouched.

7. **Deserialisation.** `HTMLParser.getTextAttributes`
   (`html_parser.coffee:197-199`):

   ```coffee
   else if config.styleProperty
     if value = element.style[config.styleProperty]
       attributes[attribute] = value
   ```

   reads `element.style.color` on any ancestor span and reapplies. The
   `parser` override above is strictly unnecessary (the `styleProperty`
   branch already handles it), but providing an explicit parser makes the
   behaviour testable and lets us filter out the document body's computed
   colour if the parser ever walks that far. If `styleProperty` alone is
   sufficient in practice, drop the `parser` key.

### Toolbar state sync for the CMS

The CMS needs two pieces of information from the editor:

- **When the cursor / selection changes**, so the CMS knows whether to show
  its colour picker and where.
- **What colour is currently active**, so the picker can highlight the right
  swatch.

Both come from existing events:

- `trix-selection-change` fires whenever the selection moves. Inside the
  handler the CMS calls `element.editor.getSelectedRange()` and
  `element.editor.getClientRectAtPosition(pos)` to position its UI.
- `trix-attributes-change` fires whenever `Composition.currentAttributes`
  changes. `event.attributes.color` will be the current colour value (a
  string like `rgb(255, 0, 0)`) or `undefined`.

### Integration contract (CMS side)

```js
const element = document.querySelector("trix-editor")

// Keep the CMS picker's state in sync.
element.addEventListener("trix-attributes-change", (event) => {
  const color = event.attributes.color // string | undefined
  cms.colorPicker.setValue(color)
})

// Show/position the picker when the user has a selection.
element.addEventListener("trix-selection-change", () => {
  const [start, end] = element.editor.getSelectedRange()
  if (start === end) {
    cms.colorPicker.hide()
  } else {
    const rect = element.editor.getClientRectAtPosition(start)
    cms.colorPicker.showAt(rect)
  }
})

// Apply or remove a colour on user action in the CMS UI.
cms.colorPicker.onPick = (hex) => {
  element.editor.recordUndoEntry("Color")              // so Ctrl+Z reverses this
  element.editor.activateAttribute("color", hex)
}

cms.colorPicker.onClear = () => {
  element.editor.recordUndoEntry("Clear Color")
  element.editor.deactivateAttribute("color")
}
```

The `recordUndoEntry` calls are important — see Edge cases below.

## Edge cases and things to watch

### Undo / redo

The toolbar path records a "Formatting" undo entry in
`EditorController.toolbarDidToggleAttribute` before calling into the
composition (`editor_controller.coffee:234-238` →
`recordFormattingUndoEntry` at 363-366). The public `activateAttribute`
API does **not** record an undo entry.

Mitigation: the CMS must call
`element.editor.recordUndoEntry("Color", {consolidatable: true})` before
`activateAttribute` to get a single undo step per pick, with consolidation
so rapid colour changes coalesce (matches `Trix.config.undoInterval`, default
5000ms).

Alternatively, introduce a dedicated high-level API
(e.g. `editor.applyAttribute(name, value)`) that records undo internally.
That's a larger change and would need upstream API review — skip it for v1.

### Colour value normalisation

Browsers serialise inline `color` CSS to `rgb(r, g, b)` (or `rgba(...)` for
transparency). Even if the CMS passes `#ff0000`,
`element.style.color` after assignment reads back as `"rgb(255, 0, 0)"`.
After one serialise/parse cycle, the stored HTML uses `rgb(...)`.

Implication: the CMS picker must normalise values for equality checks.
Convert both the selected swatch and the incoming `event.attributes.color`
to a common format (e.g. hex, or the canonical `rgb(r, g, b)` form) before
comparing.

### Collapsed selection semantics

With nothing selected, `activateAttribute("color", "#f00")` arms
`currentAttributes.color = "#f00"` but does not mutate the document. The
next typed character picks the colour up. This matches how bold works when
you click "B" with the cursor between two words.

If the CMS prefers "do nothing on collapsed selection", it should guard:

```js
const [start, end] = element.editor.getSelectedRange()
if (start === end) return
element.editor.activateAttribute("color", hex)
```

### Grouping of adjacent coloured runs

Two adjacent pieces with the same `color` **and** identical other attributes
will consolidate into one piece at `text.copyWithPieceList`
(`text.coffee:26-27`) — rendered output is one `<span>`.

Two adjacent pieces with the same `color` but different other attributes
(one bold, one not) will **not** consolidate; rendered output is two
elements (`<strong style="color:..."><span style="color:..."></span></strong>`,
in whatever order attributes appear on each piece). This is cosmetic — the
visual result is identical — but the HTML is not minimal.

If minimal HTML matters, a future enhancement would be to teach
`PieceView.createContainerElement` about a `groupStyleProperty` key that
emits a grouping `<span>` with the style applied, analogous to how
`groupTagName` works for `<a>`. **This is out of scope for v1.**

### Code blocks

Code blocks have `text: { plaintext: true }` in the block attribute config
(`block_attributes.coffee:45-46`). `PieceView.createStringNodes` short-circuits
to a bare text node in plaintext mode (`piece_view.coffee:40-41`) — it skips
the `<br>` conversion. However, `createNodes` at `piece_view.coffee:18-28`
**still** wraps those text nodes in whatever `createElement` returns, so
`<pre><span style="color: …">code</span></pre>` renders correctly. Colour
works in code blocks.

### Plain-text tools paste

`trix-before-paste` and `trix-paste` fire for pasted HTML. If a user pastes
text that already has inline colour styles, `HTMLParser.getTextAttributes`
will recover them via the `styleProperty` branch. Whether that's desirable
depends on product intent — if the CMS wants to strip colour from pasted
content, listen for `trix-before-paste`, scrub `style="color"` from
`paste.html` before Trix consumes it (or call `preventDefault()` and drive
insertion manually via `editor.insertString(paste.string)`).

### Alignment vs colour

Alignment block attributes (`alignRight`, `alignCenter`) use
`className`-based rendering, not inline styles. They coexist with a text
`color` without interference — the `<p class="text-align-right">` contains
`<span style="color: …">…</span>`.

### The `frozen` attribute

`frozen` in `text_attributes.coffee:31-32` uses `style: { backgroundColor:
"highlight" }` — a static style applied during dialog interactions. It
does not compete with `color` (different CSS property, different
trigger). If the CMS also wants to offer background colour, register a
second attribute `backgroundColor` with `styleProperty: "backgroundColor"`.

### Security

The `color` attribute value is written directly to `element.style[prop]`.
Modern browsers refuse to set invalid CSS values — strings like
`"red; background: url(…)"` are rejected and `element.style.color` stays
empty. But do not rely on this for untrusted input. The CMS should validate
colour values client-side (restrict to `#[0-9a-f]{3,8}` or a known palette)
before calling `activateAttribute`.

## Proposed changes — concrete list

### Required

1. `src/trix/config/text_attributes.coffee` — add the `color` entry after the
   existing `frozen` key. Six lines.

### Optional but recommended

2. `test/src/system/text_formatting_test.coffee` — add a test that:
   - Types text, selects it, calls
     `getEditor().activateAttribute("color", "red")`, asserts the piece
     attribute.
   - Saves the HTML, reloads, asserts the colour survives.
   Existing tests like `test "applying attributes to text"` are the template.

3. `test/src/unit/html_parser_test.coffee` — add a case that parses
   `<span style="color: rgb(255, 0, 0)">x</span>` and asserts the resulting
   piece's `color` attribute is set.

### Not required

- No new public API. `activateAttribute` / `deactivateAttribute` /
  `attributeIsActive` / the `trix-attributes-change` event already cover
  the CMS's needs.
- No change to toolbar, sanitiser, serializer, or any rendering code —
  the existing `styleProperty` branch is already wired.
- No change to `dist/*.js` source — this will be regenerated by
  `bin/blade build` before publish.

## Rollout

1. Apply the `text_attributes.coffee` change on a feature branch.
2. Write the two tests. Run `bin/blade`.
3. Run `bin/blade build` to regenerate `dist/`.
4. Publish a pre-release version of `@jimdo/trix` (e.g. `0.13.0-color.0`).
5. Wire up the CMS side against the pre-release.
6. When the CMS team is happy, bump to `0.13.0` and publish.

## What this proposal deliberately does not do

- No background colour support. That's a separate attribute; defer until
  requested.
- No predefined palette inside Trix. The CMS picker controls the palette.
- No invariant that a block has exactly one colour — Trix represents colour
  per-piece, so a selection can contain multiple colours. The `event.attributes.color`
  value will be `undefined` when the selection spans pieces with different
  colours (because `getCommonAttributesAtRange` only returns attributes
  common to **all** pieces).
- No migration of existing stored content. Old documents have no `color`
  attribute and render with the default text colour. No action needed.
- No changes to undo behaviour beyond requiring the CMS to call
  `recordUndoEntry`. A built-in undo wrapper for `activateAttribute` is a
  reasonable follow-up but not necessary for v1.
