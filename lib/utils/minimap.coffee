TextEditor = null
FileLineReader = require('./file-reader')
$ = require('jquery')
{CompositeDisposable} = require('atom')
{normalizePath} = require('../utils/utils')
path = require('path').posix
Debug = require('./debug')

NUM_PIXELS_PER_LINE = 6

module.exports =
class Minimap
  element: null
  minimapElement: null
  minimap: null
  minimapOverlay: null
  minimapContainer: null

  editor: null
  decorationQueue: null
  promise: null

  ready: false
  destroyed: false
  currentId: 0

  subscriptions: null

  # Properties from parent
  props: null
  filename: null
  projectPath: null

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
        $(@minimapOverlay).click((e) =>
          @minimapOnClick(e)
        )

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
        marker = @editor.markBufferRange(range, {id: 'cilkscreen-minimap'})
        @minimap.decorateMarker(marker, {type: 'line', scope: '.cilkscreen .minimap-marker', plugin: "cilkscreen", color: "#961B05"})
      @ready = true
      Debug.log("#{@filename} minimap ready")

      minimapView = atom.views.getView(@minimap)
      minimapView.requestForcedUpdate()
      Debug.log(minimapView)
      Debug.log(minimapView.shadowRoot)
      Debug.log(minimapView.shadowRoot.children[0])
    )


  minimapOnClick: (e) ->
    # rect = @minimapOverlay.getBoundingClientRect();
    # parentTop = @minimapOverlay.offsetTop
    # parentLeft = @minimapOverlay.offsetLeft
    # left = Math.round(e.pageX - rect.left)
    # top = Math.round(e.pageY - rect.top)
    # Debug.log("clicked: left: #{e.pageX - rect.left}, top: #{e.pageY - rect.top}")
    # violationId = e.target.getAttribute('violation-id')
    # Debug.log("clicked on id: #{violationId}")

    # if violationId
    #   @highlightViolation(e, +violationId, true)
    # else
    #   e.stopPropagation()

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
      marker = @editor.markBufferRange(range, {id: 'cilkscreen-minimap'})
      @minimap.decorateMarker(marker, {type: 'line', scope: '.cilkscreen .minimap-marker', plugin: "cilkscreen", color: "#961B05"})

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
