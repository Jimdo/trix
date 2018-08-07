class Trix.LineBreakInsertion
  constructor: (@composition) ->
    {@document} = @composition

    [@startPosition, @endPosition] = @composition.getSelectedRange()
    @startLocation = @document.locationFromPosition(@startPosition)
    @endLocation = @document.locationFromPosition(@endPosition)

    @block = @document.getBlockAtIndex(@endLocation.index)
    @breaksOnReturn = @block.breaksOnReturn()
    @previousCharacter = @block.text.getStringAtPosition(@endLocation.offset - 1)
    @nextCharacter = @block.text.getStringAtPosition(@endLocation.offset)

  shouldInsertBlockBreak: ->
    if @block.hasAttributes() and @block.isListItem() and not @block.isEmpty()
      @startLocation.offset isnt 0
    else
      # `offset isnt 0` to prevent the cursor being at start of lines
      # and inserting block breaks that have no styling
      @breaksOnReturn and @nextCharacter isnt "\n" and @startLocation.offset isnt 0

  shouldBreakFormattedBlock: ->
    # Blockbreaks should only follow blocks that have
    # non-alignment block attributes. If the previous block
    # is one that only contains alignment properties
    # then we want to add a newline to that block instead
    # of doing a blockbreak (hence `hasSignificantAttributes()`)
    isEmpty = @block.toString().replace(/\n/g, "") is ""
    @block.hasSignificantAttributes() and not @block.isListItem() and not isEmpty and
      ((@breaksOnReturn and @nextCharacter is "\n") or @previousCharacter is "\n")

  shouldDecreaseListLevel: ->
    @block.hasAttributes() and @block.isListItem() and @block.isEmpty()

  shouldPrependListItem: ->
    @block.isListItem() and @startLocation.offset is 0 and not @block.isEmpty()

  shouldRemoveLastBlockAttribute: ->
    @block.hasSignificantAttributes() and not @block.isListItem() and @block.isEmpty()
