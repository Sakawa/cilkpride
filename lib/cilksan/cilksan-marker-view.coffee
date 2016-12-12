###
Simple class specifying how Cilksan markers appear in the gutter.
###

$ = require('jquery')

module.exports =
class CilksanMarkerView
  props: null            # object containing parent-specified properties
  index: null            # the index of the violation this marker represents
  onClickCallback: null  # callback when the marker is clicked

  element: null          # the actual UI element shown in the gutter

  constructor: (props) ->
    @props = props
    @index = props.index
    @onClickCallback = props.onMarkerClick

    # Create root element
    @element = document.createElement('span')
    @element.classList.add('alert')
    @element.title = "Race condition detected at this line. Click for details."

    $(@element).on('click', (e) =>
      @onClickCallback(@index)
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
