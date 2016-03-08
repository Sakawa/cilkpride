TextEditor = null
FileLineReader = require('./file-read-lines')

NUM_PIXELS_PER_LINE = 3

module.exports =
class MinimapView
  element: null
  minimap: null

  # Properties from parent
  props: null
  filename: null

  constructor: (props) ->
    @props = props
    @filename = props.filename

    @element = document.createElement('div')
    @element.classList.add('cs-minimap-element')

    filenameDiv = document.createElement('div')
    splitPath = @filename.split('/')
    filenameDiv.textContent = splitPath[splitPath.length - 1]
    @element.appendChild(filenameDiv)

    data = FileLineReader.readFile(@filename)
    @buildMinimap(data)

  buildMinimap: (data) ->
    editor = @constructTextEditor({ mini: false })
    console.log(data)
    editor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
    editor.setText(data)
    numLines = data.split('\n').length
    atom.packages.serviceHub.consume('minimap', '1.0.0', (api) =>
      @minimap = api.standAloneMinimapForEditor(editor)
      minimapElement = atom.views.getView(@minimap)
      minimapElement.attach(@element)
      minimapElement.setDisplayCodeHighlights(true)
      minimapElement.style.cssText = """
        width: 300px;
        position: relative;
        z-index: 10;
      """
      minimapElement.style.height = "#{numLines * NUM_PIXELS_PER_LINE}px"
    )

  constructTextEditor: (params) ->
    if atom.workspace.buildTextEditor?
      lineEditor = atom.workspace.buildTextEditor(params)
    else
      TextEditor ?= require("atom").TextEditor
      lineEditor= new TextEditor(params)
    return lineEditor

  addDecoration: (marker) ->
    @minimap.decorateMarker(marker, {type: 'line', scope: '.cilkscreen .minimap-marker'})

  getElement: () ->
    return @element

  getFilename: () ->
    return @filename
