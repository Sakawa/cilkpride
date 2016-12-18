###
Util class for creating a stand-alone minimap with overlay and decorations.
Mainly used for the visual view of CilksanModule, which gives users a view
of the files with race conditions in them.
###

$ = require('jquery')
{CompositeDisposable} = require('atom')
path = require('path').posix
TextEditor = null

Debug = require('./debug')
FileLineReader = require('./file-reader')
{normalizePath} = require('../utils/utils')

NUM_PIXELS_PER_LINE = 6

module.exports =
class Minimap
  element: null          # Element containing the minimap div
  minimapElement: null   # The Minimap view object from the minimap package
  minimap: null          # The Minimap model object from the minimap package
  minimapOverlay: null   # Element containing the minimap overlay
  minimapContainer: null # Element container for the minimap

  editor: null           # The text editor associated with the current minimap
  decorationQueue: null  # Queue for decorations while the minimap is initializing
  promise: null          # Promise for building the minimap using the minimap package

  ready: false           # Boolean - true if the minimap has finished initializing
  destroyed: false       # Boolean - true if the minimap has been destroyed and is no longer usable
  currentId: 0           # ID to keep track of the latest minimap request

  subscriptions: null    # CompositeDisposable for events related to editor tracking

  # Properties from parent
  props: null            # Object containing parent-specified properties
  filename: null         # Absolute filepath for the file that the minimap is visualizing
  projectPath: null      # Path of the Cilkpride project

  constructor: (props) ->
    @props = props
    @filename = props.filename
    @projectPath = props.path

    @element = document.createElement('div')
    @element.classList.add('cs-minimap-element')

    filenameDiv = document.createElement('div')
    filenameDiv.classList.add('cs-minimap-filename')
    filenameDiv.textContent = path.relative(@projectPath, @filename)
    @element.appendChild(filenameDiv)
    $(filenameDiv).click((e) =>
      Debug.log("Clicked on a file open div: #{filenameDiv.classList}")
      atom.workspace.open(@filename, {initialLine: 0, initialColumn: Infinity})
    )

    @minimapContainer = document.createElement('div')
    @minimapContainer.classList.add('cs-minimap-container')
    @element.appendChild(@minimapContainer)

    @subscriptions = new CompositeDisposable()

    @decorationQueue = []

  init: (editor) ->
    if editor is @editor
      return

    @currentId += 1
    @destroy()
    @editor = editor if editor
    Debug.log("[minimap] Normalized path: #{normalizePath(atom.workspace.getActiveTextEditor().getPath())}")
    @editor = atom.workspace.getActiveTextEditor() if normalizePath(atom.workspace.getActiveTextEditor().getPath()) is @filename
    if @editor
      Debug.log("init started for #{@filename} minimap for editor #{@editor.id} for filename #{@filename}")
    else
      Debug.log("init started for #{@filename} minimap for filename #{@filename}")
      data = FileLineReader.readFile(@filename)
      Debug.log("[minimap] reading data")
      Debug.log(data)
      hiddenEditor = @constructTextEditor({ mini: false })
      @editor = hiddenEditor
      @editor.setGrammar(atom.grammars.grammarForScopeName('source.c'))
      @editor.setText(data)

    @buildMinimap(@currentId)

  buildMinimap: (id) ->
    @promise = new Promise((resolve, reject) =>
      numLines = @editor.getLineCount()
      atom.packages.serviceHub.consume('minimap', '1.0.0', (api) =>
        # If there a new version of the minimap has been requested, just ignore it.
        if id isnt @currentId
          reject()

        @minimap = api.standAloneMinimapForEditor(@editor)
        @minimap.setCharHeight(3)
        @minimap.setCharWidth(3)
        @minimap.onDidChange((obj) ->
          Debug.log("minimap changed!")
          Debug.log(obj)
        )
        @minimap.onDidDestroy((obj) =>
          Debug.log("minimap destroyed!")
          @minimap = null
          return @init()
        )

        @minimapOverlay = document.createElement('div')
        @minimapOverlay.classList.add('minimap-overlay')
        @minimapContainer.appendChild(@minimapOverlay)

        textEditorElement = atom.views.getView(@editor)
        @subscriptions.add(textEditorElement.onDidChangeScrollTop((() => @updateScrollOverlay())))
        @subscriptions.add(atom.views.pollDocument((() => @updateScrollOverlay())))

        minimapElement = atom.views.getView(@minimap)
        minimapElement.attach(@minimapContainer)
        minimapElement.setDisplayCodeHighlights(true)
        minimapElement.style.cssText = "width: 150px; position: relative; z-index: 10;"

        height = numLines * @minimap.getLineHeight()
        minimapElement.style.height = "#{height}px"
        minimapElement.style.width = "150px"
        Debug.log(@minimap.getLineHeight())
        Debug.log(@minimap.getVerticalScaleFactor())
        Debug.log(@minimap.getScreenHeight())
        Debug.log(@minimap.getTextEditorScaledHeight())

        resolve()
      )
    )

    @promise = @promise.then(() =>
      Debug.log("#{@filename} minimap init promise returned")
      Debug.log(@decorationQueue)
      for range in @decorationQueue
        marker = @editor.markBufferRange(range)
        @minimap.decorateMarker(marker, {type: 'line', scope: '.cilksan .minimap-marker', plugin: "cilksan", color: "#961B05"})
      @ready = true
      Debug.log("#{@filename} minimap ready")

      minimapView = atom.views.getView(@minimap)
      minimapView.requestForcedUpdate()
      Debug.log(minimapView)
      Debug.log(minimapView.shadowRoot)
      Debug.log(minimapView.shadowRoot.children[0])
    )

  updateScrollOverlay: () ->
    # Debug.log(@minimap.getTextEditorScaledHeight())
    # Debug.log(@minimap.getTextEditorScaledScrollTop())
    # TODO: this is bad performance
    try
      @minimapOverlay.style.height = "#{@minimap.getTextEditorScaledHeight()}px"
      @minimapOverlay.style.top = "#{@minimap.getTextEditorScaledScrollTop()}px"
    catch
      @subscriptions.dispose()

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
      Debug.log("#{@filename} minimap not ready for decoration, adding to queue")
      @decorationQueue.push(range)
    else
      Debug.log("#{@filename} minimap ready for decoration, adding directly")
      @decorationQueue.push(range)
      marker = @editor.markBufferRange(range)
      @minimap.decorateMarker(marker, {type: 'line', scope: '.cilksan .minimap-marker', plugin: "cilksan", color: "#961B05"})

  getElement: () ->
    return @element

  getFilename: () ->
    return @filename

  getHeight: () ->
    return @minimap.getHeight()

  destroy: () ->
    @subscriptions.dispose()
    $(@minimapContainer).empty() if @minimapContainer
    @editor = null if @editor
    @minimap.destroy() if @minimap
    @minimap = null
    @minimapElement.destroy() if @minimapElement
    @minimapElement = null
    @destroyed = true
    @ready = false
