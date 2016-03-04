TextEditor = null
$ = require('jquery')
MinimapView = require('./minimap-view')

VERBS_PT = {
  "read": "read",
  "write": "written"
}

module.exports =
class DetailCodeView
  element: null
  violation: null
  onViolationClickCallback: null

  constructor: (augmentedViolation, onViolationClickCallback) ->
    @violation = augmentedViolation
    @element = @createVisualViolationView(@violation)
    @onViolationClickCallback = onViolationClickCallback

  createVisualViolationView: (violation) ->
    violationView = document.createElement('div')
    violationView.classList.add('violation-div')
    violationView.classList.add('visual')
    $(violationView).click((e) =>
      @onViolationClickCallback(violationView)
    )
    violationView.appendChild(@constructVisualPreview(violation.line1, violation.violation.line1.type, null, true))
    violationView.appendChild(@constructVisualPreview(violation.line2, violation.violation.line2.type, @parseStacktrace(violation.violation.stacktrace), false))

    return violationView

  createViolationView: (violation) ->
    violationView = document.createElement('div')
    violationView.classList.add('violation-div')
    $(violationView).click((e) =>
      @onViolationClickCallback(violationView)
    )

    summaryDiv = document.createElement('div')
    summaryDiv.classList.add('summary-div')
    summaryDiv.textContent = "A variable was concurrently #{VERBS_PT[violation.violation.line1.type]} at #{@parseAbsolutePathname(violation.line1.filename)}:#{violation.violation.line1.line}, and #{VERBS_PT[violation.violation.line2.type]} at #{@parseAbsolutePathname(violation.line2.filename)}:#{violation.violation.line2.line}."
    violationView.appendChild(summaryDiv)

    violationView.appendChild(@constructCodePreview(violation.line1, null, true))
    violationView.appendChild(@constructCodePreview(violation.line2, @parseStacktrace(violation.violation.stacktrace), false))

    return violationView

  constructCodePreview: (lineInfo, stacktrace, isLeft) ->
    if stacktrace?
      console.log("Called constructCodePreview with stack trace: ")
      console.log(stacktrace)

    lineCode = lineInfo.text.join('\n')
    filenamePath = lineInfo.filename.split('/')
    filename = filenamePath[filenamePath.length - 1]
    minLineNum = lineInfo.lineRange[0]
    maxLineNum = lineInfo.lineRange[1]
    originalLineNum = minLineNum + 2

    divToAdd = document.createElement('div')
    divToAdd.classList.add('code-container-table')
    if not isLeft
      divToAdd.classList.add('right')
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

    for lineNum in [minLineNum ..maxLineNum]
      lineNumberDiv = document.createElement('div')
      lineNumberDiv.classList.add('line-number')
      DetailCodeView.attachFileOpenListener(lineNumberDiv, lineInfo.filename, lineNum)
      if lineNum is originalLineNum
        lineNumberDiv.innerHTML = "<code class='highlighted'>#{lineNum}</code>"
      else
        lineNumberDiv.innerHTML = "<code>#{lineNum}</code>"
      lineNumberContainer.appendChild(lineNumberDiv)

    #### Text Editor

    lineEditor = @constructTextEditor({ mini: true })
    lineEditorView = atom.views.getView(lineEditor)
    lineEditorView.removeAttribute('tabindex')
    lineEditor.setText(lineCode)
    lineEditor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
    lineEditor.getDecorations({class: 'cursor-line', type: 'line'})[0].destroy()

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
      firstLineDiv = document.createElement('div')
      firstLineDiv.classList.add('stacktrace-line')
      firstLineDiv.classList.add('first')
      stacktraceDiv.appendChild(firstLineDiv)
      firstLineDiv.innerHTML = "called by: <span class='entity name function c'>#{stacktrace[0].functionName}</span> (<span class='stacktrace-line-ref'>#{stacktrace[0].filename}:#{stacktrace[0].lineNum}</span>)"
      stacktraceLocation = firstLineDiv.children[1]
      DetailCodeView.attachFileOpenListener(stacktraceLocation, stacktrace[0].rawFilename, stacktrace[0].lineNum)

      additionalInfoContainer = document.createElement('div')
      additionalInfoContainer.classList.add('additional-stacktrace')
      html = ""
      stacktrace.slice(1).forEach((item) ->
        html += "\t<span class='entity name function c'>#{item.functionName}</span> (<span class='stacktrace-line-ref'>#{item.filename}:#{item.lineNum}</span>)\n"
      )
      additionalInfoContainer.innerHTML = html.slice(0, -1)
      for i in [0 .. additionalInfoContainer.children.length]
        if i % 2 is 0
          continue
        stacktraceIndex = Math.floor(i / 2) + 1
        DetailCodeView.attachFileOpenListener(additionalInfoContainer.children[i], stacktrace[stacktraceIndex].rawFilename, stacktrace[stacktraceIndex].lineNum)

      if stacktrace.length > 1
        additionalInfoButton = document.createElement('div')
        stacktraceDiv.appendChild(additionalInfoButton)
        additionalInfoButton.classList.add('full-stacktrace-button')
        additionalInfoButton.textContent = "(see full stack trace)"

        $(additionalInfoButton).click((e) =>
          console.log("Hello world!")
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

  constructVisualPreview: (lineInfo, type, stacktrace, isFirst) ->
    if stacktrace?
      console.log("Called constructVisualPreview with stack trace: ")
      console.log(stacktrace)
    console.log(lineInfo)

    lineCode = lineInfo.text[2]
    filenamePath = lineInfo.filename.split('/')
    filename = filenamePath[filenamePath.length - 1]
    minLineNum = lineInfo.lineRange[0]
    maxLineNum = lineInfo.lineRange[1]
    originalLineNum = minLineNum + 2

    divToAdd = document.createElement('div')
    divToAdd.classList.add('code-container-table')
    divToAdd.classList.add('visual-detail')
    if not isFirst
      divToAdd.classList.add('bottom')

    codeLineDiv = document.createElement('div')
    codeLineDiv.classList.add('code-line-container')
    readWriteDiv = document.createElement('div')
    readWriteDiv.classList.add('read-write-div')
    if type is 'read'
      readWriteDiv.textContent = "(R)"
      readWriteDiv.title = "read"
    else
      readWriteDiv.textContent = "(W)"
      readWriteDiv.title = "write"
    codeLineDiv.appendChild(readWriteDiv)
    filenameDiv = document.createElement('div')
    DetailCodeView.attachFileOpenListener(filenameDiv, lineInfo.filename, originalLineNum)
    filenameDiv.classList.add('filename-line-number')
    filenameDiv.textContent = "#{filename}:#{originalLineNum}"
    lineNumberDiv = document.createElement('div')
    lineNumberDiv.classList.add('line-number')
    DetailCodeView.attachFileOpenListener(lineNumberDiv, lineInfo.filename,originalLineNum)
    lineNumberDiv.innerHTML = "<code class='highlighted'>#{originalLineNum}</code>"
    codeLineDiv.appendChild(lineNumberDiv)

    #### Text Editor

    lineEditor = @constructTextEditor({ mini: true })
    lineEditor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
    lineEditorView = atom.views.getView(lineEditor)
    lineEditorView.removeAttribute('tabindex')
    lineEditor.setText(lineCode)
    lineEditor.getDecorations({class: 'cursor-line', type: 'line'})[0].destroy()

    editorContainer = document.createElement('div')
    editorContainer.classList.add('editor-container')
    DetailCodeView.attachFileOpenListener(editorContainer, lineInfo.filename, originalLineNum)
    editorContainer.appendChild(lineEditorView)

    codeLineDiv.appendChild(filenameDiv)
    codeLineDiv.appendChild(editorContainer)
    divToAdd.appendChild(codeLineDiv)

    if stacktrace?
      stacktraceDiv = document.createElement('div')
      stacktraceDiv.classList.add('stacktrace-container')
      firstLineDiv = document.createElement('div')
      firstLineDiv.classList.add('stacktrace-line')
      firstLineDiv.classList.add('first')
      stacktraceDiv.appendChild(firstLineDiv)
      firstLineDiv.innerHTML = "called by: <span class='entity name function c'>#{stacktrace[0].functionName}</span> (<span class='stacktrace-line-ref'>#{stacktrace[0].filename}:#{stacktrace[0].lineNum}</span>)"
      stacktraceLocation = firstLineDiv.children[1]
      DetailCodeView.attachFileOpenListener(stacktraceLocation, stacktrace[0].rawFilename, stacktrace[0].lineNum)

      additionalInfoContainer = document.createElement('div')
      additionalInfoContainer.classList.add('additional-stacktrace')
      html = ""
      stacktrace.slice(1).forEach((item) ->
        html += "\t<span class='entity name function c'>#{item.functionName}</span> (<span class='stacktrace-line-ref'>#{item.filename}:#{item.lineNum}</span>)\n"
      )
      additionalInfoContainer.innerHTML = html.slice(0, -1)
      for i in [0 .. additionalInfoContainer.children.length]
        if i % 2 is 0
          continue
        stacktraceIndex = Math.floor(i / 2) + 1
        DetailCodeView.attachFileOpenListener(additionalInfoContainer.children[i], stacktrace[stacktraceIndex].rawFilename, stacktrace[stacktraceIndex].lineNum)

      if stacktrace.length > 1
        additionalInfoButton = document.createElement('div')
        stacktraceDiv.appendChild(additionalInfoButton)
        additionalInfoButton.classList.add('full-stacktrace-button')
        additionalInfoButton.textContent = "(see full stack trace)"

        $(additionalInfoButton).click((e) =>
          console.log("Hello world!")
          $(additionalInfoContainer).toggleClass('clicked')
          if $(additionalInfoContainer).hasClass('clicked')
            additionalInfoButton.textContent = "(hide full stack trace)"
          else
            additionalInfoButton.textContent = "(see full stack trace)"
        )

        stacktraceDiv.appendChild(additionalInfoContainer)
      divToAdd.appendChild(stacktraceDiv)

    return divToAdd

  constructTextEditor: (params) ->
    if atom.workspace.buildTextEditor?
      lineEditor = atom.workspace.buildTextEditor(params)
    else
      TextEditor ?= require("atom").TextEditor
      lineEditor= new TextEditor(params)
    return lineEditor

  parseStacktrace: (stacktrace) ->
    return stacktrace.map((item) ->
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
