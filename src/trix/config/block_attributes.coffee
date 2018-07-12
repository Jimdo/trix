Trix.config.blockAttributes = attributes =
  default:
    tagName: "p"
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
    tagNames: ["p", "h1", "h2", "h3"]
    className: "text-align-right"
    role: "alignment"
    test: (element) -> element.className?.indexOf("text-align-right") != -1
  alignLeft:
    tagNames: ["p", "h1", "h2", "h3"]
    className: "text-align-left"
    role: "alignment"
    test: (element) -> element.className?.indexOf("text-align-left") != -1
  alignCenter:
    tagNames: ["p", "h1", "h2", "h3"]
    className: "text-align-center"
    role: "alignment"
    test: (element) -> element.className?.indexOf("text-align-center") != -1
