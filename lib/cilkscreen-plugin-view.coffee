$ = require('jquery')
FileLineReader = require('./file-read-lines')
{CompositeDisposable} = require('atom')
DetailCodeView = require('./detail-code-view')

module.exports =
class CilkscreenPluginView
  index: null
  element: null
  currentViolation: null
  violationContainer: null
  onCloseCallback: null
  getTextEditorCallback: null
  subscriptions: null

  HALF_CONTEXT: 2

  constructor: (state, onCloseCallback, getTextEditorCallback) ->
    @onCloseCallback = onCloseCallback
    @getTextEditorCallback = getTextEditorCallback

    @subscriptions = new CompositeDisposable()

    # Create root element
    @element = document.createElement('div')
    @element.classList.add('cilkscreen-detail-view')
    @element.classList.add('table')

    resizeDiv = document.createElement('div')
    resizeDiv.classList.add('cilkscreen-detail-resize')

    @element.appendChild(resizeDiv)
    $(resizeDiv).on('mousedown', @resizeStart)

    header = document.createElement('div')
    header.classList.add('header')
    header.classList.add('table-row')
    title = document.createElement('div')
    title.classList.add('header-title')
    title.textContent = "Cilkscreen Detected Race Conditions"
    close = document.createElement('div')
    close.classList.add('header-close')
    close.classList.add('icon')
    close.classList.add('icon-x')
    $(close).on('click', onCloseCallback)
    header.appendChild(title)
    header.appendChild(close)

    @element.appendChild(header)

    violationWrapper = document.createElement('div')
    violationWrapper.classList.add('violation-wrapper')
    violationWrapper.classList.add('table-row')

    violationContentWrapper = document.createElement('div')
    violationContentWrapper.classList.add('violation-content-wrapper')
    violationWrapper.appendChild(violationContentWrapper)

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

  getViolationDivs: (violations) ->
    ## TODO: Unjank this up
    divs = []

    console.log("getViolationDivs: start")
    console.log(violations)

    readRequestArray = []
    violations.forEach((item) =>
      line1Request = [
        item.line1.file,
        [item.line1.line - @HALF_CONTEXT, item.line1.line + @HALF_CONTEXT]
      ]
      line2Request = [
        item.line2.file,
        [item.line2.line - @HALF_CONTEXT, item.line2.line + @HALF_CONTEXT]
      ]
      readRequestArray.push(line1Request)
      readRequestArray.push(line2Request)
    )

    FileLineReader.readLineNumBatch(readRequestArray, (texts) =>
      augmentedViolations = @groupCodeWithViolations(violations, texts)
      @createViolationDivs(augmentedViolations)
    )

    return []

  # TODO: fill out stub
  createViolationDivs: (augmentedViolations) ->
    console.log("createViolationDivs: called with ")
    console.log(augmentedViolations)

    # Remove any old children, if necessary
    while @violationContainer.firstChild
      @violationContainer.removeChild(@violationContainer.firstChild)

    for violation in augmentedViolations
      violationView = new DetailCodeView(violation, ((node) => @onViolationClickCallback(node)))
      @violationContainer.appendChild(violationView.getElement())

  groupCodeWithViolations: (violations, texts) ->
    augmentedViolationList = []
    for violation in violations
      augmentedViolation = { violation: violation }
      codeSnippetsFound = 0
      for text in texts
        if codeSnippetsFound is 2
          break
        if violation.line1.filename is text.file and violation.line1.line - @HALF_CONTEXT is text.lineRange[0]
          augmentedViolation.line1 = text
          codeSnippetsFound++
        if violation.line2.filename is text.file and violation.line2.line - @HALF_CONTEXT is text.lineRange[0]
          augmentedViolation.line2 = text
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
    @getViolationDivs(violations)

  scrollToViolation: () ->
    violationTop = @currentViolation.offsetTop
    @violationContainer.scrollTop = violationTop - 10

  generateTextDiv: (text) ->
    div = document.createElement('div')
    div.textContent = text
    return div

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->
    console.log("Destroying plugin view")
    @element.remove()

  getElement: () ->
    return @element
