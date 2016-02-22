TextEditor = null
$ = require('jquery')

module.exports =
class DetailCodeView
  element: null
  violation: null

  constructor: (augmentedViolation) ->
    @violation = augmentedViolation
    @element = @createViolationView(@violation)

  createViolationView: (violation) ->
    violationView = document.createElement('div')
    violationView.classList.add('violation-div')

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
    $(filenameDiv).click((e) ->
      atom.workspace.open(lineInfo.filename, {initialLine: +originalLineNum - 1})
    )
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
      if lineNum is originalLineNum
        lineNumberDiv.innerHTML = "<code class='highlighted'>#{lineNum}</code>"
      else
        lineNumberDiv.innerHTML = "<code>#{lineNum}</code>"
      lineNumberContainer.appendChild(lineNumberDiv)

    lineEditor = @constructTextEditor({ mini: true })
    lineEditorView = atom.views.getView(lineEditor)
    lineEditorView.removeAttribute('tabindex')
    lineEditor.setText(lineCode)
    lineEditor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
    lineEditor.getDecorations({class: 'cursor-line', type: 'line'})[0].destroy()

    editorCell = document.createElement('td')
    editorCell.appendChild(lineEditorView)
    codeRow.appendChild(editorCell)

    stacktraceDiv = document.createElement('div')
    stacktraceDiv.classList.add('stacktrace-container')
    if stacktrace?
      firstLineDiv = document.createElement('div')
      firstLineDiv.classList.add('stacktrace-line')
      firstLineDiv.classList.add('first')
      stacktraceDiv.appendChild(firstLineDiv)
      firstLineDiv.innerHTML = "called by: <span class='entity name function c'>#{stacktrace[0][1]}</span> (#{stacktrace[0][0]})"
      additionalInfoButton = document.createElement('div')
      stacktraceDiv.appendChild(additionalInfoButton)
      additionalInfoButton.classList.add('full-stacktrace-button')
      additionalInfoButton.textContent = "(see full stack trace)"

      additionalInfoContainer = document.createElement('div')
      stacktraceDiv.appendChild(additionalInfoContainer)
      additionalInfoContainer.classList.add('additional-stacktrace')
      html = ""
      stacktrace.slice(1).forEach((item) ->
        html += "\t<span class='entity name function c'>#{item[1]}</span> (#{item[0]})\n"
      )
      additionalInfoContainer.innerHTML = html.slice(0, -1)

      $(additionalInfoButton).click((e) =>
        console.log("Hello world!")
        $(additionalInfoContainer).toggleClass('clicked')
        if $(additionalInfoContainer).hasClass('clicked')
          additionalInfoButton.textContent = "(hide full stack trace)"
        else
          additionalInfoButton.textContent = "(see full stack trace)"
      )

    else
      stacktraceDiv.classList.add('empty')
      stacktraceDiv.textContent = "(no stack trace available for this access)"

    divToAdd.appendChild(codeContainer)
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
      filename = item.slice(paren + 1, comma)
      functionName = item.slice(comma + 2, item.length - 1)
      filenamePath = filename.split('/')
      filename = filenamePath[filenamePath.length - 1]
      functionName = functionName.split('+')[0]
      return [filename, functionName]
    )

  getElement: () ->
    return @element
