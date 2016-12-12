###
SVG Util class for creating SVG objects and elements. Currently not being used,
but originally designed to annotate the visual minimap representations in the
Cilksan view.
###

module.exports =
class SVG
  @createSVGObject = (xOffset, yOffset) ->
    svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")

    svg.classList.add('svg')
    svg.style.top = yOffset + "px"
    svg.style.left = xOffset + "px"

    return svg

  @addSVGLine = (svg, id, x1, y1, x2, y2) ->
    line = SVG.createSVGElement("line", {
      "stroke": "#ff0000",
      "stroke-width": "1",
      "violation-id": "#{id}-visible",
      "x1": x1,
      "x2": x2,
      "y1": y1,
      "y2": y2,
    })

    # We need an invisible line that is larger than the visible line,
    # to serve as the clickable part.
    hiddenLine = SVG.createSVGElement("line", {
      "stroke": "#ff0000",
      "stroke-width": "8",
      "stroke-opacity": "0.0",
      "violation-id": id,
      "x1": x1,
      "x2": x2,
      "y1": y1,
      "y2": y2,
    })

    svg.appendChild(line)
    svg.appendChild(hiddenLine)

  @addSVGCurve = (svg, id, x1, y1, x2, y2) ->
    midX = (x1 + x2) / 2
    midY = (y1 + y2) / 2
    path = "M #{x1} #{y1} Q #{midX - 20} #{midY} #{x2} #{y2}"
    curve = SVG.createSVGElement("path", {
      "d": path,
      "fill": "none",
      "stroke": "#ff0000",
      "stroke-width": "2",
      "violation-id": "#{id}-visible",
    })

    # We need an invisible curve that is larger than the visible curve,
    # to serve as the clickable part.
    hiddenCurve = SVG.createSVGElement("path", {
      "d": path,
      "fill": "none",
      "stroke": "#ff0000",
      "stroke-opacity": "0.0",
      "stroke-width": "8",
      "violation-id": id,
    })

    svg.appendChild(curve)
    svg.appendChild(hiddenCurve)

  @createSVGElement = (type, attributes) ->
    line = document.createElementNS("http://www.w3.org/2000/svg", type)
    line.classList.add("svg-#{type}")
    for attribute in Object.getOwnPropertyNames(attributes)
      line.setAttribute(attribute, attributes[attribute])
    return line
