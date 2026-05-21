# Architecture

## Guiding principle

Trix treats `contenteditable` as an I/O device. The DOM is **not** the source
of truth; a pure, immutable document model is. Every user action is translated
into a model mutation; the DOM is then re-rendered from the new model.

This inverts how naïve WYSIWYG editors work (mutate the DOM via `execCommand`,
then try to make sense of the result). The cost is a larger codebase; the
benefit is that behaviour is deterministic and testable.

## Data flow, at a glance

User interaction flows through four layers:

```
        DOM event
           |
           v
  +-----------------+
  | InputController | (src/trix/controllers/input_controller.coffee)
  +-----------------+
           |
           v (responder protocol)
  +-----------------+
  |   Composition   | (src/trix/models/composition.coffee)
  +-----------------+
           |
           | mutates (immutable copies of) ...
           v
  +-----------------+
  |    Document     | (src/trix/models/document.coffee)
  +-----------------+
           |
           | rendered by ...
           v
  +-----------------+
  | DocumentView    | (src/trix/views/document_view.coffee)
  +-----------------+
           |
           v
         DOM
```

`EditorController` (`src/trix/controllers/editor_controller.coffee`) is the
conductor: it owns every sub-controller and every model, acts as the
delegate for all of them, and re-fires user-facing custom events on the
`<trix-editor>` element.

## Layer 1 — Custom elements (entry points)

### `<trix-editor>`

Defined in `src/trix/elements/trix_editor_element.coffee:8` via
`Trix.registerElement "trix-editor"`.

Lifecycle (`src/trix/elements/trix_editor_element.coffee:163-177`):

- `initialize`: sets `contenteditable=""` and `role="textbox"`.
- `connect`: creates `new Trix.EditorController(editorElement: this, html: @value)`
  and registers the selection manager. Fires `trix-initialize` via
  `requestAnimationFrame`.
- `disconnect`: unregisters selection manager and form-reset listener.

Properties exposed on the element (`src/trix/elements/trix_editor_element.coffee:108-150`):

- `element.trixId` — unique id, auto-assigned.
- `element.toolbarElement` — the `<trix-toolbar>`; auto-created if not in DOM.
- `element.inputElement` — the hidden `<input>` mirror for form submission;
  auto-created.
- `element.editor` — the `Trix.Editor` instance; this is the public API.
- `element.value` — getter reads from the hidden input; setter calls
  `editor.loadHTML()`.

### `<trix-toolbar>`

Defined in `src/trix/elements/trix_toolbar_element.coffee`. Its only job is to
render the default toolbar HTML from `Trix.config.toolbar.getDefaultHTML()` if
the element is empty when connected.

## Layer 2 — Core primitives (`src/trix/core/`)

- `basic_object.coffee` — `Trix.BasicObject`. Has `@proxyMethod(expression)`
  for declarative method proxying (e.g. `@proxyMethod "getDialog().open"`).
- `object.coffee` — `Trix.Object extends BasicObject`. Adds `@id`,
  `hasSameConstructorAs`, `isEqualTo`, `inspect`, `toJSONString`,
  `getCacheKey`.
- `collections/hash.coffee` — `Trix.Hash`, a persistent immutable hash used to
  store `Piece.attributes`. `merge`, `remove`, `slice`, `getKeysCommonToHash`
  all return new hashes. `Hash.box(obj)` wraps a plain object.
- `collections/object_group.coffee` — `Trix.ObjectGroup`, groups adjacent
  objects that agree on a "canBeGrouped" predicate. Used to render adjacent
  `href` pieces under a single `<a>` tag and to render nested lists/quotes as
  trees.
- `collections/object_map.coffee`, `element_store.coffee` — caches used by
  views.
- `helpers/dom.coffee` — DOM helpers: `makeElement`, `findClosestElementFromNode`,
  `findInnerElement`, `triggerEvent`, `handleEvent`, `walkTree`, `tagName`.
- `helpers/config.coffee` — cached accessors over `Trix.config`:
  `getTextConfig(name)`, `getBlockConfig(name)`, `getAllAttributeNames()`,
  `getBlockAttributeNames()`, `getTextAttributeNames()`,
  `getListAttributeNames()`.
- `utilities/operation.coffee` — `Trix.Operation`, base for async work. Has a
  `getPromise()` that auto-wraps the imperative `perform(callback)` pattern.

## Layer 3 — Models (`src/trix/models/`)

The model layer is **immutable**. Every mutating method returns a new instance.
This is how undo works: snapshots are just saved model references.

### Document hierarchy

```
Document
  blockList: SplittableList<Block>

Block
  text: Text
  attributes: string[]         # block-level (e.g. ["quote", "bullet"])

Text
  pieceList: SplittableList<Piece>

Piece (abstract)
  attributes: Trix.Hash<string, any>   # text-level (e.g. {bold: true, href: "..."})
  +-- StringPiece
  |     string: string
  |     length: number
  +-- AttachmentPiece
        attachment: Attachment
        length: 1
```

Key files:

- `document.coffee` — `Trix.Document`. Range mutations like
  `insertTextAtRange`, `removeTextAtRange`, `addAttributeAtRange`,
  `applyBlockAttributeAtRange`. Coordinate translation via
  `locationRangeFromRange` / `rangeFromLocationRange`.
- `block.coffee` — `Trix.Block`. Block attributes stored as an ordered array
  (e.g. `["quote", "bullet"]`); `getLastAttribute`, `getAttributeLevel`,
  `getNestingLevel` drive list/quote nesting logic.
- `text.coffee` — `Trix.Text`. Piece-level attribute operations
  (`addAttributesAtRange`, `removeAttributeAtRange`,
  `getCommonAttributesAtRange`).
- `piece.coffee` — `Trix.Piece`. Abstract; holds `@attributes` as a
  `Trix.Hash`. Registers subclass types via `@registerType`
  (`src/trix/models/piece.coffee:4-6`).
- `string_piece.coffee` — `Trix.StringPiece`. Implements `splitAtOffset`,
  `canBeConsolidatedWith` (true when adjacent pieces share attributes).
- `attachment_piece.coffee` — `Trix.AttachmentPiece`. Length is always 1.
- `splittable_list.coffee` — `Trix.SplittableList`. The collection that holds
  pieces or blocks. Provides `splitObjectAtPosition`,
  `transformObjectsInRange`, `consolidate`.

### Composition — the mutator facade

`src/trix/models/composition.coffee` is the thing controllers talk to. It
holds `@document`, a `@currentAttributes` cache (the attribute set active at
the cursor), a `@revision` counter, and exposes high-level operations:

- Text insertion: `insertText`, `insertString`, `insertDocument`,
  `insertHTML`, `insertBlockBreak`, `insertLineBreak`, `insertFile`,
  `insertAttachment`.
- Deletion: `deleteInDirection` (`composition.coffee:128-181`), with
  special cases for deleting into block-attribute boundaries and list
  decrements.
- Attributes: `setCurrentAttribute`, `toggleCurrentAttribute`,
  `removeCurrentAttribute`, `hasCurrentAttribute`,
  `canSetCurrentAttribute`, `updateCurrentAttributes`.
- Nesting: `increaseNestingLevel`, `decreaseNestingLevel`,
  `canDecreaseBlockAttributeLevel`.
- Attachments: `insertAttachment`, `removeAttachment`, `editAttachment`,
  `updateAttributesForAttachment`.

Every mutation flows through `setDocument(document)`
(`composition.coffee:13-18`), which:

1. Short-circuits if the new document equals the current one.
2. Replaces `@document`.
3. Calls `refreshAttachments` (diffs attachment lists, notifies delegate).
4. Increments `@revision`.
5. Notifies `@delegate.compositionDidChangeDocument`.

### Editor — the public API

`src/trix/models/editor.coffee` is a thin façade over `Composition`,
`SelectionManager`, and `UndoManager`. `element.editor` **is** an instance of
this. It is the external contract.

Full method list in [03-architecture.md § Public API](#public-api) below.

### Parsing and serialization

- `html_parser.coffee` — parses HTML → `Document` by walking a hidden sandbox
  DOM, classifying elements as block-level or inline, and recovering
  attributes per `Trix.config.textAttributes` /
  `Trix.config.blockAttributes` (`html_parser.coffee:181-220`).
- `html_sanitizer.coffee` — scrubs disallowed attributes; the default allow-list
  is `"style href src width height class target"` plus anything starting with
  `data-trix-` (`html_sanitizer.coffee:4, 45-49`).
- `src/trix/config/serialization.coffee` — defines `Trix.serializers` and
  `Trix.deserializers` for `application/json` and `text/html`. The HTML
  serializer renders the document to a DOM fragment via
  `Trix.DocumentView.render`, strips internal attributes, applies
  `data-trix-serialized-attributes` overrides, and returns `innerHTML`
  minus `<!--block-->` markers.

### Selection and undo

- `selection_manager.coffee` — bridges `window.getSelection()` and Trix's
  location ranges, with lock/unlock ref-counting so renders don't clobber
  in-progress selection updates.
- `location_mapper.coffee`, `point_mapper.coffee` — convert between screen
  points, DOM ranges, and Trix `LocationRange` / character `Range` arrays.
- `undo_manager.coffee` — two stacks of `{description, context, snapshot}`.
  Consecutive entries with the same description and context are consolidated
  (`undo_manager.coffee:6-12`) — that's how "type one word" is a single undo
  step even though each keystroke records an entry.

### Attachments

- `attachment.coffee` — model with `attributes` (filename, url, contentType,
  width, height, caption, …).
- `attachment_manager.coffee` — wraps attachments on add/remove; delegate
  surface for upload progress.
- `managed_attachment.coffee` — the attachment object handed to user code in
  `trix-attachment-add` events; proxies most methods to the underlying
  `Attachment`.

## Layer 4 — Controllers (`src/trix/controllers/`)

Controllers wire the DOM event layer to the model layer. They do no rendering
themselves.

### EditorController

`src/trix/controllers/editor_controller.coffee`. The conductor.

Constructor (`editor_controller.coffee:13-37`) wires:

- `SelectionManager`, `Composition`, `AttachmentManager`, `InputController`,
  `CompositionController`, `ToolbarController`, and a public `Editor`.
- Itself as the delegate for every sub-controller and model.
- `InputController.responder = Composition` — `InputController` mutates
  `Composition` directly via its responder interface for performance.

The delegate protocol is the real API surface between layers; every
`compositionDidX`, `inputControllerDidX`, `selectionManagerDidX`, and
`toolbarDidX` is implemented here.

`notifyEditorElement(message, data)` (`editor_controller.coffee:345-356`) is
the funnel for all `trix-*` custom events; it also updates the hidden
`<input>` on change/attachment events (`editor_controller.coffee:353-354`).

**Actions** (`editor_controller.coffee:282-302`) — `undo`, `redo`, `link`,
`increaseNestingLevel`, `decreaseNestingLevel`. Each has a `test` (can it fire
now?) and `perform` (do it). External actions use the `x-` prefix convention
and fire `trix-action-invoke` instead of running locally
(`editor_controller.coffee:310-317`).

### InputController

`src/trix/controllers/input_controller.coffee`. Listens for keyboard,
paste, drop, focus/blur, composition events. Uses a `MutationObserver`
(`src/trix/observers/mutation_observer.coffee`) to reconcile unexpected DOM
mutations (IME, browser autocorrect, extensions) with Trix's model
expectations.

There are two flavours:

- `controllers/input/level_0_input_controller.coffee` — fallback for
  browsers without `beforeinput`.
- `controllers/input/level_2_input_controller.coffee` — modern path using
  `beforeinput` events.

Both report to `EditorController` via the
`inputControllerWill*` / `inputControllerDid*` delegate methods
(`editor_controller.coffee:162-215`), which record typing/cut/paste undo
entries and coordinate render lifecycle.

### CompositionController

`src/trix/controllers/composition_controller.coffee`. Owns the
`DocumentView` instance. Calls `render` / `sync` on document change; manages
view caches and attachment editor installation.

### ToolbarController

`src/trix/controllers/toolbar_controller.coffee`. Wires DOM events on the
toolbar element to delegate callbacks:

- Clicks on `[data-trix-attribute]` → `toolbarDidToggleAttribute(name)` or
  open a dialog if one exists with that name
  (`toolbar_controller.coffee:36-46`).
- Clicks on `[data-trix-action]` → `toolbarDidInvokeAction(name)` or open a
  dialog (`toolbar_controller.coffee:26-34`).
- Clicks on `[data-trix-method]` inside a dialog → call the named method on
  the controller itself (`toolbar_controller.coffee:48-51`) — this is how
  the link dialog's "Link" button invokes `setAttribute(dialogElement)`.
- Keydown on dialog inputs → Enter submits, Escape closes
  (`toolbar_controller.coffee:53-61`).

Button state is synced via `updateAttributes(dict)` and `updateActions(dict)`
(`toolbar_controller.coffee:65-89`); buttons get `data-trix-active` when the
attribute is truthy, or disabled (`element.disabled = true`) when the
attribute value is explicitly `false`.

### AttachmentEditorController

`src/trix/controllers/attachment_editor_controller.coffee`. Installed while
an attachment is being edited; handles the caption textarea and remove
button.

## Layer 5 — Views (`src/trix/views/`)

Views are stateless renderers. Each view caches its produced DOM nodes; on
document mutation the view tree is invalidated and re-rendered to a shadow
DOM, then `sync()` clones the shadow into the real editor element.

- `object_view.coffee` — base class. `getNodes()` memoises `createNodes()`.
- `document_view.coffee` — top-level. Groups blocks into an `ObjectGroup`
  tree (respecting block nesting) and creates `BlockView` children.
- `block_view.coffee` — creates block-level containers (`<p>`, `<blockquote>`,
  `<h1>`, `<li>`, `<pre>`, etc.) based on block attributes, then renders
  inner `TextView`.
- `text_view.coffee` — groups pieces that `canBeGrouped` together (the
  default is pieces sharing an `href` value — see `piece.coffee:82-87`) and
  creates `PieceView` children.
- `piece_view.coffee` — the attribute-to-DOM bridge. See
  [04-attribute-system.md § Rendering](04-attribute-system.md#5-rendering-model--dom).
- `attachment_view.coffee`, `previewable_attachment_view.coffee` — render
  `<figure>` with cursor targets and data attributes.
- `object_group_view.coffee` — renders grouped pieces under a single
  container (e.g. `<a href="...">` wrapping adjacent linked pieces).

Rendering is **not** reconciliation-based (no virtual-DOM diff). The view
tree is always rebuilt from the new document; a content-addressed cache keeps
unchanged sub-trees fast (`object_view.coffee` cache key machinery).

## Layer 6 — Observers (`src/trix/observers/`)

- `mutation_observer.coffee` — wraps a `MutationObserver` on the
  contenteditable element; filters out mutations on `[data-trix-mutable]`
  nodes; summarises to `{textAdded, textDeleted}` for the input controller.
- `selection_change_observer.coffee` — singleton that polls
  `document.getSelection()` (via `selectionchange` event where supported,
  otherwise `requestAnimationFrame`) and notifies every registered
  `SelectionManager`.

## Layer 7 — Operations (`src/trix/operations/`)

- `operation.coffee` (in core) — base class. `perform(callback)` is
  subclassed; `getPromise()` wraps the imperative callback in a Promise.
- `file_verification_operation.coffee` — reads a file via `FileReader` to
  verify it's accessible before attaching.
- `image_preload_operation.coffee` — loads an image and captures
  `naturalWidth` / `naturalHeight` before inserting as an attachment.

## Layer 8 — Config (`src/trix/config/`)

Every file in `config/` extends `Trix.config` on import. The index
(`config/index.coffee`) requires them in order.

| File | Exposes |
|---|---|
| `text_attributes.coffee` | `Trix.config.textAttributes` — bold, italic, href, target, strike, frozen. See [04-attribute-system.md](04-attribute-system.md). |
| `block_attributes.coffee` | `Trix.config.blockAttributes` — default, quote, heading1-3, code, bulletList/bullet, numberList/number, alignRight, alignCenter. |
| `toolbar.coffee` | `Trix.config.toolbar.getDefaultHTML()` — the inline template string for the default toolbar markup. |
| `lang.coffee` | `Trix.config.lang` — UI strings. |
| `css.coffee` | `Trix.config.css` — CSS class name map for attachment parts. |
| `attachments.coffee` | Attachment-related toggles (`enableImages` etc.). |
| `file_size_formatting.coffee` | Byte formatting for attachment captions. |
| `serialization.coffee` | `Trix.serializers`, `Trix.deserializers`, `Trix.serializeToContentType`, `Trix.deserializeFromContentType`. |
| `undo_interval.coffee` | `Trix.config.undoInterval` — how often typing coalesces into a single undo step (default 5000ms). |

Config files can be mutated at runtime before calling `registerElement` or
before elements enter the DOM — this is how new attributes get registered.

## Public API

`element.editor` is a `Trix.Editor` (`src/trix/models/editor.coffee:3-141`).

### Document loading / snapshots

```
loadDocument(document)
loadHTML(html)
loadJSON({document, selectedRange})
loadSnapshot({document, selectedRange})
getDocument()                    // => Trix.Document
getSelectedDocument()            // => Trix.Document (selection only)
getSnapshot()                    // => {document, selectedRange}
toJSON()                         // snapshot as JSON-safe
```

### Mutation

```
insertText(text)                 // text: Trix.Text
insertString(string)             // uses currentAttributes
insertHTML(html)
insertDocument(document)
insertAttachment(attachment)
insertFile(file)
insertLineBreak()
deleteInDirection("forward" | "backward")
```

### Selection

```
getSelectedRange()               // => [start, end]
getPosition()                    // => number (cursor position)
getClientRectAtPosition(pos)     // => DOMRect
setSelectedRange(range)
expandSelectionInDirection(dir)
moveCursorInDirection(dir)
```

### Attributes

```
activateAttribute(name, value = true)
deactivateAttribute(name)
attributeIsActive(name)          // => boolean
canActivateAttribute(name)       // => boolean
```

### Nesting (lists / quotes)

```
canIncreaseNestingLevel()
canDecreaseNestingLevel()
increaseNestingLevel()
decreaseNestingLevel()
```

### Undo / redo

```
canUndo()
canRedo()
recordUndoEntry(description, {context, consolidatable} = {})
undo()
redo()
```

## Custom events

All are dispatched on the `<trix-editor>` element (bubble, cancelable). The
funnel is `editor_controller.coffee:345-356`; events fire via
`element.notify(message, data)` →
`triggerEvent("trix-#{message}", onElement: this, attributes: data)`.

| Event | `event.*` payload | When |
|---|---|---|
| `trix-initialize` | — | Editor ready (`requestAnimationFrame` after `connect`). |
| `trix-change` | — | Document or attachment changed. Also refreshes the hidden input. |
| `trix-document-change` | — | Document mutated. |
| `trix-selection-change` | — | Cursor or selection moved. |
| `trix-attributes-change` | `attributes` | `currentAttributes` changed. This is how external UIs read active attributes (bold, href, and any custom attribute). |
| `trix-actions-change` | `actions` | Action availability changed. |
| `trix-action-invoke` | `actionName` | An `x-*`-prefixed external action fired. |
| `trix-attachment-add` | `attachment` (ManagedAttachment) | Attachment added. |
| `trix-attachment-edit` | `attachment` | Attachment attributes changed. |
| `trix-attachment-remove` | `attachment` | Attachment removed. |
| `trix-file-accept` | `file` | Called before accepting a dropped/pasted file. `preventDefault()` to reject. |
| `trix-before-paste` | `paste` (`{html, string, range}`) | Before paste is applied. |
| `trix-paste` | `paste` | After paste applied. |
| `trix-toolbar-dialog-show` | `dialogName` | Dialog opened. |
| `trix-toolbar-dialog-hide` | `dialogName` | Dialog closed. |
| `trix-focus` | — | Editor focused. |
| `trix-blur` | — | Editor blurred. |
| `trix-render` | — | Document re-rendered. |
| `trix-sync` | — | Shadow DOM synced into live element. |

## End-to-end walkthroughs

### Typing a character

1. User types "a". The browser fires `beforeinput` / inserts into the DOM.
2. `Level2InputController` intercepts; `MutationObserver` also sees the DOM
   change.
3. InputController calls `@responder.insertString("a")` —
   `responder = Composition` (`editor_controller.coffee:25`).
4. `Composition.insertString` (`composition.coffee:58-61`) packs the string
   with current attributes via `Text.textForStringWithAttributes` and calls
   `insertText`.
5. `Composition.insertText` (`composition.coffee:34-42`) replaces `@document`
   with `@document.insertTextAtRange(text, range)` and updates selection.
6. `setDocument` fires `compositionDidChangeDocument` to `EditorController`.
7. `EditorController.compositionDidChangeDocument`
   (`editor_controller.coffee:47-49`) calls `@render()` unless in the middle
   of handling input; `notifyEditorElement("document-change")` fires the
   `trix-document-change` event.
8. When input handling ends, render happens. `CompositionController.render`
   rebuilds the view tree and syncs; `trix-sync`, then `trix-change` fire.
   The hidden input value is updated inside `notifyEditorElement`
   (`editor_controller.coffee:353-354`).

### Clicking Bold on a selection

1. User selects "abc", clicks the toolbar Bold button.
2. `ToolbarController.didClickAttributeButton`
   (`toolbar_controller.coffee:36-46`) calls
   `delegate.toolbarDidToggleAttribute("bold")`.
3. `EditorController.toolbarDidToggleAttribute`
   (`editor_controller.coffee:234-238`) records a "Formatting" undo entry
   and calls `@composition.toggleCurrentAttribute("bold")`.
4. `Composition.toggleCurrentAttribute` (`composition.coffee:220-224`)
   flips between `setCurrentAttribute("bold", true)` and
   `removeCurrentAttribute("bold")`.
5. `setCurrentAttribute` → `setTextAttribute` → since selection is
   expanded, `@setDocument(@document.addAttributeAtRange("bold", true, range))`
   (`composition.coffee:260-268`).
6. `Document.addAttributeAtRange` (`document.coffee:344-355`) walks blocks in
   the range, calls `block.text.addAttributeAtRange`, which splits pieces at
   range boundaries and applies the attribute via
   `piece.copyWithAdditionalAttributes` (`text.coffee:58-60`,
   `piece.coffee:19-20`).
7. `compositionDidChangeDocument` → render → sync.
8. `compositionDidChangeCurrentAttributes` also fires (because
   `@currentAttributes.bold = true`) — `ToolbarController.updateAttributes`
   lights up the Bold button; `trix-attributes-change` event fires.

### Pasting HTML

1. `InputController` sees a paste, calls
   `inputControllerWillPaste({html, string, range})` on delegate.
2. `EditorController.inputControllerWillPaste`
   (`editor_controller.coffee:187-190`) records a "Paste" undo entry and
   fires `trix-before-paste` (cancelable).
3. If not cancelled, `Composition.insertHTML(html)` (`composition.coffee:91-100`)
   parses via `Document.fromHTML` → `Trix.HTMLParser.parse`
   (`html_parser.coffee:23-32`), merges into the current document at the
   selection range, moves selection past the inserted range.
4. `inputControllerDidPaste` fires `trix-paste`
   (`editor_controller.coffee:192-196`).
