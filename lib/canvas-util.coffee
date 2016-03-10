VERTICAL_PADDING = 5
HORIZONTAL_PADDING = 20
CANVAS_WIDTH = 200
LINE_HEIGHT = 4

module.exports =
class CanvasUtil

  constructor: () ->

  @getLeftSide: (index) ->
    return (index * (HORIZONTAL_PADDING * 2 + CANVAS_WIDTH)) + HORIZONTAL_PADDING

  @getRightSide: (index) ->
    return (index + 1) * (HORIZONTAL_PADDING * 2 + CANVAS_WIDTH) - HORIZONTAL_PADDING

  @getLineTop: (line) ->
    return line * LINE_HEIGHT - 2
