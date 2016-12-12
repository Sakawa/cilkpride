###
Main class for the Cilksan module. Controls most of the core non-UI related
functionality of the Cilksan mod.
###

CilksanView = require('./ui')
Debug = require('../utils/debug')
Parser = require('./parser')

module.exports =
class CilksanModule

  @moduleName: "Cilksan"   # Public-facing descriptor for this class
  @id: "cilksan"           # Private-facing descriptor for this class

  view: null               # CilksanView object for the Cilksan detail panel
  currentState: null       # Object containing lots of state-related info

  props: null              # Object containing parent-specified properties
  changePanel: null        # Callback to show the Cilksan detail panel for current project
  getSettings: null        # Function to retrieve updated project config settings
  onStateChange: null      # Callback to let Project class know that this module's state has changed

  violations: null         # Violations detected from the last run of Cilksan
  path: null               # Path of the Cilkpride project this is running

  runner: null             # Runner object to run command line tools
  tab: null                # Tab object to update status on the detail panel tabs

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
      ready: not @getSettings().sshEnabled
      state: "start"
      lastUpdated: null
      lastSuccessful: null
      startTime: null
      lastRuntime: null
      output: null
      initialized: not @getSettings().sshEnabled
    }

    @view = new CilksanView({
      changePanel: (() =>
        @changePanel()
        @tab.click()
      )
      path: @path
    })

    atom.commands.add('atom-workspace', 'cilkpride:debug', () =>
      Debug.log("[debug]")
      Debug.log(@currentState)
    )

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
    @runner.spawn(@getSettings().cilksanCommand, [], {}, (err, output) =>
      @runnerCallback(err, output)
    )
    @startState()

  runnerCallback: (err, output) ->
    settings = @getSettings(true)
    Debug.log("[cilksan] Received code #{err}")
    Debug.log("[cilksan] Received output #{output}")
    @currentState.output = output
    if err is 0
      Debug.log("[cilksan] Killing old markers, if any...")
      Debug.log("[cilksan] Parsing data...")
      Parser.processViolations(output, (results) =>
        @updateState(err, results)
        @generateUI(results)
      , settings.remoteBaseDir, settings.localBaseDir)
    else
      @updateState(err, null)

  generateUI: (parserResults) ->
    @violations = parserResults
    @view.createUI(parserResults)

  # State-based functions

  resetState: () ->
    Debug.log("[cilksan] Resetting state.")
    @currentState.ready = true
    @currentState.startTime = null
    @onStateChange()

  # TODO: figure this out
  updateState: (err, results) ->
    Debug.log("[cilksan] Update state.")
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
      if results.length > 0
        @currentState.state = "error"
      else
        @currentState.state = "ok"
    @tab.setState(@currentState.state)
    @resetState()
    @onStateChange()

  startState: () ->
    Debug.log("[cilksan] Start state.")
    @currentState.ready = false
    @currentState.startTime = Date.now()
    @tab.setState("busy")
    @onStateChange()

  registerEditor: (editor) ->
    @view.createMarkersForEditor(editor)

  getView: () ->
    return @view

  destroy: () ->
    @runner.destroy()
    @view.destroyOldMarkers()
