$ = require('jquery')
FileLineReader = require('./file-read-lines')
{CompositeDisposable} = require('atom')
DetailCodeView = require('./detail-code-view')
MinimapView = require('./minimap-view')
{MinimapUtil} = require('./utils')
SVG = require('./svg')

module.exports =
class CilkscreenPluginView
  element: null
  currentHighlightedIndex: null
  violationContainer: null
  minimapContainer: null
  minimaps: null
  minimapIndex: null

  violationMarkers: null

  # Properties from parents
  props: null
  onCloseCallback: null

  HALF_CONTEXT: 2

  constructor: (props) ->
    @props = props
    @onCloseCallback = props.onCloseCallback

    # Create root element
    @element = document.createElement('div')
    @element.classList.add('cilkscreen-detail-view', 'table')

    resizeDiv = document.createElement('div')
    resizeDiv.classList.add('cilkscreen-detail-resize')

    @element.appendChild(resizeDiv)
    $(resizeDiv).on('mousedown', @resizeStart)

    header = document.createElement('div')
    header.classList.add('header', 'table-row')
    title = document.createElement('div')
    title.classList.add('header-title')
    title.textContent = "Cilkscreen Detected Race Conditions"
    close = document.createElement('div')
    close.classList.add('header-close', 'icon', 'icon-x')
    $(close).on('click', (() => @onClosePanel()))
    header.appendChild(title)
    header.appendChild(close)

    @element.appendChild(header)

    violationWrapper = document.createElement('div')
    violationWrapper.classList.add('violation-wrapper', 'table-row')

    violationContentWrapper = document.createElement('div')
    violationContentWrapper.classList.add('violation-content-wrapper')
    # TODO: need a better way to switch visual/non-visual
    violationContentWrapper.classList.add('visual')
    violationWrapper.appendChild(violationContentWrapper)

    @minimapContainer = document.createElement('div')
    @minimapContainer.classList.add('minimap-container')
    violationWrapper.appendChild(@minimapContainer)

    @violationContainer = document.createElement('div')
    @violationContainer.classList.add('violation-container')
    violationContentWrapper.appendChild(@violationContainer)

    @element.appendChild(violationWrapper)

  resizeStart: () =>
    console.log("Resize start")
    $(document).on('mousemove', @resizeMove)
    $(document).on('mouseup', @resizeStop)

  resizeStop: () =>
    console.log("Resize stop")
    $(document).off('mousemove', @resizeMove)
    $(document).off('mouseup', @resizeStop)

  resizeMove: (event) =>
    return @resizeStop() unless event.which is 1

    element = $(@element)
    console.log("Resize move")
    height = element.offset().top + element.outerHeight() - event.pageY
    element.height(height)

  update: (violations) ->
    console.log("updating plugin view: start")
    console.log(violations)

    @createViolationDivs(violations)

  createViolationDivs: (augmentedViolations) ->
    console.log("createViolationDivs: called with ")
    console.log(augmentedViolations)

    @clearChildren()

    @minimapOverlay = SVG.createSVGObject(0, 32)
    @minimapOverlay.classList.add('minimap-canvas-overlay')
    @minimapContainer.appendChild(@minimapOverlay)
    $(@minimapOverlay).click((e) =>
      @minimapOnClick(e)
    )

    # TODO: figure out a better way to store the visual stuff here
    @minimaps = {}
    @minimapIndex = {}
    minimapPromises = []
    @violationMarkers = []
    for index in [0 .. augmentedViolations.length - 1]
      violation = augmentedViolations[index]
      violationView = new DetailCodeView({
        isVisual: true,
        index: index,
        violation: violation,
        onViolationClickCallback: ((index) => @highlightViolation(index, false))
      })
      @violationContainer.appendChild(violationView.getElement())
      @violationMarkers.push(violation.markers)

      if violation.line1.filename
        if not @minimaps[violation.line1.filename]
          @minimaps[violation.line1.filename] = new MinimapView({filename: violation.line1.filename})
          minimapPromises.push(@minimaps[violation.line1.filename].init())
          @minimapIndex[violation.line1.filename] = minimapPromises.length - 1
          @minimapContainer.appendChild(@minimaps[violation.line1.filename].getElement())
        @minimaps[violation.line1.filename].addDecoration(violation.line1.line)
      if violation.line2.filename
        if not @minimaps[violation.line2.filename]
          @minimaps[violation.line2.filename] = new MinimapView({filename: violation.line2.filename})
          minimapPromises.push(@minimaps[violation.line2.filename].init())
          @minimapIndex[violation.line2.filename] = minimapPromises.length - 1
          @minimapContainer.appendChild(@minimaps[violation.line2.filename].getElement())
        @minimaps[violation.line2.filename].addDecoration(violation.line2.line)

    Promise.all(minimapPromises).then(() =>
      console.log("All promises done!")
      console.log(@minimaps)
      console.log(Object.getOwnPropertyNames(@minimaps))
      maxHeight = -1
      minimaps = Object.getOwnPropertyNames(@minimaps)
      for minimap in minimaps
        height = @minimaps[minimap].getHeight()
        console.log("looking at: #{height} height")
        if maxHeight < height
          maxHeight = height
      @minimapOverlay.style.height = maxHeight + "px"
      @minimapOverlay.style.width = (minimaps.length * 240) + "px"
      @minimapOverlay.height = maxHeight
      @minimapOverlay.width = (minimaps.length * 240)

      for index in [0 .. augmentedViolations.length - 1]
        @drawViolationConnector(augmentedViolations[index], index)
    )

  minimapOnClick: (e) ->
    rect = @minimapOverlay.getBoundingClientRect();
    parentTop = @minimapOverlay.offsetTop
    parentLeft = @minimapOverlay.offsetLeft
    left = Math.round(e.pageX - rect.left)
    top = Math.round(e.pageY - rect.top)
    console.log("clicked: left: #{e.pageX - rect.left}, top: #{e.pageY - rect.top}")
    violationId = e.target.getAttribute('violation-id')
    console.log("clicked on id: #{violationId}")
    if violationId
      @highlightViolation(+violationId, true)
    else
      e.stopPropagation()

  drawViolationConnector: (violation, index) ->
    DEBUG = false
    console.log("Drawing violation connector.") if DEBUG
    console.log(violation) if DEBUG

    if not violation.line1.filename or not violation.line2.filename
      return

    # The violation is within the same file, so we'll have to draw a curved line.
    if violation.line1.filename is violation.line2.filename
      console.log(@minimapIndex) if DEBUG
      console.log(@minimapIndex[violation.line1.filename]) if DEBUG
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
      console.log("Drawing a curve from #{startX},#{line1Y} to #{endX}, #{line2Y}") if DEBUG
      SVG.addSVGLine(@minimapOverlay, "#{index}", startX, line1Y, endX, line2Y)

  highlightViolation: (index, shouldScroll) ->
    if @currentHighlightedIndex is index
      @scrollToViolation()
      return

    @resetHighlight()

    console.log("Highlighting violation: #{index}")
    if not @violationContainer.children[index]
      console.log("Uh oh, current violation not found but highlightViolation triggered")
    else
      console.log($("[violation-id=#{index}]"))
      @setHighlight(index)
      if shouldScroll
        @scrollToViolation()

  resetHighlight: () ->
    console.log("resetHighlight: #{@currentHighlightedIndex}")
    if @currentHighlightedIndex isnt null
      violationDiv = @violationContainer.children[@currentHighlightedIndex]
      violationDiv.classList.remove('highlighted')
      $("[violation-id=#{@currentHighlightedIndex}-visible]").css("stroke", "#ff0000")
      @resetMarkers()
      @currentHighlightedIndex = null

  setHighlight: (index) ->
    @currentHighlightedIndex = index
    violationDiv = @violationContainer.children[index]
    violationDiv.classList.add('highlighted')
    $("[violation-id=#{index}-visible]").css("stroke", "#ffff00")
    @highlightMarkers(index)

  highlightMarkers: (index) ->
    if @violationMarkers isnt null
      for marker in @violationMarkers[index]
        console.log("Highlighting marker...")
        marker.highlightMarker()

  resetMarkers: () ->
    console.log("in reset markers")
    console.log(@currentHighlightedIndex)
    if @currentHighlightedIndex isnt null and @violationMarkers isnt null
      console.log(@violationMarkers)
      for marker in @violationMarkers[@currentHighlightedIndex]
        console.log("Resetting marker...")
        marker.resetMarker()

  setViolations: (violations) ->
    @update(violations)

  scrollToViolation: () ->
    violationTop = @violationContainer.children[@currentHighlightedIndex].offsetTop
    @violationContainer.scrollTop = violationTop - 10

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  onClosePanel: (e) ->
    @resetHighlight()
    @onCloseCallback()

  clearChildren: () ->
    console.log("Clearing children...")

    $(@violationContainer).empty()
    $(@minimapContainer).empty()

  # Tear down any state and detach
  destroy: ->
    console.log("Destroying plugin view")
    @element.remove()

  getElement: () ->
    return @element
