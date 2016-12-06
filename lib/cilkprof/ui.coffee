{CompositeDisposable, Range} = require('atom')
{normalizePath} = require('../utils/utils')
CilkprofMarkerView = require('./cilkprof-marker-view')
Debug = require('../utils/debug')

$ = require('jquery')
d3 = require('d3')
path = require('path').posix

module.exports =
class CilkprofUI

  props: null
  changePanel: null
  path: null

  element: null
  subscriptions: null

  markers: null

  contentContainer: null
  tableContentWrapper: null
  callgraphContainer: null

  constructor: (props) ->
    @props = props
    @changePanel = props.changePanel
    @path = props.path

    @subscriptions = new CompositeDisposable()
    @markers = {}

    # Create root element
    @element = document.createElement('div')
    @element.classList.add('cilkprof-detail-view', 'table')

    contentWrapper = document.createElement('div')
    contentWrapper.classList.add('cilkprof-content-wrapper')

    @callgraphContainer = document.createElement('div')
    @callgraphContainer.classList.add('callgraph-container')
    callgraphEmptyContentDiv = document.createElement('ul')
    callgraphEmptyContentDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "No results yet. Save a file to start cilkprof."
    callgraphEmptyContentDiv.appendChild(backgroundMessage)
    @callgraphContainer.appendChild(callgraphEmptyContentDiv)
    contentWrapper.appendChild(@callgraphContainer)

    tableContentWrapper = document.createElement('div')
    @tableContentWrapper = tableContentWrapper
    tableContentWrapper.classList.add('cilkprof-table-content-wrapper')

    tableContentWrapper.classList.add('visual')
    contentWrapper.appendChild(tableContentWrapper)

    @contentContainer = document.createElement('div')
    @contentContainer.classList.add('cilkprof-content-container')
    emptyContentDiv = document.createElement('ul')
    emptyContentDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "Your program's performance is shown here. Nothing right now!"
    emptyContentDiv.appendChild(backgroundMessage)
    @contentContainer.appendChild(emptyContentDiv)
    tableContentWrapper.appendChild(@contentContainer)

    @element.appendChild(contentWrapper)

  createUI: (results) ->
    Debug.log("[cilkprof] updating view - begin")
    # make stuff here (table)
    if results.csv.length
      @createMarkers(results)
      @createCilkprofTable(results)
      # @createCallgraph
    else
      @createEmptyBackgroundMessage()

  resetUI: () ->

  createEmptyBackgroundMessage: () ->
    @clearChildren()

    callgraphEmptyContentDiv = document.createElement('ul')
    callgraphEmptyContentDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "Nothing to display!"
    callgraphEmptyContentDiv.appendChild(backgroundMessage)
    @callgraphContainer.appendChild(callgraphEmptyContentDiv)

    emptyContentDiv = document.createElement('ul')
    emptyContentDiv.classList.add('background-message', 'centered', 'cilkpride-normal-whitespace', 'cilkpride-background-message')
    backgroundMessage = document.createElement('li')
    backgroundMessage.textContent = "No reported performance results."
    emptyContentDiv.appendChild(backgroundMessage)
    @contentContainer.appendChild(emptyContentDiv)

  createCilkprofTable: (results) ->
    Debug.log("[cilkprof-ui] called createCilkprofTable")
    Debug.log(results)
    results.csv.sort((a,b) ->
      return parseFloat(b["work on work"]) - parseFloat(a["work on work"])
    )

    @clearChildren()
    cilkprofTable = document.createElement('table')
    cilkprofTable.classList.add('cilkprof-table')

    headers = [
      {name: "Callsite (File and Line)", data: "file"},
      {name: "Line", data: "line"},
      {name: "Work", data: "work on work"},
      {name: "Executions (total)", data: "count on work"},
      {name: "Span", data: "span on span"},
      {name: "Executions (span)", data: "count on span"},
      {name: "Parallelism", data: "parallelism on work"},
      {name: "Local Work", data: "local work on work"},
      {name: "Local Span", data: "local span on span"}
    ]

    callsiteHeader = document.createElement('colgroup')
    callsiteHeader.span = 2
    cilkprofTable.appendChild(callsiteHeader)
    cilkprofTable.appendChild(document.createElement('colgroup')) for [2...headers.length]

    # Add the headers
    headerRow = document.createElement('thead')
    headers.forEach((header, index) ->
      if index is 1
        return
      headerRowEntry = document.createElement('th')
      headerRowEntry.textContent = header.name
      if index is 0
        headerRowEntry.colSpan = 2
      if header.name is "Work" or header.name is "Span" or header.name is "Local Work" or header.name is "Local Span"
        headerRowEntry.classList.add('cilkprof-table-toggle-raw')
        headerRowEntry.textContent += " (%)"
      headerRow.appendChild(headerRowEntry)
    , this)
    cilkprofTable.appendChild(headerRow)

    # Content
    tableBody = document.createElement('tbody')
    for result in results.csv
      entryRow = document.createElement('tr')
      for header in headers
        entryRowEntry = document.createElement('td')
        if header.name is "Work" or header.name is "Local Work"
          entryRowEntry.appendChild(@createBarGraphSpan(result[header.data], results.work))
        else if header.name is "Span" or header.name is "Local Span"
          entryRowEntry.appendChild(@createBarGraphSpan(result[header.data], results.span))
        else
          textWrapper = document.createElement('div')
          textWrapper.classList.add('cilkprof-table-text-wrapper')
          textWrapper.textContent = result[header.data]
          entryRowEntry.appendChild(textWrapper)
        if header.data is "file" or header.data is "line"
          textWrapper.classList.add('cilkprof-table-file-line')
          do (result) =>
            $(textWrapper).on('click', (e) =>
              Debug.log(result)
              atom.workspace.open(path.join(@path, result["file"]), {initialLine: +result["line"] - 1, initialColumn: Infinity})
              e.stopPropagation()
            )

        entryRowEntry.dataset.cilkprof = result[header.data]
        entryRow.appendChild(entryRowEntry)
      tableBody.appendChild(entryRow)

    cilkprofTable.appendChild(tableBody)
    @contentContainer.appendChild(cilkprofTable)

    $(cilkprofTable).on('click', 'th', (e) =>
      Debug.log(e)

      index = $(e.target).index()
      isAsc = false
      tableData = document.getElementsByClassName('cilkprof-table').item(0)
      tableData = tableData.getElementsByTagName('thead').item(0)
      if e.target.classList.contains('sort-asc')
        e.target.classList.remove('sort-asc')
        e.target.classList.add('sort-desc')
        $("colgroup").eq(index).addClass("highlighted")
      else if e.target.classList.contains('sort-desc')
        e.target.classList.remove('sort-desc')
        e.target.classList.add('sort-asc')
        $("colgroup").eq(index).addClass("highlighted")
        isAsc = true
      else
        for header in tableData.getElementsByTagName('th')
          header.classList.remove('sort-asc', 'sort-desc')
        $("colgroup").each((index, element) ->
          Debug.log(element)
          element.classList.remove('highlighted')
        )
        e.target.classList.add('sort-desc')
        $("colgroup").eq(index).addClass("highlighted")
      @sortTableByColumn(index + 1, isAsc)
    )

  sortTableByColumn: (columnIndex, isAsc) ->
    # Adapted from http://codereview.stackexchange.com/questions/37632/sorting-an-html-table-with-javascript
    # Read table body node.
    tableData = document.getElementsByClassName('cilkprof-table').item(0)
    tableData = tableData.getElementsByTagName('tbody').item(0)

    # Read table row nodes.
    rowData = tableData.getElementsByTagName('tr')
    # We aren't sorting by callsite if the index is greater than 1.
    if columnIndex > 1
      for i in [1 .. rowData.length - 1]
        rowI = parseFloat(rowData.item(i).getElementsByTagName('td').item(columnIndex).dataset.cilkprof)
        for j in [0 .. i - 1]
          rowJ = parseFloat(rowData.item(j).getElementsByTagName('td').item(columnIndex).dataset.cilkprof)
          if isAsc and rowI < rowJ
            tableData.insertBefore(rowData.item(i), rowData.item(j))
            break
          else if not isAsc and rowI > rowJ
            tableData.insertBefore(rowData.item(i), rowData.item(j))
            break
    # Special-case sorting by callsite, which will be columnIndex 1.
    else if columnIndex is 1
      for i in [1 .. rowData.length - 1]
        rowIFile = rowData.item(i).getElementsByTagName('td').item(0).dataset.cilkprof
        rowILine = parseInt(rowData.item(i).getElementsByTagName('td').item(1).dataset.cilkprof)
        for j in [0 .. i - 1]
          rowJFile = rowData.item(j).getElementsByTagName('td').item(0).dataset.cilkprof
          rowJLine = parseInt(rowData.item(j).getElementsByTagName('td').item(1).dataset.cilkprof)
          if isAsc and (rowIFile < rowJFile or (rowIFile is rowJFile and rowILine < rowJLine))
            tableData.insertBefore(rowData.item(i),rowData.item(j))
            break
          else if not isAsc and (rowIFile > rowJFile or (rowIFile is rowJFile and rowILine > rowJLine))
            tableData.insertBefore(rowData.item(i), rowData.item(j))
            break

  createBarGraphSpan: (raw, total) ->
    percent = parseFloat(raw) / total
    bar = document.createElement('div')
    bar.classList.add('cilkprof-table-work-bar-wrapper')
    percent100 = Math.round(percent * 10000) / 100
    innerBar = document.createElement('div')
    innerBar.classList.add('cilkprof-table-work-bar-load')
    innerBar.style.width = "#{percent100}%"
    text = document.createElement('div')
    text.classList.add('cilkprof-table-work-bar-text')
    text.classList.add('cilkprof-table-percent')
    text.textContent = "#{percent100}%"
    altText = document.createElement('div')
    altText.classList.add('cilkprof-table-work-bar-text')
    altText.classList.add('cilkprof-table-raw')
    altText.textContent = "#{parseFloat(raw).toLocaleString("en-US")}"

    interpolator = d3.interpolateRgb.gamma(2.2)("green", "red")
    innerBar.style.backgroundColor = interpolator(percent)
    innerBar.style.color = "white"
    bar.appendChild(innerBar)
    innerBar.appendChild(text)
    innerBar.appendChild(altText)

    $(bar).on('click', (event) =>
      $(".cilkprof-table").toggleClass("cilkprof-table-raw")
      if $(".cilkprof-table").hasClass("cilkprof-table-raw")
        $(".cilkprof-table-toggle-raw").text((index, text) ->
          brokenText = text.split(' ')
          brokenText = brokenText.slice(0, -1)
          newText = brokenText.join(' ') + " (cycles)"
        )
      else
        $(".cilkprof-table-toggle-raw").text((index, text) ->
          brokenText = text.split(' ')
          brokenText = brokenText.slice(0, -1)
          newText = brokenText.join(' ') + " (%)"
        )
    )
    return bar

  # Marker related functions

  createMarkers: (results) ->
    # Build a small cache of file path -> editor
    editorCache = {}
    editors = atom.workspace.getTextEditors()
    for textEditor in editors
      editorPath = normalizePath(textEditor.getPath?())
      if editorPath
        if editorPath in editorCache
          editorCache[editorPath].push(textEditor)
        else
          editorCache[editorPath] = [textEditor]

    # first aggregate results for every line
    cleanResults = {}
    for line in results.csv
      id = line["file"] + ':' + line["line"]
      if id in cleanResults
        for header in ["work on work", "span on span", "span on work"]
          cleanResults[id][header] += parseFloat(line[header])
        for header in ["count on work", "count on span"]
          cleanResults[id][header] = max(cleanResults[id][header], parseFloat(line[header]))
      else
        cleanResults[id] = {}
        for header in ["work on work", "span on span", "count on work", "count on span", "span on work"]
          cleanResults[id][header] = parseFloat(line[header])
    Debug.log("[cilkprof-ui]")
    Debug.log(cleanResults)

    for id in Object.getOwnPropertyNames(cleanResults)
      info = cleanResults[id]
      fileLineArray = id.split(':')
      filepath = path.join(@path, fileLineArray[0])
      fileline = +(fileLineArray[1])
      Debug.log("[cilkprof-ui] checking filepath #{filepath} : #{fileline}")
      if info["work on work"] / results.work > 0.01
        @markers[id] = new CilkprofMarkerView({
            work: info["work on work"]
            spanOnWork: info["span on work"]
            totalWork: results.work
            span: info["span on span"]
            totalSpan: results.span
            totalCount: info["count on work"]
            spanCount: info["count on span"]
        })
        do (id, fileline) =>
          editorCache[filepath]?.forEach((textEditor) =>
            @createCilkprofMarker(textEditor, id, fileline)
          )

  createCilkprofMarker: (editor, id, line) ->
    Debug.log("[cilkprof-marker] received #{line}")
    cilkprofGutter = editor.gutterWithName('cilkprof')
    range = new Range([line - 1, 0], [line - 1, Infinity])
    marker = editor.markBufferRange(range, {id: 'cilkprof'})
    cilkprofGutter.decorateMarker(marker, {type: 'gutter', item: @markers[id]})

  createMarkersForEditor: (editor) ->
    return if not editorPath = normalizePath(editor.getPath?())

    for id in Object.getOwnPropertyNames(@markers)
      Debug.log("[cilkprof-ui] checking id #{id}")
      violation = @markers[id]
      fileLineArray = id.split(':')
      filepath = fileLineArray[0]
      fileline = +(fileLineArray[1])
      Debug.log("[cilkprof-ui] checking filepath #{filepath} against #{editorPath}")

      if path.join(@path, filepath) is editorPath
        @createCilkprofMarker(editor, id, fileline)

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  clearChildren: () ->
    Debug.log("Clearing children...")

    $(@contentContainer).empty()
    $(@callgraphContainer).empty()

  # Tear down any state and detach
  destroy: ->
    Debug.log("Destroying plugin view")
    @element.remove()

  getElement: () ->
    return @element
