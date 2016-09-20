$ = require('jquery')
{CompositeDisposable} = require('atom')

FileLineReader = require('../utils/file-reader')
DetailCodeView = require('./detail-code-view')
MinimapView = require('../utils/minimap')
{MinimapUtil} = require('../utils/utils')
SVG = require('../utils/svg')

module.exports =
class CilkscreenPluginView
  element: null
  violationContainer: null
  violationContentWrapper: null
  minimapContainer: null
  minimaps: null
  minimapIndex: null
  toggleVisual: true

  # Properties from parents
  props: null
  onCloseCallback: null
  highlightCallback: null

  HALF_CONTEXT: 2

  constructor: (props) ->
    @props = props
    @onCloseCallback = props.onCloseCallback
    @highlightCallback = props.highlightCallback

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
    title.textContent = "Detected Race Conditions"
    close = document.createElement('div')
    close.classList.add('header-close', 'icon', 'icon-x')
    $(close).on('click', (() => @onCloseCallback()))
    header.appendChild(title)
    header.appendChild(close)

    @element.appendChild(header)

    violationWrapper = document.createElement('div')
    violationWrapper.classList.add('violation-wrapper', 'table-row')

    violationContentWrapper = document.createElement('div')
    @violationContentWrapper = violationContentWrapper
    violationContentWrapper.classList.add('violation-content-wrapper')
    if @toggleVisual
      violationContentWrapper.classList.add('visual')
      minimapResizeDiv = document.createElement('div')
      minimapResizeDiv.classList.add('minimap-resize-div')
      violationContentWrapper.appendChild(minimapResizeDiv)
      $(minimapResizeDiv).on('mousedown', @horizontalResizeStart)
    violationWrapper.appendChild(violationContentWrapper)

    if @toggleVisual
      @minimapContainer = document.createElement('div')
      @minimapContainer.classList.add('minimap-container')
      violationWrapper.appendChild(@minimapContainer)

    @violationContainer = document.createElement('div')
    @violationContainer.classList.add('violation-container')
    violationContentWrapper.appendChild(@violationContainer)

    @element.appendChild(violationWrapper)

  resizeStart: () =>
    # console.log("Resize start")
    $(document).on('mousemove', @resizeMove)
    $(document).on('mouseup', @resizeStop)

  resizeStop: () =>
    # console.log("Resize stop")
    $(document).off('mousemove', @resizeMove)
    $(document).off('mouseup', @resizeStop)

  resizeMove: (event) =>
    return @resizeStop() unless event.which is 1

    element = $(@element)
    # console.log("Horizontal resize move")
    height = element.offset().top + element.outerHeight() - event.pageY
    element.height(height)

  horizontalResizeStart: () =>
    # console.log("Horizontal resize start")
    $(document).on('mousemove', @horizontalResizeMove)
    $(document).on('mouseup', @horizontalResizeStop)

  horizontalResizeStop: () =>
    # console.log("Horizontal resize stop")
    $(document).off('mousemove', @horizontalResizeMove)
    $(document).off('mouseup', @horizontalResizeStop)

  horizontalResizeMove: (event) =>
    return @horizontalResizeStop() unless event.which is 1

    element = $(@violationContentWrapper)
    # console.log("Horizontal resize move")
    width = element.offset().left + element.outerWidth() - event.pageX
    element.width(width)

  update: (violations) ->
    console.log("updating plugin view: start")
    console.log(violations)

    @createViolationDivs(violations)

  updateMinimap: (editor) ->
    console.log("updateMinimap called with editor: ")
    console.log(editor)
    if @toggleVisual
      console.log(@minimaps)
      if @minimaps and @minimaps[editor.getPath()]
        @minimaps[editor.getPath()].init(editor)
        console.log("updating minimap @ updateMinimap")
      else
        console.log("not updating @ updateMinimap 1")
    else
      console.log('not updating @ updateMinimap 2')

  createViolationDivs: (augmentedViolations) ->
    console.log("createViolationDivs: called with ")
    console.log(augmentedViolations)

    @clearChildren()

    if @toggleVisual
      @minimapOverlay = SVG.createSVGObject(0, 32)
      @minimapOverlay.classList.add('minimap-canvas-overlay')
      @minimapContainer.appendChild(@minimapOverlay)
      $(@minimapOverlay).click((e) =>
        @minimapOnClick(e)
      )

    # TODO: figure out a better way to store the visual stuff here
    if @toggleVisual
      @minimaps = {}
      @minimapIndex = {}
      minimapPromises = []
      minimapLineContainer = document.createElement('div')
      minimapLineContainer.classList.add('minimap-canvas-line-container')
      @minimapContainer.appendChild(minimapLineContainer)
    for index in [0 ... augmentedViolations.length]
      violation = augmentedViolations[index]
      violationView = new DetailCodeView({
        isVisual: @toggleVisual,
        index: index,
        violation: violation,
        onViolationClickCallback: ((e, index) => @highlightCallback(e, index, false))
      })
      @violationContainer.appendChild(violationView.getElement())

      if @toggleVisual
        @createMinimapForLine(violation.line1, minimapPromises, minimapLineContainer)
        @createMinimapForLine(violation.line2, minimapPromises, minimapLineContainer)

    # if @toggleVisual
    #   Promise.all(minimapPromises).then(() =>
    #     console.log("All promises done!")
    #     console.log(@minimaps)
    #     console.log(Object.getOwnPropertyNames(@minimaps))
    #     maxHeight = -1
    #     minimaps = Object.getOwnPropertyNames(@minimaps)
    #     for minimap in minimaps
    #       height = @minimaps[minimap].getHeight()
    #       console.log("looking at: #{height} height")
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

  createMinimapForLine: (violationLine, minimapPromises, minimapLineContainer) ->
    if violationLine.filename
      if not @minimaps[violationLine.filename]
        @minimaps[violationLine.filename] = new MinimapView({filename: violationLine.filename})
        # minimapPromises.push(@minimaps[violation.line1.filename].init())
        @minimaps[violationLine.filename].init()
        @minimapIndex[violationLine.filename] = minimapPromises.length - 1
        @minimapContainer.appendChild(@minimaps[violationLine.filename].getElement())
      @minimaps[violationLine.filename].addDecoration(violationLine.line)
      lineOverlay = document.createElement('div')
      lineOverlay.classList.add('minimap-line-overlay')
      lineOverlay.style.top = (MinimapUtil.getLineTop(violationLine.line)) + "px"
      lineOverlay.style.left = (MinimapUtil.getLeftSide(@minimapIndex[violationLine.filename])) + "px"
      minimapLineContainer.appendChild(lineOverlay)
      DetailCodeView.attachFileOpenListener(lineOverlay, violationLine.filename, violationLine.line)

  minimapOnClick: (e) ->
    rect = @minimapOverlay.getBoundingClientRect();
    left = Math.round(e.pageX - rect.left)
    top = Math.round(e.pageY - rect.top)
    console.log("clicked: left: #{e.pageX - rect.left}, top: #{e.pageY - rect.top}")
    violationId = e.target.getAttribute('violation-id')
    console.log("clicked on id: #{violationId}")
    if violationId
      @highlightCallback(e, +violationId, true)
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
    console.log("Clicked on a highlight violation for index #{index}")

    console.log("Highlighting violation: #{index}")
    if not @violationContainer.children[index]
      console.log("Uh oh, current violation not found but highlightViolation triggered")
    else
      console.log($("[violation-id=#{index}]"))
      @setHighlight(index)
      if shouldScroll
        @scrollToViolation(index)

  resetHighlight: (index) ->
    console.log("resetHighlight: #{index}")
    console.log(@violationContainer.children)

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
    console.log("Trying to scroll to index #{index}")
    violationTop = @violationContainer.children[index].offsetTop
    @violationContainer.scrollTop = violationTop - 10

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  clearChildren: () ->
    console.log("Clearing children...")

    $(@violationContainer).empty()
    if @toggleVisual
      $(@minimapContainer).empty()

  # Tear down any state and detach
  destroy: ->
    console.log("Destroying plugin view")
    @element.remove()

  getElement: () ->
    return @element
