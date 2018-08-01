# Attribute explanation
#
# `inheritFromPreviousBlock: boolean`
# When the user has e.g. the end of a block selected, and presses return
# this property will decide whether the block attribute should be copied
# from the original block to the one that gets created.

Trix.config.blockAttributes = attributes =
  default:
    tagName: "div"
    parse: false
  quote:
    tagName: "blockquote"
    nestable: true
  heading1:
    tagName: "h1"
    terminal: true
    breakOnReturn: true
    group: false
  heading2:
    tagName: "h2"
    terminal: true
    breakOnReturn: true
    group: false
  heading3:
    tagName: "h3"
    terminal: true
    breakOnReturn: true
    group: false
  code:
    tagName: "pre"
    terminal: true
    text:
      plaintext: true
  bulletList:
    tagName: "ul"
    parse: false
  bullet:
    tagName: "li"
    listAttribute: "bulletList"
    group: false
    nestable: true
    test: (element) ->
      Trix.tagName(element.parentNode) is attributes[@listAttribute].tagName
  numberList:
    tagName: "ol"
    parse: false
  number:
    tagName: "li"
    listAttribute: "numberList"
    group: false
    nestable: true
    test: (element) ->
      Trix.tagName(element.parentNode) is attributes[@listAttribute].tagName
  alignRight:
    inheritFromPreviousBlock: true
    # Note: `div` only kept here for ease of testing (we change to `p` in prod)
    tagNames: ["div", "p", "h1", "h2", "h3"]
    className: "text-align-right"
    role: "alignment"
    test: (element) -> element.className?.indexOf("text-align-right") != -1
  alignLeft:
    inheritFromPreviousBlock: true
    tagNames: ["div", "p", "h1", "h2", "h3"]
    className: "text-align-left"
    role: "alignment"
    test: (element) -> element.className?.indexOf("text-align-left") != -1
  alignCenter:
    inheritFromPreviousBlock: true
    tagNames: ["div", "p", "h1", "h2", "h3"]
    className: "text-align-center"
    role: "alignment"
    test: (element) -> element.className?.indexOf("text-align-center") != -1
