{assert, clickToolbarButton, createFile, defer, expandSelection, moveCursor, pasteContent, pressKey, selectAll, test, testGroup, triggerEvent, typeCharacters} = Trix.TestHelpers

testGroup "Pasting", template: "editor_empty", ->
  test "paste plain text", (expectDocument) ->
    typeCharacters "abc", ->
      moveCursor "left", ->
        pasteContent "text/plain", "!", ->
          expectDocument "ab!c\n"

  test "paste simple html", (expectDocument) ->
    typeCharacters "abc", ->
      moveCursor "left", ->
        pasteContent "text/html", "&lt;", ->
          expectDocument "ab<c\n"

  test "paste complex html", (expectDocument) ->
    typeCharacters "abc", ->
      moveCursor "left", ->
        pasteContent "text/html", "<div>Hello world<br></div><div>This is a test</div>", ->
          expectDocument "abHello world\nThis is a test\nc\n"

  test "paste html in expanded selection", (expectDocument) ->
    typeCharacters "abc", ->
      moveCursor "left", ->
        expandSelection direction: "left", times: 2, ->
          pasteContent "text/html", "<strong>x</strong>", ->
            assert.selectedRange(1)
            expectDocument "xc\n"

  test "paste plain text with CRLF ", (expectDocument) ->
    pasteContent "text/plain", "a\r\nb\r\nc", ->
      expectDocument "a\nb\nc\n"

  test "paste html with CRLF ", (expectDocument) ->
    pasteContent "text/html", "<div>a<br></div>\r\n<div>b<br></div>\r\n<div>c<br></div>", ->
      expectDocument "a\nb\nc\n"

  test "prefers plain text when html lacks formatting", (expectDocument) ->
    pasteData =
      "text/html": "<meta charset='utf-8'>a\nb"
      "text/plain": "a\nb"

    pasteContent pasteData, ->
      expectDocument "a\nb\n"

  test "prefers formatted html", (expectDocument) ->
    pasteData =
      "text/html": "<meta charset='utf-8'>a\n<strong>b</strong>"
      "text/plain": "a\nb"

    pasteContent pasteData, ->
      expectDocument "a b\n"

  test "paste URL", (expectDocument) ->
    typeCharacters "a", ->
      pasteContent "URL", "http://example.com", ->
        assert.textAttributes([1, 18], href: "http://example.com")
        expectDocument "ahttp://example.com\n"

  test "paste URL with name", (expectDocument) ->
    pasteData =
      "URL": "http://example.com"
      "public.url-name": "Example"
      "text/plain": "http://example.com"

    pasteContent pasteData, ->
      assert.textAttributes([0, 7], href: "http://example.com")
      expectDocument "Example\n"

  test "paste URL with name containing extraneous whitespace", (expectDocument) ->
    pasteData =
      "URL": "http://example.com"
      "public.url-name": "   Example from \n link  around\n\nnested \nelements "
      "text/plain": "http://example.com"

    pasteContent pasteData, ->
      assert.textAttributes([0, 40], href: "http://example.com")
      expectDocument "Example from link around nested elements\n"

  test "paste complex html into formatted block", (done) ->
    typeCharacters "abc", ->
      clickToolbarButton attribute: "quote", ->
        pasteContent "text/html", "<div>Hello world<br></div><pre>This is a test</pre>", ->
          document = getDocument()
          assert.equal document.getBlockCount(), 2

          block = document.getBlockAtIndex(0)
          assert.deepEqual block.getAttributes(), ["quote"],
          assert.equal block.toString(), "abcHello world\n"

          block = document.getBlockAtIndex(1)
          assert.deepEqual block.getAttributes(), ["code"]
          assert.equal block.toString(), "This is a test\n"

          done()
  
  test "paste complex html to end of header", (done) -> 
    typeCharacters "header1", ->
      clickToolbarButton attribute: "heading1", ->
        pasteContent "text/html", "<h1>header2</h1><div>paragraph</div>", ->
          doc = getDocument()
          assert.equal doc.getBlockCount(), 2
          block = doc.getBlockAtIndex(0)
          assert.deepEqual block.getAttributes(), ["heading1"]
          block = doc.getBlockAtIndex(1)
          assert.deepEqual block.getAttributes(), []

          output = document.querySelector("trix-editor").value
          assert.equal output, "<h1>header1header2</h1><div>paragraph</div>"
          done();

  test "pasting different kind of headers into each other", (done) ->
    typeCharacters "header1", ->
      clickToolbarButton attribute: "heading1", ->
        pasteContent "text/html", "<h2>header2</h2>", ->
          doc = getDocument()
          assert.equal doc.getBlockCount(), 2
          block = doc.getBlockAtIndex(0)
          assert.deepEqual block.getAttributes(), ["heading1"]
          output = document.querySelector("trix-editor").value
          assert.equal output, "<h1>header1</h1><h2>header2</h2>"
          done();

  test "pasting after having select all should delete previous alignment", (done) ->
    typeCharacters "header1", ->
      clickToolbarButton attribute: "heading1", ->
        getEditorController().composition.setCurrentAttribute('alignRight')
        selectAll ->
          pasteContent "text/html", "<div>paragraph</div>", ->
            doc = getDocument()
            assert.equal doc.getBlockCount(), 1
            block = doc.getBlockAtIndex(0)
            assert.deepEqual block.getAttributes(), []
            output = document.querySelector("trix-editor").value
            assert.equal output, "<div>paragraph</div>"
            done();

  test "pasting after having select all should delete previous header attribute", (done) ->
    typeCharacters "header1", ->
      clickToolbarButton attribute: "heading1", ->

        selectAll ->
          pasteContent "text/html", "<div>paragraph</div>", ->
            doc = getDocument()
            assert.equal doc.getBlockCount(), 1
            block = doc.getBlockAtIndex(0)
            assert.deepEqual block.getAttributes(), []
            output = document.querySelector("trix-editor").value
            assert.equal output, "<div>paragraph</div>"
            done();

  test "paste list into list", (done) ->
    clickToolbarButton attribute: "bullet", ->
      typeCharacters "abc\n", ->
        pasteContent "text/html", "<ul><li>one</li><li>two</li></ul>", ->
          document = getDocument()
          assert.equal document.getBlockCount(), 3

          block = document.getBlockAtIndex(0)
          assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
          assert.equal block.toString(), "abc\n"

          block = document.getBlockAtIndex(1)
          assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
          assert.equal block.toString(), "one\n"

          block = document.getBlockAtIndex(2)
          assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
          assert.equal block.toString(), "two\n"

          done()

  test "paste list into quote", (done) ->
    clickToolbarButton attribute: "quote", ->
      typeCharacters "abc", ->
        pasteContent "text/html", "<ul><li>one</li><li>two</li></ul>", ->
          document = getDocument()
          assert.equal document.getBlockCount(), 3

          block = document.getBlockAtIndex(0)
          assert.deepEqual block.getAttributes(), ["quote"]
          assert.equal block.toString(), "abc\n"

          block = document.getBlockAtIndex(1)
          assert.deepEqual block.getAttributes(), ["quote", "bulletList", "bullet"]
          assert.equal block.toString(), "one\n"

          block = document.getBlockAtIndex(2)
          assert.deepEqual block.getAttributes(), ["quote", "bulletList", "bullet"]
          assert.equal block.toString(), "two\n"

          done()

  test "paste list into quoted list", (done) ->
    clickToolbarButton attribute: "quote", ->
      clickToolbarButton attribute: "bullet", ->
        typeCharacters "abc\n", ->
          pasteContent "text/html", "<ul><li>one</li><li>two</li></ul>", ->
            document = getDocument()
            assert.equal document.getBlockCount(), 3

            block = document.getBlockAtIndex(0)
            assert.deepEqual block.getAttributes(), ["quote", "bulletList", "bullet"]
            assert.equal block.toString(), "abc\n"

            block = document.getBlockAtIndex(1)
            assert.deepEqual block.getAttributes(), ["quote", "bulletList", "bullet"]
            assert.equal block.toString(), "one\n"

            block = document.getBlockAtIndex(2)
            assert.deepEqual block.getAttributes(), ["quote", "bulletList", "bullet"]
            assert.equal block.toString(), "two\n"

            done()

  test "paste nested list into empty list item", (done) ->
    clickToolbarButton attribute: "bullet", ->
      typeCharacters "y\nzz", ->
        getSelectionManager().setLocationRange(index: 0, offset: 1)
        defer ->
          pressKey "backspace", ->
            pasteContent "text/html", "<ul><li>a<ul><li>b</li></ul></li></ul>", ->
            document = getDocument()
            assert.equal document.getBlockCount(), 3

            block = document.getBlockAtIndex(0)
            assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
            assert.equal block.toString(), "a\n"

            block = document.getBlockAtIndex(1)
            assert.deepEqual block.getAttributes(), ["bulletList", "bullet", "bulletList", "bullet"]
            assert.equal block.toString(), "b\n"

            block = document.getBlockAtIndex(2)
            assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
            assert.equal block.toString(), "zz\n"
            done()

  test "paste nested list over list item contents", (done) ->
    clickToolbarButton attribute: "bullet", ->
      typeCharacters "y\nzz", ->
        getSelectionManager().setLocationRange(index: 0, offset: 1)
        defer ->
          expandSelection "left", ->
            pasteContent "text/html", "<ul><li>a<ul><li>b</li></ul></li></ul>", ->
            document = getDocument()
            assert.equal document.getBlockCount(), 3

            block = document.getBlockAtIndex(0)
            assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
            assert.equal block.toString(), "a\n"

            block = document.getBlockAtIndex(1)
            assert.deepEqual block.getAttributes(), ["bulletList", "bullet", "bulletList", "bullet"]
            assert.equal block.toString(), "b\n"

            block = document.getBlockAtIndex(2)
            assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
            assert.equal block.toString(), "zz\n"
            done()

  test "paste list into empty block before list", (done) ->
    clickToolbarButton attribute: "bullet", ->
      typeCharacters "c", ->
        moveCursor "left", ->
          pressKey "return", ->
            getSelectionManager().setLocationRange(index: 0, offset: 0)
            defer ->
              pasteContent "text/html", "<ul><li>a</li><li>b</li></ul>", ->
                document = getDocument()
                assert.equal document.getBlockCount(), 3

                block = document.getBlockAtIndex(0)
                assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
                assert.equal block.toString(), "a\n"

                block = document.getBlockAtIndex(1)
                assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
                assert.equal block.toString(), "b\n"

                block = document.getBlockAtIndex(2)
                assert.deepEqual block.getAttributes(), ["bulletList", "bullet"]
                assert.equal block.toString(), "c\n"
                done()

  test "paste file", (expectDocument) ->
    typeCharacters "a", ->
      pasteContent "Files", (createFile()), ->
        expectDocument "a#{Trix.OBJECT_REPLACEMENT_CHARACTER}\n"

  test "paste event with no clipboardData", (expectDocument) ->
    typeCharacters "a", ->
      triggerEvent(document.activeElement, "paste")
      document.activeElement.insertAdjacentHTML("beforeend", "<span>bc</span>")
      requestAnimationFrame ->
        expectDocument("abc\n")
