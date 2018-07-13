#= require trix/views/text_view

{makeElement, getBlockConfig} = Trix

class Trix.BlockView extends Trix.ObjectView
  constructor: ->
    super
    @block = @object
    @attributes = @block.getAttributes()

  createNodes: ->
    comment = document.createComment("block")
    nodes = [comment]
    if @block.isEmpty()
      nodes.push(makeElement("br"))
    else
      textConfig = getBlockConfig(@block.getLastAttribute())?.text
      textView = @findOrCreateCachedChildView(Trix.TextView, @block.text, {textConfig})
      nodes.push(textView.getNodes()...)
      nodes.push(makeElement("br")) if @shouldAddExtraNewlineElement()

    blacklist = ["alignRight", "alignLeft", "alignCenter"]
    attributes = (attr for attr in @attributes when attr not in blacklist)

    if attributes.length
      nodes
    else
      element = makeElement(Trix.config.blockAttributes.default.tagName)
      classNames = []
      for attribute in @attributes
          classNames.push(className) if className = Trix.getBlockConfig(attribute)?.className
      element.className = classNames.join(' ') unless classNames.length is 0
      element.appendChild(node) for node in nodes
      [element]

  createContainerElement: (depth) ->
    attribute = undefined
    config = undefined

    # since we want to skip block attributes
    # that do not have a tagName property
    # (i.e. the alignment attrs)
    for attr in @attributes.slice(depth)
      if attr
        # keep assigning, since if there is no
        # other block attr with tagName
        # we use the default tagName instead
        config = getBlockConfig(attr)
        attribute = attr
        if config.tagName
          break

    config = getBlockConfig(attribute)
    if config.tagName
      element = makeElement(config.tagName)
    else
      element = makeElement(Trix.config.blockAttributes.default.tagName)

    # add classes from align* block attributes
    classNames = []
    for attribute in @attributes
        classNames.push(className) if className = Trix.getBlockConfig(attribute)?.className
    element.className = classNames.join(' ') unless classNames.length is 0
    element

  # A single <br> at the end of a block element has no visual representation
  # so add an extra one.
  shouldAddExtraNewlineElement:->
    /\n\n$/.test(@block.toString())
