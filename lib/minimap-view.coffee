TextEditor = null
FileLineReader = require('./file-read-lines')
$ = require('jquery')

NUM_PIXELS_PER_LINE = 6

module.exports =
class MinimapView
  element: null
  ready: false
  editor: null
  minimap: null
  decorationQueue: null

  # Properties from parent
  props: null
  filename: null

  constructor: (props) ->
    @props = props
    @filename = props.filename

    @element = document.createElement('div')
    @element.classList.add('cs-minimap-element')

    filenameDiv = document.createElement('div')
    filenameDiv.classList.add('cs-minimap-filename')
    splitPath = @filename.split('/')
    filenameDiv.textContent = splitPath[splitPath.length - 1]
    @element.appendChild(filenameDiv)
    $(filenameDiv).click((e) =>
      console.log("Clicked on a file open div: #{filenameDiv.classList}")
      atom.workspace.open(@filename, {initialLine: 0, initialColumn: Infinity})
    )

    @decorationQueue = []

  init: () ->
    console.log("init started for #{@filename} minimap")
    promise = new Promise((resolve, reject) =>
      data = FileLineReader.readFile(@filename)
      @buildMinimap(resolve, data)
    )
    promise.then(() =>
      console.log("#{@filename} minimap init promise returned")
      console.log(@decorationQueue)
      for range in @decorationQueue
        marker = @editor.markBufferRange(range, {id: 'cilkscreen-minimap'})
        @minimap.decorateMarker(marker, {type: 'line', scope: '.cilkscreen .minimap-marker', plugin: "cilkscreen", color: "#961B05"})
      @ready = true
      console.log("#{@filename} minimap ready")

      minimapView = atom.views.getView(@minimap)
      minimapView.requestForcedUpdate()
      console.log(minimapView)
      console.log(minimapView.shadowRoot)
      console.log(minimapView.shadowRoot.children[0])
    )
    return promise

  buildMinimap: (resolve, data) ->
    editor = @constructTextEditor({ mini: false })
    @editor = editor
    editor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
    editor.setText(data)
    numLines = data.split('\n').length
    atom.packages.serviceHub.consume('minimap', '1.0.0', (api) =>
      @minimap = api.standAloneMinimapForEditor(editor)
      @minimap.setCharHeight(3)
      @minimap.setCharWidth(3)
      minimapElement = atom.views.getView(@minimap)
      minimapElement.attach(@element)
      minimapElement.setDisplayCodeHighlights(true)
      minimapElement.style.cssText = """
        width: 200px;
        position: relative;
        z-index: 10;
      """
      minimapElement.style.height = "#{numLines * @minimap.getLineHeight()}px"
      console.log(@minimap.getLineHeight())
      resolve()
    )

  constructTextEditor: (params) ->
    if atom.workspace.buildTextEditor?
      lineEditor = atom.workspace.buildTextEditor(params)
    else
      TextEditor ?= require("atom").TextEditor
      lineEditor= new TextEditor(params)
    return lineEditor

  addDecoration: (line) ->
    range = [[line - 1, 0], [line - 1, Infinity]]
    if not @ready
      console.log("#{@filename} minimap not ready for decoration, adding to queue")
      @decorationQueue.push(range)
    else
      console.log("#{@filename} minimap ready for decoration, adding directly")
      marker = @editor.markBufferRange(range, {id: 'cilkscreen-minimap'})
      @minimap.decorateMarker(marker, {type: 'line', scope: '.cilkscreen .minimap-marker', plugin: "cilkscreen", color: "#961B05"})

  getElement: () ->
    return @element

  getFilename: () ->
    return @filename

  getHeight: () ->
    return @minimap.getScreenHeight()
