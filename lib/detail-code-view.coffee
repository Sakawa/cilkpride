module.exports =
class DetailCodeView
  displayCode: null
  filename: null
  element: null

  constructor: (augmentedViolation) ->

    return
    for i in [0 .. violations.length - 1]
      violation = violations[i]
      divToAdd = document.createElement('div')
      FileLineReader.readLineNumBatch([[violation.line1.file, [violation.line1.line - 2, violation.line1.line + 2], () -> ]])
      for editor in atom.workspace.getTextEditors()
        console.log("Looking at text editor with path #{editor.getPath()}")
        if editor.getPath() is violation.line1.file
          line1Code = editor.lineTextForBufferRow(violation.line1.line - 1)
          line2Code = editor.lineTextForBufferRow(violation.line1.line - 2)
          line1Html = @highlighter.highlightSync({
              fileContents: line1Code,
              scopeName: 'source.c',
          })

          lineNumber = document.createElement('div')
          lineNumber.classList.add('line-number')
          lineNumber.textContent = violation.line1.line

          codeContainer = document.createElement('table')
          codeRow = document.createElement('tr')
          lineNumberCell = document.createElement('td')
          lineNumberContainer = document.createElement('div')
          codeContainer.classList.add('code-container')
          codeRow.appendChild(lineNumberCell)
          codeContainer.appendChild(codeRow)
          lineNumberContainer.classList.add('line-number-container')
          lineNumberCell.appendChild(lineNumberContainer)
          lineNum = 35
          for i in [-2..-1]
            lineNumberDiv = document.createElement('div')
            lineNumberDiv.classList.add('line-number')
            lineNumberDiv.innerHTML = "<code>#{lineNum + i}</code>"
            lineNumberContainer.appendChild(lineNumberDiv)

          params = { mini: true }
          if atom.workspace.buildTextEditor?
            lineEditor = atom.workspace.buildTextEditor(params)
          else
            TextEditor ?= require("atom").TextEditor
            lineEditor= new TextEditor(params)

          lineEditorView = atom.views.getView(lineEditor)
          # lineEditorView = document.createElement('atom-text-editor')
          lineEditorView.removeAttribute('tabindex')
          # lineEditor = lineEditorView.getModel()
          # @subscriptions.add(lineEditor.onDidStopChanging(() ->
          #   console.log("Line editor did change.")
          #   lineNumberElements = lineEditorView.rootElement.querySelectorAll('.line-number')
          #   console.log(lineNumberElements)
          #   console.log(lineEditorView)
          #   # TODO : Doesn't work for large line numbers
          #   for lineNumberElement in lineNumberElements
          #     console.log("Line Number Element: ")
          #     console.log(lineNumberElement)
          #     row = parseInt(lineNumberElement.getAttribute('data-buffer-row'), 10)
          #     relative = row + violation.line1.line - 3
          #     lineNumberElement.setAttribute('data-buffer-row', relative)
          #     console.log(row)
          #     console.log(relative)
          #     console.log lineNumberElement.innerHTML
          #     lineNumberElement.innerHTML = "#{relative}<div class=\"icon-right\"></div>"
          # ))
          lineEditor.setText(line2Code + "\n" + line1Code)
          lineEditor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
          lineEditor.getDecorations({class: 'cursor-line', type: 'line'})[0].destroy()
          console.log(lineEditor)

          divToAdd.appendChild(lineNumber)
          editorCell = document.createElement('td')
          editorCell.appendChild(lineEditorView)
          codeRow.appendChild(editorCell)
          divToAdd.appendChild(codeContainer)

          console.log("Getting line 1: #{line1Html}")
          console.log("Line Editor Height")
          console.log($(lineEditorView).height())
        if editor.getPath() is violation.line2.file
          line2Code = editor.lineTextForBufferRow(violation.line2.line - 1)
          console.log("Getting line 2: #{editor.lineTextForBufferRow(violation.line2.line - 1)}")

      divToAdd.appendChild(@generateTextDiv(violation.location))
      divToAdd.appendChild(@generateTextDiv(violation.line1.raw))
      divToAdd.appendChild(@generateTextDiv(violation.line2.raw))
      for trace in violation.stacktrace
        divToAdd.appendChild(@generateTextDiv(trace))
      divs.push(divToAdd)
    return divs

  getElement: () ->
    return @element
