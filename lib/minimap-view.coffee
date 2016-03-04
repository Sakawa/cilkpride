TextEditor = null
FileLineReader = require('./file-read-lines')

module.exports =
class MinimapView
  minimap: null

  constructor: (div, filename) ->
    data = FileLineReader.readFile(filename)
    @buildMinimap(div, data, filename)

  buildMinimap: (div, data, filename) ->
    editor = @constructTextEditor({ mini: false })
    console.log(data)
    editor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
    editor.setText(data)
    atom.packages.serviceHub.consume('minimap', '1.0.0', (api) =>
      @minimap = api.standAloneMinimapForEditor(editor)
      minimapElement = atom.views.getView(@minimap)
      minimapElement.attach(div)
      minimapElement.setDisplayCodeHighlights(true)
      minimapElement.style.cssText = """
        width: 300px;
        height: 300px;
        position: relative;
        top: 0;
        right: 100px;
        z-index: 10;
      """
    )

  constructTextEditor: (params) ->
    if atom.workspace.buildTextEditor?
      lineEditor = atom.workspace.buildTextEditor(params)
    else
      TextEditor ?= require("atom").TextEditor
      lineEditor= new TextEditor(params)
    return lineEditor

  getElement: () ->
    return atom.views.getView(@minimap)
