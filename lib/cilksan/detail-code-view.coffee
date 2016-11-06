TextEditor = null
CustomSet = require('../utils/set')
$ = require('jquery')

VERBS_PT = {
  "read": "read",
  "write": "written"
}

module.exports =
class DetailCodeView
  element: null

  # Properties from parent
  props: null
  violation: null
  index: null
  onViolationClickCallback: null

  constructor: (props) ->
    @props = props
    @violation = props.violation
    @index = props.index
    @onViolationClickCallback = props.onViolationClickCallback

    if @props.isVisual
      @element = @createVisualViolationView()
    else
      @element = @createViolationView()

  # Creates a visual version of the race conditions.
  createVisualViolationView: () ->
    violationView = document.createElement('div')
    violationView.classList.add('violation-div', 'visual')
    if @index % 2 is 0
      violationView.classList.add('even')
    $(violationView).click((e) =>
      console.log("[detail-code-view] violation view #{@index} clicked")
      @onViolationClickCallback(e, @index)
    )
    # violationView.addEventListener("click", ((e) => @onViolationClickCallback(e, @index)), true)
    violationView.appendChild(@constructVisualPreview(@violation.line1, null, true))
    # currently no stack traces
    violationView.appendChild(@constructVisualPreview(@violation.line2, null, false))

    return violationView

  # Creates a non-visual version of the race conditions with mostly text only.
  createViolationView: () ->
    violationView = document.createElement('div')
    violationView.classList.add('violation-div')
    $(violationView).click((e) =>
      @onViolationClickCallback(e, @index)
    )

    summaryDiv = document.createElement('div')
    summaryDiv.classList.add('summary-div')
    if @violation.line1.accessType is @violation.line2.accessType
      summaryDiv.textContent = "A variable was concurrently #{VERBS_PT[@violation.line1.accessType]} at #{@parseAbsolutePathname(@violation.line1.filename)}:#{@violation.line1.line} and #{@parseAbsolutePathname(@violation.line2.filename)}:#{@violation.line2.line}."
    else
      summaryDiv.textContent = "A variable was concurrently #{VERBS_PT[@violation.line1.accessType]} at #{@parseAbsolutePathname(@violation.line1.filename)}:#{@violation.line1.line} and #{VERBS_PT[@violation.line2.accessType]} at #{@parseAbsolutePathname(@violation.line2.filename)}:#{@violation.line2.line}."
    violationView.appendChild(summaryDiv)

    violationView.appendChild(@constructCodePreview(@violation.line1, null, true))
    # currently no stack traces
    violationView.appendChild(@constructCodePreview(@violation.line2, null, false))

    return violationView

  constructCodePreview: (lineInfo, stacktrace, isLeft) ->
    if stacktrace?
      console.log("Called constructCodePreview with stack trace: ")
      console.log(stacktrace)
    console.log(lineInfo)

    divToAdd = document.createElement('div')
    divToAdd.classList.add('code-container-table')
    if not isLeft
      divToAdd.classList.add('right')

    # First we check if there is a source annotation to use.
    if lineInfo.text is undefined
      emptyDiv = document.createElement('div')
      emptyDiv.classList.add('empty')
      emptyDiv.textContent = "No information on this access."
      divToAdd.appendChild(emptyDiv)
      return divToAdd

    lineCode = lineInfo.text.join('\n')
    filenamePath = lineInfo.filename.split('/')
    filename = filenamePath[filenamePath.length - 1]
    minLineNum = lineInfo.lineRange[0]
    maxLineNum = lineInfo.lineRange[1]
    originalLineNum = lineInfo.line

    filenameDiv = document.createElement('div')
    DetailCodeView.attachFileOpenListener(filenameDiv, lineInfo.filename, originalLineNum)
    filenameDiv.classList.add('filename-line-number')
    filenameDiv.textContent = "#{filename}:#{originalLineNum}"
    divToAdd.appendChild(filenameDiv)

    codeContainer = document.createElement('table')
    codeContainer.classList.add('code-container')
    codeRow = document.createElement('tr')
    codeContainer.appendChild(codeRow)
    lineNumberCell = document.createElement('td')
    codeRow.appendChild(lineNumberCell)
    lineNumberContainer = document.createElement('div')
    lineNumberContainer.classList.add('line-number-container')
    lineNumberCell.appendChild(lineNumberContainer)

    for lineNum in [minLineNum .. maxLineNum]
      lineNumberDiv = document.createElement('div')
      lineNumberDiv.classList.add('line-number')
      DetailCodeView.attachFileOpenListener(lineNumberDiv, lineInfo.filename, lineNum)
      if lineNum is originalLineNum
        lineNumberDiv.innerHTML = "<code class='highlighted'>#{lineNum}</code>"
      else
        lineNumberDiv.innerHTML = "<code>#{lineNum}</code>"
      lineNumberContainer.appendChild(lineNumberDiv)

    #### Text Editor

    lineEditor = @createMiniEditorWithCode(lineCode)
    lineEditorView = atom.views.getView(lineEditor)

    editorCell = document.createElement('td')
    editorContainer = document.createElement('div')
    editorContainer.classList.add('editor-container')
    DetailCodeView.attachFileOpenListener(editorContainer, lineInfo.filename, originalLineNum)
    editorCell.appendChild(editorContainer)
    editorContainer.appendChild(lineEditorView)

    editorOverlay = document.createElement('div')
    editorOverlay.classList.add('editor-overlay')
    lineHighlightOverlay = document.createElement('div')
    lineHighlightOverlay.classList.add('line-highlight-overlay')
    editorContainer.appendChild(editorOverlay)
    editorContainer.appendChild(lineHighlightOverlay)

    codeRow.appendChild(editorCell)

    stacktraceDiv = document.createElement('div')
    stacktraceDiv.classList.add('stacktrace-container')
    if stacktrace?
      for file in Object.getOwnPropertyNames(stacktrace)
        console.log(stacktrace[file])
        console.log(stacktrace[file].length)
        for i in [0 ... stacktrace[file].length]
          st = stacktrace[file][i]
          firstLineDiv = document.createElement('div')
          firstLineDiv.classList.add('stacktrace-line', 'first')
          stacktraceDiv.appendChild(firstLineDiv)
          firstLineDiv.innerHTML = "called by: <span class='entity name function c'>#{st[0].functionName}</span> (<span class='stacktrace-line-ref'>#{st[0].filename}:#{st[0].lineNum}</span>)"
          stacktraceLocationSpan = firstLineDiv.children[1]
          DetailCodeView.attachFileOpenListener(stacktraceLocationSpan, st[0].rawFilename, st[0].lineNum)

          additionalInfoContainer = document.createElement('div')
          additionalInfoContainer.classList.add('additional-stacktrace')
          html = ""
          st.slice(1).forEach((item) ->
            html += "\t<span class='entity name function c'>#{item.functionName}</span> (<span class='stacktrace-line-ref'>#{item.filename}:#{item.lineNum}</span>)\n"
          )
          # Go through the extra stacktrace lines to attach our file-opening listener.
          additionalInfoContainer.innerHTML = html.slice(0, -1)
          for i in [1 .. additionalInfoContainer.children.length - 1] by 2
            stacktraceIndex = Math.ceil(i / 2)
            DetailCodeView.attachFileOpenListener(additionalInfoContainer.children[i], st[stacktraceIndex].rawFilename, st[stacktraceIndex].lineNum)

          if st.length > 1
            additionalInfoButton = document.createElement('div')
            stacktraceDiv.appendChild(additionalInfoButton)
            additionalInfoButton.classList.add('full-stacktrace-button')
            additionalInfoButton.textContent = "(see full stack trace)"

            $(additionalInfoButton).click((e) =>
              console.log("Toggling the stacktrace.")
              $(additionalInfoContainer).toggleClass('clicked')
              if $(additionalInfoContainer).hasClass('clicked')
                additionalInfoButton.textContent = "(hide full stack trace)"
              else
                additionalInfoButton.textContent = "(see full stack trace)"
            )

            stacktraceDiv.appendChild(additionalInfoContainer)
    else
      stacktraceDiv.classList.add('empty')
      stacktraceDiv.textContent = "(no stack trace available for this access)"

    divToAdd.appendChild(codeContainer)
    divToAdd.appendChild(stacktraceDiv)

    return divToAdd

  constructVisualPreview: (lineInfo, stacktrace, isFirst) ->
    if stacktrace?
      console.log("Called constructVisualPreview with stack trace: ")
      console.log(stacktrace)
    console.log(lineInfo)

    divToAdd = document.createElement('div')
    divToAdd.classList.add('code-container-table', 'visual-detail')
    if not isFirst
      divToAdd.classList.add('bottom')

    # First we check if there is a source annotation to use.
    # console.log("LineInfoText: ")
    # console.log(lineInfo.text)
    # console.log(lineInfo.text is undefined)
    if lineInfo.text is undefined
      emptyDiv = document.createElement('div')
      emptyDiv.classList.add('empty')
      emptyDiv.textContent = "No information was provided for this access."
      divToAdd.appendChild(emptyDiv)
      return divToAdd

    lineCode = lineInfo.text[2]
    filenamePath = lineInfo.filename.split('/')
    filename = filenamePath[filenamePath.length - 1]
    minLineNum = lineInfo.lineRange[0]
    maxLineNum = lineInfo.lineRange[1]
    originalLineNum = if lineInfo.line then lineInfo.line else '??'

    codeLineDiv = document.createElement('div')
    codeLineDiv.classList.add('code-line-container')
    readWriteDiv = document.createElement('div')
    readWriteDiv.classList.add('read-write-div')
    if lineInfo.accessType is 'read'
      readWriteDiv.textContent = "(R)"
      readWriteDiv.title = "This line read from a shared location."
    else
      readWriteDiv.textContent = "(W)"
      readWriteDiv.title = "This line wrote to a shared location."
    codeLineDiv.appendChild(readWriteDiv)
    filenameDiv = document.createElement('div')
    DetailCodeView.attachFileOpenListener(filenameDiv, lineInfo.filename, originalLineNum) if originalLineNum isnt '??'
    filenameDiv.classList.add('filename-line-number')
    filenameDiv.textContent = "#{filename}:#{originalLineNum}"
    lineNumberDiv = document.createElement('div')
    lineNumberDiv.classList.add('line-number')
    DetailCodeView.attachFileOpenListener(lineNumberDiv, lineInfo.filename,originalLineNum) if originalLineNum isnt '??'
    lineNumberDiv.innerHTML = "<code class='highlighted'>#{originalLineNum}</code>"
    codeLineDiv.appendChild(lineNumberDiv)

    #### Text Editor

    lineEditor = @createMiniEditorWithCode(lineCode.trim())
    lineEditorView = atom.views.getView(lineEditor)

    editorContainer = document.createElement('div')
    editorContainer.classList.add('editor-container')
    if originalLineNum isnt '??'
      editorOverlay = document.createElement('div')
      editorOverlay.classList.add('editor-overlay')
      editorContainer.appendChild(editorOverlay)
      editorOverlay.title = "Click to go to line."
      DetailCodeView.attachFileOpenListener(editorOverlay, lineInfo.filename, originalLineNum)
      $(editorOverlay).mousemove((e) ->
        e.stopPropagation()
      )
    editorContainer.appendChild(lineEditorView)

    codeLineDiv.appendChild(filenameDiv)
    codeLineDiv.appendChild(editorContainer)
    divToAdd.appendChild(codeLineDiv)

    if stacktrace?
      stacktraceDiv = document.createElement('div')
      stacktraceDiv.classList.add('stacktrace-container')
      for file in Object.getOwnPropertyNames(stacktrace)
        console.log(stacktrace[file])
        console.log(stacktrace[file].length)

        for i in [0 ... stacktrace[file].length]
          st = stacktrace[file][i]
          stacktraceHolder = document.createElement('div')
          stacktraceHolder.classList.add('stacktrace-holder')
          firstLineDiv = document.createElement('div')
          firstLineDiv.classList.add('stacktrace-line', 'first')
          stacktraceHolder.appendChild(firstLineDiv)
          firstLineDiv.innerHTML = "called by: <span class='entity name function c'>#{st[0].functionName}</span> (<span class='stacktrace-line-ref'>#{st[0].filename}:#{st[0].lineNum}</span>)"
          stacktraceLocationSpan = firstLineDiv.children[1]
          DetailCodeView.attachFileOpenListener(stacktraceLocationSpan, st[0].rawFilename, st[0].lineNum)

          additionalInfoContainer = document.createElement('div')
          additionalInfoContainer.classList.add('additional-stacktrace')
          html = ""
          st.slice(1).forEach((item) ->
            html += "\t<span class='entity name function c'>#{item.functionName}</span> (<span class='stacktrace-line-ref'>#{item.filename}:#{item.lineNum}</span>)\n"
          )
          additionalInfoContainer.innerHTML = html.slice(0, -1)
          for i in [1 ... additionalInfoContainer.children.length] by 2
            stacktraceIndex = Math.ceil(i / 2)
            DetailCodeView.attachFileOpenListener(additionalInfoContainer.children[i], st[stacktraceIndex].rawFilename, st[stacktraceIndex].lineNum)

          if st.length > 1
            additionalInfoButton = document.createElement('div')
            stacktraceHolder.appendChild(additionalInfoButton)
            additionalInfoButton.classList.add('full-stacktrace-button')
            additionalInfoButton.textContent = "(see full stack trace)"

            $(additionalInfoButton).click((e) =>
              console.log("Toggled the stacktrace.")
              $(additionalInfoContainer).toggleClass('clicked')
              if $(additionalInfoContainer).hasClass('clicked')
                additionalInfoButton.textContent = "(hide full stack trace)"
              else
                additionalInfoButton.textContent = "(see full stack trace)"
            )

            stacktraceHolder.appendChild(additionalInfoContainer)
          stacktraceDiv.appendChild(stacktraceHolder)
      divToAdd.appendChild(stacktraceDiv)

    return divToAdd

  createMiniEditorWithCode: (code) ->
    lineEditor = @constructTextEditor({ mini: true })
    lineEditor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
    lineEditorView = atom.views.getView(lineEditor)
    lineEditorView.removeAttribute('tabindex')
    lineEditor.setText(code)
    lineEditor.getDecorations({class: 'cursor-line', type: 'line'})[0].destroy()
    return lineEditor

  constructTextEditor: (params) ->
    if atom.workspace.buildTextEditor?
      lineEditor = atom.workspace.buildTextEditor(params)
    else
      TextEditor ?= require("atom").TextEditor
      lineEditor= new TextEditor(params)
    return lineEditor

  parseStacktrace: (stacktrace) ->
    console.log("In parseStacktrace")
    for file in Object.getOwnPropertyNames(stacktrace)
      console.log(stacktrace[file])
      console.log(stacktrace[file].length)
      for i in [0 ... stacktrace[file].length]
        console.log("Doing #{i}")
        stacktrace[file][i] = stacktrace[file][i].map(
          (item) ->
            paren = item.indexOf('(')
            comma = item.indexOf(',')
            rawFilename = item.slice(paren + 1, comma)
            lineNumDelim = rawFilename.indexOf(':')
            lineNum = rawFilename.slice(lineNumDelim + 1)
            rawFilename = rawFilename.slice(0, lineNumDelim)
            functionName = item.slice(comma + 2, item.length - 1)
            filenamePath = rawFilename.split('/')
            filename = filenamePath[filenamePath.length - 1]
            functionName = functionName.split('+')[0]
            return {rawFilename: rawFilename, filename: filename, functionName: functionName, lineNum: lineNum}
        )

      isEquals = (o1, o2) ->
        if o1.length is o2.length and o1.length > 0
          for i in [0 ... o1.length]
            for attr in Object.getOwnPropertyNames(o1)
              if o1[i][attr] isnt o2[i][attr]
                return false
          return true
        else
          return true

      stSet = new CustomSet(isEquals)
      stSet.add(stacktrace[file])
      stacktrace[file] = stSet.getContents()
    return stacktrace

  @attachFileOpenListener: (node, filename, lineNum) ->
    $(node).click((e) ->
      console.log("Clicked on a file open div: #{node.classList}")
      atom.workspace.open(filename, {initialLine: +lineNum - 1, initialColumn: Infinity})
      e.stopPropagation()
    )

  parseAbsolutePathname: (filename) ->
    splitName = filename.split('/')
    return splitName[splitName.length - 1]

  getElement: () ->
    return @element
