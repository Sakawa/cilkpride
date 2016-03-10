$ = require('jquery')
FileLineReader = require('./file-read-lines')
{CompositeDisposable} = require('atom')
DetailCodeView = require('./detail-code-view')
MinimapView = require('./minimap-view')
CanvasUtil = require('./canvas-util')

module.exports =
class CilkscreenPluginView
  element: null
  currentViolation: null
  violationContainer: null
  minimapContainer: null
  minimaps: null
  minimapIndex: null

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
    $(close).on('click', @onCloseCallback)
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

    readRequestArray = []
    violations.forEach((item) =>
      line1Request = [
        item.line1.filename,
        [item.line1.line - @HALF_CONTEXT, item.line1.line + @HALF_CONTEXT]
      ]
      line2Request = [
        item.line2.filename,
        [item.line2.line - @HALF_CONTEXT, item.line2.line + @HALF_CONTEXT]
      ]
      readRequestArray.push(line1Request)
      readRequestArray.push(line2Request)
    )

    FileLineReader.readLineNumBatch(readRequestArray, (texts) =>
      augmentedViolations = @groupCodeWithViolations(violations, texts)
      @createViolationDivs(augmentedViolations)
    )

  createViolationDivs: (augmentedViolations) ->
    console.log("createViolationDivs: called with ")
    console.log(augmentedViolations)

    @clearChildren()

    @minimapOverlay = document.createElement('canvas')
    @minimapOverlay.classList.add('minimap-canvas-overlay')
    @minimapContainer.appendChild(@minimapOverlay)
    $(@minimapOverlay).mousemove((e) =>
      @minimapOnClick(e)
    )

    # TODO: figure out a better way to store the visual stuff here
    @minimaps = {}
    @minimapIndex = {}
    minimapPromises = []
    for violation in augmentedViolations
      violationView = new DetailCodeView({
        isVisual: true,
        violation: violation,
        onViolationClickCallback: ((node) => @onViolationClickCallback(node))
      })
      @violationContainer.appendChild(violationView.getElement())

      if not @minimaps[violation.line1.filename]
        @minimaps[violation.line1.filename] = new MinimapView({filename: violation.line1.filename})
        minimapPromises.push(@minimaps[violation.line1.filename].init())
        @minimapIndex[violation.line1.filename] = minimapPromises.length - 1
        @minimapContainer.appendChild(@minimaps[violation.line1.filename].getElement())
      if not @minimaps[violation.line2.filename]
        @minimaps[violation.line2.filename] = new MinimapView({filename: violation.line2.filename})
        minimapPromises.push(@minimaps[violation.line2.filename].init())
        @minimapIndex[violation.line2.filename] = minimapPromises.length - 1
        @minimapContainer.appendChild(@minimaps[violation.line2.filename].getElement())

      @minimaps[violation.line1.filename].addDecoration(violation.line1.line)
      @minimaps[violation.line2.filename].addDecoration(violation.line2.line)

    Promise.all(minimapPromises).then(() =>
      console.log("All promises done!")
      console.log(@minimaps)
      console.log(Object.getOwnPropertyNames(@minimaps))
      maxHeight = -1
      minimaps = Object.getOwnPropertyNames(@minimaps)
      for minimap in minimaps
        height = @minimaps[minimap].getHeight()
        if maxHeight < height
          maxHeight = height
      @minimapOverlay.style.height = maxHeight + "px"
      @minimapOverlay.style.width = (minimaps.length * 240) + "px"
      @minimapOverlay.height = maxHeight
      @minimapOverlay.width = (minimaps.length * 240)

      for violation in augmentedViolations
        @drawViolationConnector(violation)
    )

  minimapOnClick: (e) ->
    console.log(e)

  drawViolationConnector: (violation) ->
    console.log("Drawing violation connector.")
    console.log(violation)

    # The violation is within the same file, so we'll have to draw a curved line.
    if violation.line1.filename is violation.line2.filename
      console.log(@minimapIndex)
      console.log(@minimapIndex[violation.line1.filename])
      startX = CanvasUtil.getLeftSide(@minimapIndex[violation.line1.filename])
      line1Y = CanvasUtil.getLineTop(violation.line1.line)
      line2Y = CanvasUtil.getLineTop(violation.line2.line)
      console.log("Drawing a curve from #{startX},#{line1Y} to #{startX}, #{line2Y}")
      console.log("The control point will be #{startX - 15}, #{(line1Y + line2Y) / 2}")
      ctx = @minimapOverlay.getContext("2d")
      ctx.strokeStyle = 'red'
      ctx.lineWidth = 3
      ctx.beginPath()
      ctx.moveTo(startX, line1Y)
      ctx.quadraticCurveTo(startX - 15, (line1Y + line2Y) / 2, startX, line2Y)
      ctx.stroke()

  groupCodeWithViolations: (violations, texts) ->
    augmentedViolationList = []
    for violation in violations
      augmentedViolation = violation
      codeSnippetsFound = 0
      console.log(violation)
      for text in texts
        console.log(text)
        if codeSnippetsFound is 2
          break
        if violation.line1.filename is text.filename and violation.line1.line - @HALF_CONTEXT is text.lineRange[0]
          augmentedViolation.line1.text = text.text
          augmentedViolation.line1.lineRange = text.lineRange
          codeSnippetsFound++
        if violation.line2.filename is text.filename and violation.line2.line - @HALF_CONTEXT is text.lineRange[0]
          augmentedViolation.line2.text = text.text
          augmentedViolation.line2.lineRange = text.lineRange
          codeSnippetsFound++
      augmentedViolationList.push(augmentedViolation)
      if codeSnippetsFound < 2
        console.log("groupCodeWithViolations: too few texts found for a violation")
    console.log("Finished groupCodeWithViolations")
    console.log(augmentedViolationList)
    return augmentedViolationList

  highlightViolation: (index) ->
    @currentViolation.classList.remove('highlighted') if @currentViolation isnt null

    @currentViolation = @violationContainer.children[index]
    if not @currentViolation
      console.log("Uh oh, current violation not found but highlightViolation triggered")
    @currentViolation.classList.add('highlighted')

  onViolationClickCallback: (node) ->
    if @currentViolation is node
      return
    @currentViolation.classList.remove('highlighted') if @currentViolation isnt null
    node.classList.add('highlighted')
    @currentViolation = node

  setViolations: (violations) ->
    @update(violations)

  scrollToViolation: () ->
    violationTop = @currentViolation.offsetTop
    @violationContainer.scrollTop = violationTop - 10

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  clearChildren: () ->
    # Remove any old children, if necessary
    while @violationContainer and @violationContainer.firstChild
      @violationContainer.removeChild(@violationContainer.firstChild)

    while @minimapContainer and @minimapContainer.firstChild
      @minimapContainer.removeChild(@minimapContainer.firstChild)

  # Tear down any state and detach
  destroy: ->
    console.log("Destroying plugin view")
    @element.remove()

  getElement: () ->
    return @element
