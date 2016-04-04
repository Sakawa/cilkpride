class MinimapUtil
  VERTICAL_PADDING = 5
  HORIZONTAL_PADDING = 20
  CANVAS_WIDTH = 200
  LINE_HEIGHT = 4

  constructor: () ->

  @getLeftSide: (index) ->
    return (index * (HORIZONTAL_PADDING * 2 + CANVAS_WIDTH)) + HORIZONTAL_PADDING

  @getRightSide: (index) ->
    return (index + 1) * (HORIZONTAL_PADDING * 2 + CANVAS_WIDTH) - HORIZONTAL_PADDING

  @getLineTop: (line) ->
    return line * LINE_HEIGHT - 2

class TimeUtil
  @MS_IN_SEC: 1000
  @MS_IN_MIN: 1000 * 60
  @MS_IN_HR: 1000 * 60 * 60
  @MS_IN_DAY: 1000 * 60 * 60 * 24

  @getTimeSince: (date) ->
    d = new Date(date)
    return "#{d.toLocaleDateString()} #{d.toLocaleTimeString()}"

module.exports = {MinimapUtil, TimeUtil}
