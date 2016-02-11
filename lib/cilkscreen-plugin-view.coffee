$ = require('jquery')

module.exports =
class CilkscreenPluginView
  index: null
  element: null
  currentViolation: null
  violationContainer: null

  constructor: (state, onCloseCallback) ->
    @index = state.index
    @violations = state.violations

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
    title.textContent = "Cilkscreen Race Condition Detector - Detailed View"
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
    console.log(violations)
    for i in [0 .. violations.length - 1]
      violation = violations[i]
      divToAdd = document.createElement('div')
      divToAdd.appendChild(@generateTextDiv(violation.location))
      divToAdd.appendChild(@generateTextDiv(violation.line1.raw))
      divToAdd.appendChild(@generateTextDiv(violation.line2.raw))
      for trace in violation.stacktrace
        divToAdd.appendChild(@generateTextDiv(trace))
      divs.push(divToAdd)
    return divs

  highlightViolation: (index) ->
    @currentViolation.classList.remove('highlighted') if @currentViolation isnt null

    @currentViolation = @violationContainer.children[index]
    @currentViolation.classList.add('highlighted')

  setViolations: (violations) ->
    # Remove any old children, if necessary
    while @violationContainer.firstChild
      @violationContainer.removeChild(@violationContainer.firstChild)

    # Get the violation text, and append the divs
    violationDivs = @getViolationDivs(violations)
    for violationDiv in violationDivs
      @violationContainer.appendChild(violationDiv)

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
