###
Class specifying how Cilkprof markers appear in the gutter.
###

$ = require('jquery')
d3 = require('d3')

Debug = require('../utils/debug')

module.exports =
class CilkprofMarker

  # TODO: document this
  currentType: 1
  numTypes: 3

  element: null

  MAX_CORES = 32
  CURRENT_CORES = 8

  constructor: (info) ->
    @element = document.createElement('div')
    for i in [0 ... @numTypes]
      @element.appendChild(@createMarker(info, i))
    @switchType()

    atom.commands.add('atom-workspace', 'cilkpride:debug2', (event) =>
      @switchType()
    )

    return @element

  switchType: () ->
    @currentType = (@currentType + 1) % @numTypes
    for child in @element.children
      $(child).addClass('hidden')
    $(@element.children[@currentType]).removeClass('hidden')

  createMarker: (info, type) ->
    if type is 0
      element = document.createElement('div')
      element.appendChild(@createBarGraphView(info.work, info.totalWork, info.totalCount, true, type))
      element.appendChild(@createBarGraphView(info.span, info.totalSpan, info.spanCount, false, type))
    else if type is 1
      element = document.createElement('div')
      element.appendChild(@createBarGraphView(info.work, info.totalWork, info.totalCount, true, type))
    else if type is 2
      element = document.createElement('div')
      svgElement = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
      svgElement.setAttribute("width", "30px")
      svgElement.setAttribute("height", "24px")
      element.appendChild(svgElement)

      percent = parseFloat(info.work) / info.totalWork
      interpolator = d3.interpolateRgbBasis(["green", "gray", "red"])

      svg = d3.select(svgElement)
      width = 30
      height = 23
      g = svg.append("g")

      x = d3.scaleLog().base(2).rangeRound([0, width])
      y = d3.scaleLinear().rangeRound([height, 0])

      area = d3.area()
        .x((d) -> return x(d.index))
        .y0(height)
        .y1((d) -> return y(d.time))
      line = d3.line()
        .x((d) -> return x(d.index))
        .y((d) -> return y(d.time))

      data = @calculateWorkSpan(info.work, info.spanOnWork, info.totalWork, info.totalSpan)
      Debug.info(data)
      x.domain([1, MAX_CORES]);
      y.domain([0, 1]);
      g.append("path")
        .datum(data)
        .attr("class", "area")
        .attr("d", area)
        .attr("fill", "#{interpolator(percent)}")
      g.append("path")
        .datum(data)
        .attr("class", "line")
        .attr("d", line)
        .attr("stroke", "#{interpolator(percent)}")
      g.append("path")
        .datum([{index: CURRENT_CORES, time: 0}, {index: CURRENT_CORES, time: 1}])
        .attr("class", "dashed-line")
        .attr("stroke-dasharray", "1,4")
        .attr("d", line)
      g.append("g")
        .attr("class", "axis axis--x")
        .attr("transform", "translate(0," + height + ")")
        .style("stroke", "white")
        .call(d3.axisBottom(x).ticks(0))
      g.append("g")
        .attr("class", "axis axis--y")
        .style("stroke", "white")
        .call(d3.axisLeft(y))
    # else if type is 3
    #   element = document.createElement('div')
    #   runningTime = (info.totalWork - info.totalSpan) / CURRENT_CORES + info.totalSpan
    #   percent1 = (info.work - info.spanOnWork) / CURRENT_CORES / runningTime
    #   percent2 = info.spanOnWork / runningTime
    #   bar = document.createElement('div')
    #   bar.classList.add("cilkprof-marker-test-#{type}")
    #   percent1001 = Math.round(percent1 * 10000) / 100
    #   percent1002 = Math.round(percent2 * 10000) / 100
    #   innerBar = document.createElement('div')
    #   innerBar.classList.add("cilkprof-marker-test-#{type}-inner1")
    #   innerBar.style.width = "#{percent1001}%"
    #   innerBar2 = document.createElement('div')
    #   innerBar2.classList.add("cilkprof-marker-test-#{type}-inner2")
    #   innerBar2.style.width = "#{percent1002}%"
    #   innerBar2.style.left = "#{percent1001}%"
    #   text = document.createElement('div')
    #   text.classList.add("cilkprof-marker-test-#{type}-bar-text")
    #   text.textContent = "#{@truncateCount(info.totalCount)}"
    #   innerBar.style.color = "white"
    #   bar.appendChild(innerBar2)
    #   bar.appendChild(innerBar)
    #   innerBar.appendChild(text)
    #   element.appendChild(bar)
    Debug.log(element)
    return element

  createBarGraphView: (raw, total, count, isWork, type) ->
    percent = parseFloat(raw) / total
    bar = document.createElement('div')
    if isWork
      bar.classList.add("cilkprof-marker-test-#{type}-work")
    else
      bar.classList.add("cilkprof-marker-test-#{type}-span")
    percent100 = Math.round(percent * 10000) / 100
    innerBar = document.createElement('div')
    if isWork
      innerBar.classList.add("cilkprof-marker-test-#{type}-work-inner")
    else
      innerBar.classList.add("cilkprof-marker-test-#{type}-span-inner")
    innerBar.style.width = "#{percent100}%"
    text = document.createElement('div')
    if isWork
      text.classList.add("cilkprof-marker-test-#{type}-work-bar-text")
    else
      text.classList.add("cilkprof-marker-test-#{type}-span-bar-text")
    text.textContent = "#{@truncateCount(count)}"
    innerBar.style.color = "white"
    bar.appendChild(innerBar)
    innerBar.appendChild(text)

    return bar

  truncateCount: (count) ->
    count = String(count)
    if count.length < 4
      return count
    if count.length < 7
      return count.slice(0, -3) + "K"
    if count.length < 10
      return count.slice(0, -6) + "M"
    if count.length < 13
      return count.slice(0, -9) + "B"
    return count.slice(0, -12) + "T"

  calculateWorkSpan: (work, span, totalWork, totalSpan) ->
    return [1 .. 64].map((currentValue, index, array) =>
      return {
        index: currentValue,
        time: @calculateWorkSpanForCore(work, span, totalWork, totalSpan, currentValue)
      }
    )

  calculateWorkSpanForCore: (work, span, totalWork, totalSpan, cores) ->
    return ((work - span) / cores + span) / (totalWork)

  getElement: () ->
    return @element
