#= require trix/models/text

{arraysAreEqual, spliceArray, getBlockConfig, getBlockAttributeNames, getListAttributeNames} = Trix

class Trix.Block extends Trix.Object
  @fromJSON: (blockJSON) ->
    text = Trix.Text.fromJSON(blockJSON.text)
    new this text, blockJSON.attributes

  constructor: (text = new Trix.Text, attributes = []) ->
    super
    @text = applyBlockBreakToText(text)
    @attributes = attributes

  isEmpty: ->
    @text.isBlockBreak()

  isEqualTo: (block) ->
    super or (
      @text.isEqualTo(block?.text) and
      arraysAreEqual(@attributes, block?.attributes)
    )

  copyWithText: (text) ->
    new @constructor text, @attributes

  copyWithoutText: ->
    @copyWithText(null)

  copyWithAttributes: (attributes) ->
    new @constructor @text, attributes

  copyUsingObjectMap: (objectMap) ->
    if mappedText = objectMap.find(@text)
      @copyWithText(mappedText)
    else
      @copyWithText(@text.copyUsingObjectMap(objectMap))

  addAttribute: (attribute) ->
    {role} = Trix.getBlockConfig(attribute)
    if role?
      filteredAttributes = []
      for attr in @attributes
        filteredAttributes.push(attr) unless Trix.getBlockConfig(attr).role is role
        @attributes = filteredAttributes
    attributes = @attributes.concat(expandAttribute(attribute))
    @copyWithAttributes(attributes)

  removeAttribute: (attribute) ->
    {listAttribute} = getBlockConfig(attribute)
    attributes = removeLastValue(removeLastValue(@attributes, attribute), listAttribute)
    @copyWithAttributes(attributes)

  removeLastAttribute: ->
    @removeAttribute(@getLastAttribute())

  getLastAttribute: ->
    # if we dont use significant attrs here
    # then a lot of logic relying on the fact
    # that there should be only a single
    # block attribute will stop working
    significantAttrs = @getSignificantAttributes()
    getLastElement(significantAttrs)

  # "significant" here can loosely be defined as
  # "all block attrs who dont deal with alignment"
  getSignificantAttributes: ->
    insignificantAttributes = ["alignCenter", "alignRight"]
    @getAttributes().filter (attr) ->
      attr not in insignificantAttributes

  getAttributes: ->
    @attributes.slice(0)

  getAttributeLevel: ->
    significantAttrs = @getSignificantAttributes()
    significantAttrs.length

  getAttributeAtLevel: (level) ->
    @attributes[level - 1]

  hasSignificantAttributes: ->
    significantAttrs = @getSignificantAttributes()
    significantAttrs.length > 0

  hasAnyAttributes: ->
    @getAttributes().length > 0

  hasAttributes: ->
    @getAttributeLevel() > 0

  getLastNestableAttribute: ->
    getLastElement(@getNestableAttributes())

  getNestableAttributes: ->
    attribute for attribute in @attributes when getBlockConfig(attribute).nestable

  getNestingLevel: ->
    @getNestableAttributes().length

  decreaseNestingLevel: ->
    if attribute = @getLastNestableAttribute()
      @removeAttribute(attribute)
    else
      this

  increaseNestingLevel: ->
    if attribute = @getLastNestableAttribute()
      index = @attributes.lastIndexOf(attribute)
      attributes = spliceArray(@attributes, index + 1, 0, expandAttribute(attribute)...)
      @copyWithAttributes(attributes)
    else
      this

  getListItemAttributes: ->
    attribute for attribute in @attributes when getBlockConfig(attribute).listAttribute

  isListItem: ->
    getBlockConfig(@getLastAttribute())?.listAttribute

  isTerminalBlock: ->
    getBlockConfig(@getLastAttribute())?.terminal

  breaksOnReturn: ->
    getBlockConfig(@getLastAttribute())?.breakOnReturn

  findLineBreakInDirectionFromPosition: (direction, position) ->
    string = @toString()
    result = switch direction
      when "forward"
        string.indexOf("\n", position)
      when "backward"
        string.slice(0, position).lastIndexOf("\n")

    result unless result is -1

  contentsForInspection: ->
    text: @text.inspect()
    attributes: @attributes

  toString: ->
    @text.toString()

  toJSON: ->
    text: @text
    attributes: @attributes

  # Splittable

  getLength: ->
    @text.getLength()

  canBeConsolidatedWith: (block) ->
    not @hasAttributes() and not block.hasAttributes()

  consolidateWith: (block) ->
    newlineText = Trix.Text.textForStringWithAttributes("\n")
    text = @getTextWithoutBlockBreak().appendText(newlineText)
    @copyWithText(text.appendText(block.text))

  splitAtOffset: (offset) ->
    if offset is 0
      left = null
      right = this
    else if offset is @getLength()
      left = this
      right = null
    else
      left = @copyWithText(@text.getTextAtRange([0, offset]))
      right = @copyWithText(@text.getTextAtRange([offset, @getLength()]))
    [left, right]

  getBlockBreakPosition: ->
    @text.getLength() - 1

  getTextWithoutBlockBreak: ->
    if textEndsInBlockBreak(@text)
      @text.getTextAtRange([0, @getBlockBreakPosition()])
    else
      @text.copy()

  # Grouping

  canBeGrouped: (depth) ->
    attrs = @getSignificantAttributes()
    attr = attrs[depth]

  canBeGroupedWith: (otherBlock, depth) ->
    otherAttributes = otherBlock.getSignificantAttributes()
    otherAttribute = otherAttributes[depth]
    attribute = @getSignificantAttributes()[depth]

    attribute is otherAttribute and
      not (getBlockConfig(attribute).group is false and
           otherAttributes[depth + 1] not in getListAttributeNames())

  # Block breaks

  applyBlockBreakToText = (text) ->
    text = unmarkExistingInnerBlockBreaksInText(text)
    text = addBlockBreakToText(text)
    text

  unmarkExistingInnerBlockBreaksInText = (text) ->
    modified = false
    [innerPieces..., lastPiece] = text.getPieces()
    return text unless lastPiece?

    innerPieces = for piece in innerPieces
      if piece.isBlockBreak()
        modified = true
        unmarkBlockBreakPiece(piece)
      else
        piece

    if modified
      new Trix.Text [innerPieces..., lastPiece]
    else
      text

  blockBreakText = Trix.Text.textForStringWithAttributes("\n", blockBreak: true)

  addBlockBreakToText = (text) ->
    if textEndsInBlockBreak(text)
      text
    else
      text.appendText(blockBreakText)

  textEndsInBlockBreak = (text) ->
    length = text.getLength()
    return false if length is 0
    endText = text.getTextAtRange([length - 1, length])
    endText.isBlockBreak()

  unmarkBlockBreakPiece = (piece) ->
    piece.copyWithoutAttribute("blockBreak")

  # Attributes

  expandAttribute = (attribute) ->
    {listAttribute} = getBlockConfig(attribute)
    if listAttribute?
      [listAttribute, attribute]
    else
      [attribute]

  # Array helpers

  getLastElement = (array) ->
    array.slice(-1)[0]

  removeLastValue = (array, value) ->
    index = array.lastIndexOf(value)
    if index is -1
      array
    else
      spliceArray(array, index, 1)
