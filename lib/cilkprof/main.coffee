###
Main class for the Cilkprof module. Controls most of the core non-UI related
functionality of the Cilkprof mod.
###

CilkprofView = require('./ui')
CilkprofMarkerView = require('./cilkprof-marker-view')
Debug = require('../utils/debug')
Parser = require('./parser')

# Strings for parsing out the Cilkprof CSV easily. Should be synced with the
# variables in CilkprofParser.
CILKPROF_START = "cilkpride:cilkprof_start"
CILKPROF_END = "cilkpride:cilkprof_end"

module.exports =
class CilkprofModule

  @moduleName: "Cilkprof"  # Public-facing descriptor for this class
  @id: "cilkprof"          # Private-facing descriptor for this class

  view: null               # CilkprofUI object for the UI
  currentState: null       # Dictionary holding current state info on the module

  props: null              # Parent-specified properties
  changePanel: null        # Function that changes panel to Cilkprof view
  getSettings: null        # Function that retrieves updated settings
  onStateChange: null      # Function called when Cilkprof's state changes

  path: null               # Path for the project this module is acting on

  runner: null             # Runner object to execute Cilkprof on
  tab: null                # Tab object for the Cilkpride detail panel

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
      getSettings: (() => return @getSettings())
    })

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
