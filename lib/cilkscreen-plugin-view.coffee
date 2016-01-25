module.exports =
class CilkscreenPluginView
  index: null
  violations: null
  element: null

  constructor: (state, onCloseCallback) ->
    @index = state.index
    @violations = state.violations

    # Create root element
    @element = document.createElement('div')
    @element.classList.add('cilkscreen-detail-view')

    header = document.createElement('div')
    header.classList.add('header')
    title = document.createElement('div')
    title.classList.add('header-title')
    title.textContent = "Cilkscreen Race Condition Detector - Detailed View"
    close = document.createElement('div')
    close.classList.add('header-close')
    close.classList.add('icon')
    close.classList.add('icon-x')
    close.onclick = onCloseCallback
    header.appendChild(title)
    header.appendChild(close)

    @element.appendChild(header)

    # Create message element
    message = document.createElement('div')
    message.textContent = "Hello world!"
    message.classList.add('message')
    @element.appendChild(message)

    # Get the violation text, and append the divs
    violationDivs = @getViolationDivs()
    for violationDiv in violationDivs
      @element.appendChild(violationDiv)

  getViolationDivs: () ->
    ## TODO: Unjank this up
    divs = []
    console.log(@violations)
    for i in [0 .. @violations.length - 1]
      violation = @violations[i]
      divToAdd = document.createElement('div')
      if @index is i
        divToAdd.classList.add('highlighted')
      divToAdd.appendChild(@generateTextDiv(violation.location))
      divToAdd.appendChild(@generateTextDiv(violation.line1.raw))
      divToAdd.appendChild(@generateTextDiv(violation.line2.raw))
      for trace in violation.stacktrace
        divToAdd.appendChild(@generateTextDiv(trace))
      divs.push(divToAdd)
    return divs

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

  getElement: ->
    @element
