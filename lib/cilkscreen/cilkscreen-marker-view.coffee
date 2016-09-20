$ = require('jquery')

module.exports =
class CilkscreenMarkerView
  state: null

  constructor: (state, onClickCallback) ->
    @state = state

    # Create root element
    @element = document.createElement('span')
    @element.classList.add('alert')
    @element.title = "Race condition detected at this line. Click for details."

    $(@element).on('click', (e) =>
      onClickCallback(@state.index)
    )

  # Returns an object that can be retrieved when package is activated
  serialize: () ->

  # Tear down any state and detach
  destroy: () ->
    @element.remove()

  getElement: () ->
    return @element

  highlightMarker: () ->
    @element.classList.add('highlighted')

  resetMarker: () ->
    @element.classList.remove('highlighted')
