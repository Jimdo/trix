{browser} = Trix

class Trix.CompositionInput extends Trix.BasicObject
  constructor: (@inputController) ->
    {@responder, @delegate, @inputSummary} = @inputController
    @data = {}

  start: (data) ->
    @data.start = data

  update: (data) ->
    @data.update = data

  reparse: () =>
    @inputController.delegate.reparse()

  end: (data) ->
    @data.end = data
    if @isSignificant() and @canApplyToDocument
      setTimeout(@reparse, 1);

  getEndData: ->
    @data.end

  isEnded: ->
    @getEndData()?

  isSignificant: ->
    if browser.composesExistingText
      @inputSummary.didInput
    else
      true

  # Private

  canApplyToDocument: ->
    @data.start?.length is 0 and @data.end?.length > 0 and @range?

  @proxyMethod "inputController.setInputSummary"
  @proxyMethod "inputController.requestRender"
  @proxyMethod "inputController.requestReparse"
  @proxyMethod "responder?.selectionIsExpanded"
  @proxyMethod "responder?.insertPlaceholder"
  @proxyMethod "responder?.selectPlaceholder"
  @proxyMethod "responder?.forgetPlaceholder"
