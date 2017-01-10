###
Class specifying how Cilkprof markers appear in the gutter.
###

$ = require('jquery')
d3 = require('d3')

Debug = require('../utils/debug')

module.exports =
class CilkprofMarker

  # TODO: document this
  currentType: 0
  numTypes: 2

  currentCores: 32
  maxCores: 32 * 32

  element: null

  constructor: (info, numCores) ->
    if numCores
      @currentCores = numCores
      @maxCores = numCores * numCores
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
      element.classList.add('cilkprof-marker-type-0')
      element.appendChild(@createBarGraphView(info.work, info.totalWork, info.totalCount, true, type))
      element.appendChild(@createBarGraphView(info.span, info.totalSpan, info.spanCount, false, type))
    # else if type is 1
    #   element = document.createElement('div')
    #   element.appendChild(@createBarGraphView(info.work, info.totalWork, info.totalCount, true, type))
    else if type is 1
      element = document.createElement('div')
      element.classList.add('cilkprof-marker-type-2')
      svgElement = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
      svgElement.setAttribute("width", "30px")
      svgElement.setAttribute("height", "24px")
      element.appendChild(svgElement)

      percent = parseFloat(info.work) / info.totalWork
      # This should be the same as the interpolator found in ui.coffee.
      interpolator = d3.interpolateRgbBasis(["#226522", "gray", "#b72020"])

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
      x.domain([1, @maxCores]);
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
        .datum([{index: @currentCores, time: 0}, {index: @currentCores, time: 1}])
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

      # Execution count div + tooltip
      execCountDiv = document.createElement('div')
      execCountDiv.classList.add('badge')
      execCountDiv.textContent = @truncateCount(info.totalCount).toLowerCase()
      execCountDiv.style.backgroundColor = interpolator(percent)
      element.appendChild(execCountDiv)
      atom.tooltips.add(execCountDiv, {
        title: "This line was executed #{info.totalCount.toLocaleString('en-US')} times."
        trigger: 'hover'
        delay: 0
      })

      # D3 tooltip closeup
      tooltipSVGContainer = document.createElement('div')
      tooltipSVGContainer.classList.add('cilkprof-tooltip-svg')
      tooltipSVGElement = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
      tooltipSVGElement.setAttribute("width", "300px")
      tooltipSVGElement.setAttribute("height", "240px")
      tooltipSVGContainer.appendChild(tooltipSVGElement)

      tooltipSVG = d3.select(tooltipSVGElement)
      width = 260
      height = 200
      g = tooltipSVG.append("g")
        .attr("transform", "translate(" + 20 + "," + 10 + ")");

      x = d3.scaleLog().base(2).rangeRound([0, width])
      y = d3.scaleLinear().rangeRound([height, 0])

      area = d3.area()
        .x((d) -> return x(d.index))
        .y0(height)
        .y1((d) -> return y(d.time))
      line = d3.line()
        .x((d) -> return x(d.index))
        .y((d) -> return y(d.time))

      ideal = @calculateIdealParallelismCurve(info.work, info.totalWork)
      x.domain([1, @maxCores]);
      y.domain([0, 1]);
      g.append("path")
          .datum(data)
          .attr("class", "area transparent")
          .attr("d", area)
          .attr("fill", "#{interpolator(percent)}")
          .attr("data-legend", "Projected Speedup")
      g.append("path")
          .datum(ideal)
          .attr("class", "line")
          .attr("d", line)
          .attr("stroke", "black")
          .attr("data-legend", "Ideal Speedup (work/cores)")
      g.append("path")
          .datum(data)
          .attr("class", "line")
          .attr("d", line)
          .attr("stroke", "#{interpolator(percent)}")
      g.append("path")
          .datum([{index: @currentCores, time: 0}, {index: @currentCores, time: 1}])
          .attr("class", "dashed-line")
          .attr("stroke-dasharray", "1,4")
          .attr("d", line)
      g.append("text")
          .attr("class", "label")
          .attr("fill", "white")
          .attr("stroke", "none")
          .style("font-size", "8pt")
          .style("text-anchor", "end")
          .attr("transform", "rotate(-90)")
          .attr("dx", 0)
          .attr("dy", width / 2 + 10)
          .text("#{@currentCores} cores")
      g.append("g")
          .attr("class", "axis axis--x")
          .attr("transform", "translate(0," + height + ")")
          .style("stroke", "white")
          .call(d3.axisBottom(x).ticks(7))
        .append("text")
          .attr("class", "x label")
          .attr("fill", "white")
          .attr("stroke", "none")
          .style("font-size", "8pt")
          .style("text-anchor", "middle")
          .attr("x", width / 2)
          .attr("y", 28)
          .text("# of cores (log scale)")
      g.append("g")
          .attr("class", "axis axis--y")
          .style("stroke", "white")
          .call(d3.axisLeft(y).ticks(0))
        .append("text")
          .attr("fill", "white")
          .attr("stroke", "none")
          .style("font-size", "8pt")
          .attr("transform", "rotate(-90)")
          .attr("x", -height / 2)
          .attr("y", -10)
          .style("text-anchor", "middle")
          .text("time consumed")
      atom.tooltips.add(svgElement, {
        html: true
        placement: 'right'
        trigger: 'hover'
        delay: 0
        title: tooltipSVGContainer.outerHTML
      })
    # else if type is 3
    #   element = document.createElement('div')
    #   runningTime = (info.totalWork - info.totalSpan) / @currentCores + info.totalSpan
    #   percent1 = (info.work - info.spanOnWork) / @currentCores / runningTime
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
    return [1 .. @maxCores].map((currentValue, index, array) =>
      return {
        index: currentValue,
        time: @calculateWorkSpanForCore(work, span, totalWork, totalSpan, currentValue)
      }
    )

  calculateIdealParallelismCurve: (work, totalWork) ->
    return [1 .. @maxCores].map((currentValue, index, array) =>
      return {
        index: currentValue,
        time: (work / currentValue) / totalWork
      }
    )

  calculateWorkSpanForCore: (work, span, totalWork, totalSpan, cores) ->
    return ((work - span) / cores + span) / (totalWork)

  getElement: () ->
    return @element
