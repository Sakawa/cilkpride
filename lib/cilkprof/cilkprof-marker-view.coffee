module.exports =
class CilkprofMarker

  type: 1

  element: null

  constructor: (info) ->
    @createMarker(info)
    return @element

  createMarker: (info) ->
    if @type is 1
      @element = document.createElement('div')
      @element.appendChild(@createBarGraphView(info.work, info.totalWork, info.totalCount, true))
      @element.appendChild(@createBarGraphView(info.span, info.totalSpan, info.spanCount, false))
    else if @type is 2
      @element = document.createElement('div')
      @element.appendChild(@createBarGraphView(info.work, info.totalWork, info.totalCount, true))

  createBarGraphView: (raw, total, count, isWork) ->
    percent = parseFloat(raw) / total
    bar = document.createElement('div')
    if isWork
      bar.classList.add("cilkprof-marker-test-#{@type}-work")
    else
      bar.classList.add("cilkprof-marker-test-#{@type}-span")
    percent100 = Math.round(percent * 10000) / 100
    innerBar = document.createElement('div')
    if isWork
      innerBar.classList.add("cilkprof-marker-test-#{@type}-work-inner")
    else
      innerBar.classList.add("cilkprof-marker-test-#{@type}-span-inner")
    innerBar.style.width = "#{percent100}%"
    text = document.createElement('div')
    if isWork
      text.classList.add("cilkprof-marker-test-#{@type}-work-bar-text")
    else
      text.classList.add("cilkprof-marker-test-#{@type}-span-bar-text")
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

  getElement: () ->
    return @element
