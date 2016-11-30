$ = require('jquery')
{CompositeDisposable} = require('atom')

FileLineReader = require('../utils/file-reader')
DetailCodeView = require('./detail-code-view')
MinimapView = require('../utils/minimap')
{MinimapUtil, normalizePath} = require('../utils/utils')
SVG = require('../utils/svg')
Debug = require('../utils/debug')

module.exports =
class CilkscreenPluginView
  element: null
  subscriptions: null
  violationContainer: null
  violationContentWrapper: null

  minimapContainer: null
  minimaps: null
  minimapIndex: null

  currentMinimap: null

  # Properties from parents
  props: null
  highlightCallback: null
  path: null

  HALF_CONTEXT: 2

  constructor: (props) ->
    @props = props
    @highlightCallback = props.highlightCallback
    @path = props.path

    @subscriptions = new CompositeDisposable()

    # Create root element
    @element = document.createElement('div')
    @element.classList.add('cilkscreen-detail-view', 'table')

    violationWrapper = document.createElement('div')
    violationWrapper.classList.add('violation-wrapper')

    violationContentWrapper = document.createElement('div')
    @violationContentWrapper = violationContentWrapper
    violationContentWrapper.classList.add('violation-content-wrapper')
    violationContentWrapper.classList.add('visual')
    minimapResizeDiv = document.createElement('div')
    minimapResizeDiv.classList.add('minimap-resize-div')
    violationContentWrapper.appendChild(minimapResizeDiv)
    $(minimapResizeDiv).on('mousedown', @horizontalResizeStart)
    violationWrapper.appendChild(violationContentWrapper)

    @minimapContainer = document.createElement('div')
    @minimapContainer.classList.add('minimap-container')
    minimapEmptyViolationDiv = document.createElement('ul')
    minimapEmptyViolationDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "No results yet. Save a file to start cilksan."
    minimapEmptyViolationDiv.appendChild(backgroundMessage)
    @minimapContainer.appendChild(minimapEmptyViolationDiv)
    violationWrapper.appendChild(@minimapContainer)

    @violationContainer = document.createElement('div')
    @violationContainer.classList.add('violation-container')
    emptyViolationDiv = document.createElement('ul')
    emptyViolationDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "Detected race conditions are shown here. None right now!"
    emptyViolationDiv.appendChild(backgroundMessage)
    @violationContainer.appendChild(emptyViolationDiv)
    violationContentWrapper.appendChild(@violationContainer)

    @element.appendChild(violationWrapper)

    @subscriptions.add(atom.workspace.onDidChangeActivePaneItem(() =>
      return if not editorPath = atom.workspace.getActiveTextEditor()?.getPath()

      if @minimaps and @minimaps[normalizePath(editorPath)]
        @minimaps[normalizePath(editorPath)].init(atom.workspace.getActiveTextEditor())
    ))

  horizontalResizeStart: () =>
    # Debug.log("Horizontal resize start")
    $(document).on('mousemove', @horizontalResizeMove)
    $(document).on('mouseup', @horizontalResizeStop)

  horizontalResizeStop: () =>
    # Debug.log("Horizontal resize stop")
    $(document).off('mousemove', @horizontalResizeMove)
    $(document).off('mouseup', @horizontalResizeStop)

  horizontalResizeMove: (event) =>
    return @horizontalResizeStop() unless event.which is 1

    element = $(@violationContentWrapper)
    # Debug.log("Horizontal resize move")
    width = element.offset().left + element.outerWidth() - event.pageX
    element.width(width)

  update: (violations) ->
    Debug.log("updating plugin view: start")
    Debug.log(violations)

    if violations.length
      @createViolationDivs(violations)
    else
      @createEmptyBackgroundMessage()

  createEmptyBackgroundMessage: () ->
    @clearChildren()

    minimapEmptyViolationDiv = document.createElement('ul')
    minimapEmptyViolationDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "Nothing to display!"
    minimapEmptyViolationDiv.appendChild(backgroundMessage)
    @minimapContainer.appendChild(minimapEmptyViolationDiv)

    emptyViolationDiv = document.createElement('ul')
    emptyViolationDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "No reported race conditions."
    emptyViolationDiv.appendChild(backgroundMessage)
    @violationContainer.appendChild(emptyViolationDiv)

  updateMinimap: (editor) ->
    Debug.log("updateMinimap called with editor: ")
    Debug.log(editor)
    Debug.log(@minimaps)
    if @minimaps and @minimaps[normalizePath(editor.getPath())]
      @minimaps[normalizePath(editor.getPath())].init(editor)
      Debug.log("updating minimap @ updateMinimap")
    else
      Debug.log("not updating @ updateMinimap 1")

  createViolationDivs: (augmentedViolations) ->
    Debug.log("createViolationDivs: called with ")
    Debug.log(augmentedViolations)

    @clearChildren()
    @currentMinimap = 0

    @minimapOverlay = SVG.createSVGObject(0, 32)
    @minimapOverlay.classList.add('minimap-canvas-overlay')
    # @minimapContainer.appendChild(@minimapOverlay)
    $(@minimapOverlay).click((e) =>
      @minimapOnClick(e)
    )

    # TODO: figure out a better way to store the visual stuff here
    @minimaps = {}
    @minimapIndex = {}
    minimapPromises = []
    minimapLineContainer = document.createElement('div')
    minimapLineContainer.classList.add('minimap-canvas-line-container')
    @minimapContainer.appendChild(minimapLineContainer)
    for index in [0 ... augmentedViolations.length]
      violation = augmentedViolations[index]
      violationView = new DetailCodeView({
        index: index,
        violation: violation,
        onViolationClickCallback: ((e, index) => @highlightCallback(e, index, false))
      })
      @violationContainer.appendChild(violationView.getElement())
      violation.minimapMarkers = []

      @createMinimapForLine(violation, violation.line1, minimapPromises, minimapLineContainer)
      @createMinimapForLine(violation, violation.line2, minimapPromises, minimapLineContainer)

      do (index) =>
        for marker in violation.minimapMarkers
          $(marker).on('click', (e) =>
            @highlightCallback(e, +index, true)
          )

    # if @toggleVisual
    #   Promise.all(minimapPromises).then(() =>
    #     Debug.log("All promises done!")
    #     Debug.log(@minimaps)
    #     Debug.log(Object.getOwnPropertyNames(@minimaps))
    #     maxHeight = -1
    #     minimaps = Object.getOwnPropertyNames(@minimaps)
    #     for minimap in minimaps
    #       height = @minimaps[minimap].getHeight()
    #       Debug.log("looking at: #{height} height")
    #       if maxHeight < height
    #         maxHeight = height
    #     @minimapOverlay.style.height = maxHeight + "px"
    #     @minimapOverlay.style.width = (minimaps.length * 240) + "px"
    #     @minimapOverlay.height = maxHeight
    #     @minimapOverlay.width = (minimaps.length * 240)
    #
    #     for index in [0 ... augmentedViolations.length]
    #       @drawViolationConnector(augmentedViolations[index], index)
    #   )

  createMinimapForLine: (violation, violationLine, minimapPromises, minimapLineContainer) ->
    if violationLine.filename and violationLine.line
      if not @minimaps[violationLine.filename]
        @minimaps[violationLine.filename] = new MinimapView({filename: violationLine.filename, path: @path})
        # minimapPromises.push(@minimaps[violation.line1.filename].init())
        @minimaps[violationLine.filename].init()
        @minimapIndex[violationLine.filename] = @currentMinimap
        @currentMinimap += 1
        @minimapContainer.appendChild(@minimaps[violationLine.filename].getElement())
      @minimaps[violationLine.filename].addDecoration(violationLine.line)
      lineOverlay = document.createElement('div')
      lineOverlay.classList.add('minimap-line-overlay')
      lineOverlay.style.top = (MinimapUtil.getLineTop(violationLine.line)) + "px"
      lineOverlay.style.left = (MinimapUtil.getLeftSide(@minimapIndex[violationLine.filename])) + "px"
      minimapLineContainer.appendChild(lineOverlay)
      DetailCodeView.attachFileOpenListener(lineOverlay, violationLine.filename, violationLine.line)

      # Create a marker next to the minimap as well
      Debug.log("[cilkscreen-plugin-view] Adding markers")
      marker = document.createElement('div')
      marker.classList.add('icon', 'alert', 'cilksan-marker')
      marker.style.top = (MinimapUtil.getLineTop(violationLine.line, -8)) + "px"
      marker.style.left = (MinimapUtil.getLeftSide(@minimapIndex[violationLine.filename], -15)) + "px"
      minimapLineContainer.appendChild(marker)
      violation.minimapMarkers.push(marker)

  minimapOnClick: (e) ->
    rect = @minimapOverlay.getBoundingClientRect();
    left = Math.round(e.pageX - rect.left)
    top = Math.round(e.pageY - rect.top)
    Debug.log("clicked: left: #{e.pageX - rect.left}, top: #{e.pageY - rect.top}")
    violationId = e.target.getAttribute('violation-id')
    Debug.log("clicked on id: #{violationId}")
    if violationId
      @highlightCallback(e, +violationId, true)
    else
      e.stopPropagation()

  drawViolationConnector: (violation, index) ->
    DEBUG = false
    Debug.log("Drawing violation connector.") if DEBUG
    Debug.log(violation) if DEBUG

    if not violation.line1.filename or not violation.line2.filename
      return

    # The violation is within the same file, so we'll have to draw a curved line.
    if violation.line1.filename is violation.line2.filename
      Debug.log(@minimapIndex) if DEBUG
      Debug.log(@minimapIndex[violation.line1.filename]) if DEBUG
      startX = MinimapUtil.getLeftSide(@minimapIndex[violation.line1.filename])
      line1Y = MinimapUtil.getLineTop(violation.line1.line)
      line2Y = MinimapUtil.getLineTop(violation.line2.line)
      SVG.addSVGCurve(@minimapOverlay, "#{index}", startX, line1Y, startX, line2Y)
    # Otherwise draw a straight line.
    else
      startX = 0
      endX = 0
      if @minimapIndex[violation.line1.filename] > @minimapIndex[violation.line2.filename]
        startX = MinimapUtil.getLeftSide(@minimapIndex[violation.line1.filename]) - 2
        endX = MinimapUtil.getRightSide(@minimapIndex[violation.line2.filename]) + 2
      else
        startX = MinimapUtil.getRightSide(@minimapIndex[violation.line1.filename]) + 2
        endX = MinimapUtil.getLeftSide(@minimapIndex[violation.line2.filename]) - 2
      line1Y = MinimapUtil.getLineTop(violation.line1.line)
      line2Y = MinimapUtil.getLineTop(violation.line2.line)
      Debug.log("Drawing a curve from #{startX},#{line1Y} to #{endX}, #{line2Y}") if DEBUG
      SVG.addSVGLine(@minimapOverlay, "#{index}", startX, line1Y, endX, line2Y)

  highlightViolation: (index, shouldScroll) ->
    Debug.log("Clicked on a highlight violation for index #{index}")

    Debug.log("Highlighting violation: #{index}")
    if not @violationContainer.children[index]
      Debug.log("Uh oh, current violation not found but highlightViolation triggered")
    else
      Debug.log($("[violation-id=#{index}]"))
      @setHighlight(index)
      if shouldScroll
        @scrollToViolation(index)

  resetHighlight: (index) ->
    Debug.log("resetHighlight: #{index}")
    Debug.log(@violationContainer.children)

    return if index is null
    violationDiv = @violationContainer.children[index]
    violationDiv.classList.remove('highlighted')
    $("[violation-id=#{index}-visible]").css("stroke", "#ff0000")

  setHighlight: (index) ->
    violationDiv = @violationContainer.children[index]
    violationDiv.classList.add('highlighted')
    $("[violation-id=#{index}-visible]").css("stroke", "#ffff00")

  setViolations: (violations) ->
    @update(violations)

  scrollToViolation: (index) ->
    Debug.log("Trying to scroll to index #{index}")
    violationTop = @violationContainer.children[index].offsetTop
    @violationContainer.scrollTop = violationTop - 10

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  clearChildren: () ->
    Debug.log("Clearing children...")

    $(@violationContainer).empty()
    $(@minimapContainer).empty()

  # Tear down any state and detach
  destroy: ->
    Debug.log("Destroying plugin view")
    @element.remove()

  getElement: () ->
    return @element
