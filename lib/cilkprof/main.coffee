Parser = require('./parser')
CilkprofView = require('./ui')
CilkprofMarkerView = require('./cilkprof-marker-view')
Debug = require('../utils/debug')

CILKPROF_START = "cilkpride:cilkprof_start"
CILKPROF_END = "cilkpride:cilkprof_end"

module.exports =
class CilkprofModule

  view: null
  currentState: null
  name: "Cilkprof"

  props: null
  changePanel: null
  getSettings: null
  onStateChange: null

  path: null

  runner: null
  tab: null

  constructor: (props) ->
    @props = props
    @onCloseCallback = props.onCloseCallback
    @changePanel = props.changePanel
    @getSettings = props.getSettings
    @runner = props.runner
    @path = props.path
    @onStateChange = props.onStateChange
    @tab = props.tab

    @currentState = {
      ready: false
      state: "start"
      lastUpdated: null
      lastSuccessful: null
      startTime: null
      lastRuntime: null
      output: null
      initialized: not @getSettings().sshEnabled
    }

    @view = new CilkprofView({
      changePanel: (() =>
        @changePanel()
        @tab.click()
      )
      path: @path
    })

    # debug below
    # atom.commands.add('atom-workspace', 'cilkpride:debug', (event) =>
    #   @debugTest()
    # )

  updateInstance: () ->
    @currentState.initialized = false
    @tab.setState("initializing")
    @resetState()
    @runner.getNewInstance(() =>
      @currentState.initialized = true
      @tab.setState(@currentState.state)
      @resetState()
    )

  kill: () ->
    if @runner.kill()
      @resetState()

  startThread: () ->
    @runner.spawn(@getSettings().cilkprofCommand + " && echo '#{CILKPROF_START}' && cat cilkprof_cs_0.csv && echo '#{CILKPROF_END}'", [], {}, (err, output) =>
      @runnerCallback(err, output)
    )
    @startState()

  runnerCallback: (err, output) ->
    settings = @getSettings(true)
    Debug.log("[cilkprof] Received code #{err}")
    Debug.log("[cilkprof] Received output #{output}")
    if output.indexOf(CILKPROF_START) isnt -1 and output.indexOf(CILKPROF_END)
      @currentState.output = output.substring(0, output.indexOf(CILKPROF_START))
      @currentState.output += output.substring(output.indexOf(CILKPROF_END) + CILKPROF_END.length)
    else
      @currentState.output = output
    if err is 0
      results = Parser.parseResults(output)
      @generateUI(results)
      @updateState(err, output)
    else
      @updateState(err, null)

  generateUI: (parserResults) ->
    # @violations = parserResults
    Debug.log(parserResults)
    @view.createUI(parserResults)

  # State-based functions

  resetState: () ->
    Debug.log("[cilkprof] Resetting state.")
    @currentState.ready = true
    @currentState.startTime = null
    @onStateChange()

  # TODO: figure this out
  updateState: (err, results) ->
    Debug.log("[cilkprof] Update state.")
    @currentState.lastUpdated = Date.now()

    # Shortcircuit if err is actually null
    if err is null
      @onStateChange()
      return

    if err
      @currentState.state = "execution_error"
    else
      @currentState.lastSuccessful = Date.now()
      @currentState.lastRuntime = Date.now() - @currentState.startTime
      if results is null
        @currentState.state = "error"
      else
        @currentState.state = "ok"
    @tab.setState(@currentState.state)
    @resetState()
    @onStateChange()

  startState: () ->
    Debug.log("[cilkprof] Start state.")
    @currentState.ready = false
    @currentState.startTime = Date.now()
    @tab.setState("busy")
    @onStateChange()

  getView: () ->
    return @view

  destroy: () ->
    @runner.destroy()

  registerEditor: (editor) ->
    @view.createMarkersForEditor(editor)

  ####
  debugTest: () ->
    info = {
      work: 90
      totalWork: 100
      span: 50
      totalSpan: 100
      totalCount: 1000000000
      spanCount: 500
    }

    currentTE = atom.workspace.getActiveTextEditor()
    for marker in currentTE.findMarkers()
        marker.destroy()
    if gutter = currentTE.gutterWithName('cilkpride-debug')
      gutter.destroy()
    newGutter = currentTE.addGutter({name: 'cilkpride-debug', priority: -101, visible: true})
    Debug.log(newGutter)

    # Create gutter test
    cilkprofMarker = new CilkprofMarkerView(info)
    marker = currentTE.markBufferRange([[1, 0], [1, Infinity]])
    newGutter.decorateMarker(marker, {type: 'gutter', item: cilkprofMarker})

    info2 = {
      work: 10
      totalWork: 100
      span: 30
      totalSpan: 100
      totalCount: 10000
      spanCount: 98
    }
    cilkprofMarker2 = new CilkprofMarkerView(info2)
    marker2 = currentTE.markBufferRange([[2,0], [2, Infinity]])
    newGutter.decorateMarker(marker2, {type: 'gutter', item: cilkprofMarker2})
