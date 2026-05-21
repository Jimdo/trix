# The attribute system

This is the mechanism you hook into to add new formatting (including the
colour feature in [05-color-feature-proposal.md](05-color-feature-proposal.md)).
Before touching it, read end to end — the seven stages form one feedback loop,
and a change in any one of them must be consistent with the rest.

## Block attributes vs text attributes

Two distinct mechanisms, same config shape.

| | Block attributes | Text attributes |
|---|---|---|
| Defined in | `src/trix/config/block_attributes.coffee` | `src/trix/config/text_attributes.coffee` |
| Stored on | `Block.attributes: string[]` | `Piece.attributes: Trix.Hash` |
| Can carry a value | No (name only) | Yes (e.g. `href: "https://…"`) |
| Scope | Whole block (paragraph / list item / heading …) | Character range within a block |
| Examples | `quote`, `heading1`, `bullet`, `alignRight`, `code` | `bold`, `italic`, `href`, `strike`, `frozen` |
| Tag output | Container element (`<blockquote>`, `<h1>`, …) | Inline wrapper (`<strong>`, `<em>`, `<a>`, `<span>`) |

A new colour attribute is a **text** attribute — it applies to a selection, not
to a whole paragraph.

## Supported config keys

### Text attribute keys (`src/trix/config/text_attributes.coffee`)

| Key | Meaning | Example |
|---|---|---|
| `tagName: string` | Wrap each piece in this tag. | `bold: {tagName: "strong"}` |
| `groupTagName: string` | Group adjacent pieces with the same value under one tag. HTML attributes come from the attribute value (`href: "…"` → `<a href="…">`). | `href: {groupTagName: "a"}` |
| `style: {property: value}` | Apply **static** inline styles to a wrapping `<span>` (or the `tagName` element if set). Values are literal, not the piece's attribute value. | `frozen: {style: {backgroundColor: "highlight"}}` |
| `styleProperty: string` | Apply the piece's attribute value as a **dynamic** inline style. | (not currently used upstream — this is exactly what the colour attribute needs) |
| `parser: (element) => value` | Recover the attribute from a DOM element when parsing HTML. Return a truthy value, or undefined. | `bold.parser` checks computed `fontWeight`. |
| `inheritable: boolean` | If true, the attribute is treated as "sticky" at the boundary between adjacent pieces — the toolbar shows it as active even when the cursor sits right after a styled run. See `document.coffee:585-588`. | `bold: {inheritable: true}` |

### Block attribute keys (`src/trix/config/block_attributes.coffee`)

| Key | Meaning |
|---|---|
| `tagName: string` | The wrapping block element (`<blockquote>`, `<h1>`, …). |
| `tagNames: string[]` | Multi-tag match; used with `test` for attributes like alignment that can apply to any block tag (`alignRight.tagNames: ["div", "p", "h1", "h2", "h3"]`). |
| `className: string` | Class to apply on the block element. |
| `parse: boolean` | If `false`, the parser never *produces* this attribute; it only exists as output (`default`, `bulletList`, `numberList` — you never ask for a "bulletList", you ask for a "bullet" and the list container is implied). |
| `nestable: boolean` | Block can nest inside itself (quotes, list items). |
| `terminal: boolean` | No further block attribute can nest inside this one. Code blocks and headings are terminal. |
| `breakOnReturn: boolean` | Return in this block exits the block rather than creating a new one of the same kind. Headings. |
| `inheritFromPreviousBlock: boolean` | When Return creates a new block, this attribute is copied. Used for alignments (`block_attributes.coffee:67-79`). Mechanism: `composition.coffee:538-542`. |
| `role: string` | Prevents multiple attributes with the same role co-existing on a block. `alignRight` and `alignCenter` both have `role: "alignment"`. |
| `listAttribute: string` | Names the container attribute a list item belongs to (`bullet.listAttribute: "bulletList"`). |
| `group: boolean` | If `false`, adjacent blocks with this attribute are **not** rendered in the same element. Headings and list items. |
| `test: (element) => boolean` | Additional DOM predicate during parsing. |
| `text: {plaintext: boolean}` | Tells `TextView` to treat this block's text as pre-formatted (no BR conversion). Used by code blocks. |

## The seven stages of round-trip

### 1. Declaration

Declare the attribute in the config. This is the only "new code" place for
most attributes.

```coffee
# src/trix/config/text_attributes.coffee:2-7
bold:
  tagName: "strong"
  inheritable: true
  parser: (element) ->
    style = window.getComputedStyle(element)
    style["fontWeight"] is "bold" or style["fontWeight"] >= 600
```

Once this entry exists, **everything else is automatic** because the rest of
the system iterates `Trix.config.textAttributes` at runtime:

- `getAllAttributeNames()` in `src/trix/core/helpers/config.coffee` returns
  every registered name.
- `HTMLParser.getTextAttributes` iterates the config
  (`html_parser.coffee:183-200`).
- `PieceView.createElement` iterates the piece's attributes
  (`piece_view.coffee:57-76`).

Runtime registration is possible too — `Trix.config.textAttributes.color = {...}`
before a `<trix-editor>` enters the DOM behaves identically to hard-coding it.

### 2. Toolbar wiring (optional)

A toolbar button is just an HTML element with `data-trix-attribute`:

```html
<!-- src/trix/config/toolbar.coffee:7 -->
<button type="button"
        class="trix-button trix-button--icon trix-button--icon-bold"
        data-trix-attribute="bold"
        data-trix-key="b"
        title="Bold" tabindex="-1">Bold</button>
```

A value-requiring attribute uses a dialog instead of direct toggle:

```html
<!-- src/trix/config/toolbar.coffee:10 -->
<button data-trix-attribute="href" data-trix-action="link" data-trix-key="k">…</button>
```

with a dialog (`src/trix/config/toolbar.coffee:30-38`):

```html
<div class="trix-dialog" data-trix-dialog="href" data-trix-dialog-attribute="href">
  <input type="url" name="href" data-trix-input>
  <input type="button" value="Link"   data-trix-method="setAttribute">
  <input type="button" value="Unlink" data-trix-method="removeAttribute">
</div>
```

For the colour feature the toolbar is bypassed entirely — the CMS provides
its own UI. No changes are needed to `config/toolbar.coffee`.

### 3. Activation

User flow: button click → toolbar delegate → editor controller → composition →
document.

```
ToolbarController.didClickAttributeButton        toolbar_controller.coffee:36
  └─> delegate.toolbarDidToggleAttribute(name)
EditorController.toolbarDidToggleAttribute       editor_controller.coffee:234-238
  ├─> recordFormattingUndoEntry()                editor_controller.coffee:363-366
  └─> composition.toggleCurrentAttribute(name)
Composition.toggleCurrentAttribute               composition.coffee:220-224
  └─> setCurrentAttribute(name, true) | removeCurrentAttribute(name)
Composition.setCurrentAttribute                  composition.coffee:252-258
  ├─> block path? setBlockAttribute
  └─> text path:
      setTextAttribute(name, value)
      currentAttributes[name] = value     # always cache, even for collapsed
      notifyDelegateOfCurrentAttributesChange()
Composition.setTextAttribute                     composition.coffee:260-268
  ├─> collapsed selection + name === "href" → insert link text
  ├─> collapsed selection + anything else   → (no document mutation; the cache above arms the attribute for the next typed character)
  └─> expanded selection → document.addAttributeAtRange(name, value, range)
```

Programmatic entry point for external callers (the CMS colour picker will use
this):

```
element.editor.activateAttribute(name, value = true)   # editor.coffee:82-83
  └─> composition.setCurrentAttribute(name, value)
```

and

```
element.editor.deactivateAttribute(name)               # editor.coffee:91-92
  └─> composition.removeCurrentAttribute(name)
```

Note: `activateAttribute` does **not** record an undo entry.
`toolbarDidToggleAttribute` does (via `recordFormattingUndoEntry`). External
callers that want undo support must call
`element.editor.recordUndoEntry("…", {context, consolidatable})` first.

### 4. Storage in the document

`Document.addAttributeAtRange` (`document.coffee:344-355`) walks every block
in the range; for text attributes it delegates to
`block.text.addAttributeAtRange` (`text.coffee:53-60`), which calls
`pieceList.transformObjectsInRange(range, fn)`
(`splittable_list.coffee:58-65`).

`transformObjectsInRange` is where the magic happens:

1. `splitObjectsAtRange(range)` splits pieces at the start and end boundaries
   via `string_piece.coffee:36-46`. A piece "hello" split at offset 2 returns
   `[<"he">, <"llo">]`, both carrying the original attributes.
2. Each piece within the range is replaced by
   `piece.copyWithAdditionalAttributes(attrs)` (`piece.coffee:19-20`), which
   merges the new attribute into the immutable `Trix.Hash`.
3. A new `Text` is built from the resulting list; `copyWithPieceList` calls
   `pieceList.consolidate()` (`text.coffee:26-27`), which re-merges adjacent
   pieces whose attribute hashes are now equal.

Attributes live on `Piece.attributes`, a `Trix.Hash`:

```coffee
# src/trix/models/piece.coffee:12-14
constructor: (value, attributes = {}) ->
  super
  @attributes = Trix.Hash.box(attributes)
```

The hash is persistent: `merge`, `remove`, `slice` return new hashes, so
pieces can share structure across document versions. `isEqualTo` on two
hashes is an array comparison of `toArray()` (`hash.coffee:48-49`).

### 5. Rendering (model → DOM)

`PieceView.createNodes` (`piece_view.coffee:18-28`) calls `createStringNodes`
(plain text nodes) and then wraps them in whatever `createElement` produces.

`PieceView.createElement` (`piece_view.coffee:54-76`) is the attribute-to-DOM
translator:

```coffee
createElement: ->
  styles = {}

  for key, value of @attributes when config = getTextConfig(key)
    if config.tagName
      pendingElement = makeElement(config.tagName)
      # ... nest into the innermost existing wrapper ...

    if config.styleProperty
      styles[config.styleProperty] = value

    if config.style
      styles[key] = value for key, value of config.style

  if Object.keys(styles).length
    element ?= makeElement("span")
    element.style[key] = value for key, value of styles
  element
```

Three routes, which combine:

- `tagName` → creates a wrapping element. Multiple `tagName` attributes on
  one piece produce nested wrappers.
- `styleProperty` → sets `element.style[prop] = pieceValue`. This is how the
  colour attribute will render.
- `style` → applies a **static** style object (the attribute value is
  ignored; only config-time values are used).

If **only** style routes fire, the wrapper defaults to `<span>`. If a
`tagName` exists, the style is applied to that element instead. For a piece
with `{bold: true, color: "#f00"}`, this produces `<strong style="color: rgb(255,0,0)">`.

`PieceView.createContainerElement` (`piece_view.coffee:78-92`) is separate —
it handles `groupTagName`. This is how multiple adjacent `href`-carrying
pieces are wrapped in a single `<a>`. Group wrappers carry HTML attributes
(from the attribute value passed to `makeElement`), not styles.

Grouping at all is decided by `piece.canBeGrouped` / `canBeGroupedWith`
(`piece.coffee:82-87`), which hard-codes `href`. Adjacent colour-only pieces
with the same colour will consolidate (step 4) rather than group — you'll get
a single piece with a single `<span>` wrapper, not multiple pieces grouped
together.

Block-level rendering is orthogonal: `BlockView` creates the containing
element from block attributes and then inserts a `TextView`, which delegates
each piece to a `PieceView`.

### 6. Serialization (document → HTML string)

`Trix.serializers["text/html"]` (`src/trix/config/serialization.coffee:20-44`):

```
1. Render document via Trix.DocumentView.render   → DOM fragment
2. Remove elements with [data-trix-serialize=false]
3. Remove attributes: contenteditable, data-trix-id, data-trix-store-key,
   data-trix-mutable, data-trix-placeholder, tabindex
4. For elements with data-trix-serialized-attributes, parse the JSON and
   apply those as real attributes (this is how attachments round-trip
   their bag of data).
5. Return innerHTML, stripped of <!--block--> comments
```

Note that the serializer **does not** filter `style` attributes — inline
styles survive into the output. `class` also survives (used for alignment
block attributes: `text-align-right`, `text-align-center`).

Hidden input synchronisation: `EditorController.updateInputElement`
(`editor_controller.coffee:340-343`) is called inside `notifyEditorElement`
on `change`, `attachment-add`, `attachment-edit`, `attachment-remove`; it
serialises the current `SerializableElement` and writes to
`element.inputElement.value`. Any code that reads the hidden input's value
(e.g. a form post, or the CMS reading saved content) gets the serialised HTML
with inline styles intact.

### 7. Deserialization (HTML → document)

`Document.fromHTML` → `Trix.HTMLParser.parse` → walks the sanitised HTML DOM.

First, `HTMLSanitizer` scrubs disallowed attributes. Its allow-list
(`html_sanitizer.coffee:4`) is:

```
style  href  src  width  height  class  target
```

Anything starting with `data-trix-` is also allowed
(`html_sanitizer.coffee:45-49`). Everything else (e.g. `onclick`, `style-xyz`)
is stripped on load. Elements with `data-trix-serialize="false"` and `<script>`
tags are removed entirely (`html_sanitizer.coffee:51-54`).

Then `HTMLParser.getTextAttributes` runs for each text node
(`html_parser.coffee:181-206`):

```coffee
for attribute, config of Trix.config.textAttributes
  if config.tagName and findClosestElementFromNode(element, matchingSelector: config.tagName, untilNode: @containerElement)
    attributes[attribute] = true

  else if config.parser
    if value = config.parser(element)
      # …guard against parsers picking up values that come from the block element itself
      unless attributeInheritedFromBlock
        attributes[attribute] = value

  else if config.styleProperty
    if value = element.style[config.styleProperty]
      attributes[attribute] = value
```

Three branches mirror the three rendering routes:

- `tagName` branch: if any ancestor element has that tag (up to the
  sanitiser container), the attribute fires.
- `parser` branch: the user-supplied function decides. This is the escape
  hatch for detecting attributes from computed styles, `href` values on
  `<a>` ancestors, etc. The inner loop at lines 189-194 guards against a
  parser matching a block-level ancestor (e.g. computed colour inherited
  from a parent) and wrongly applying it to the text.
- `styleProperty` branch: `element.style[prop]` is read literally. If you
  `styleProperty: "color"`, the parser reads `element.style.color` — which
  on most browsers is normalised to `rgb(r, g, b)` even if the source HTML
  said `#ff0000`. That's the round-trip format you'll see from the second
  save onwards.

Block attributes are recovered similarly by `getBlockAttributes`
(`html_parser.coffee:208-220`).

## Toolbar state sync

After any document or selection change, `Composition.updateCurrentAttributes`
(`composition.coffee:334-345`) runs:

1. Read the selection's range.
2. Compute the attributes common to every piece in the range via
   `document.getCommonAttributesAtRange`.
3. For any attribute that cannot be activated in the current context, mark
   it explicitly `false` (so the toolbar button is disabled).
4. If `currentAttributes` changed, notify the delegate.

`EditorController.compositionDidChangeCurrentAttributes`
(`editor_controller.coffee:51-54`) fires `trix-attributes-change` with the
full map and calls `toolbarController.updateAttributes`.

`ToolbarController.refreshAttributeButtons` (`toolbar_controller.coffee:81-89`)
reads the map and toggles `data-trix-active` on each
`[data-trix-attribute]` element.

The `inheritable` flag affects what "common at cursor" means for a **collapsed
selection** (`document.coffee:577-591`). When the cursor sits at position `p`,
the common attributes are those of the piece at `p` **plus** those of the piece
at `p-1` if they are inheritable. That's why typing right after bold text
continues to be bold without the user re-activating it — the toolbar says
"bold is active" even though the cursor is technically between two pieces.

## Custom events

Anything external that needs to know about attributes listens for
`trix-attributes-change`. The event has `event.attributes` mirroring
`Composition.currentAttributes` — every text-config key whose value is truthy
or explicitly `false`.

## One-line recipe

To register a new text attribute completely:

```coffee
Trix.config.textAttributes.myAttr =
  # one of the following rendering strategies:
  tagName: "…"               # wraps in a tag
  groupTagName: "…"          # adjacent pieces grouped under one tag with attrs
  style: { prop: "value" }   # static inline style
  styleProperty: "cssProp"   # dynamic inline style from the attribute value

  # optional:
  inheritable: true          # sticky at piece boundaries (toolbar + typing)
  parser: (el) -> …          # recover from HTML
```

That's all the code changes needed — everything else is driven by the
existing iteration over `Trix.config.textAttributes`.
