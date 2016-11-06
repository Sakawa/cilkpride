CilkscreenView = require('./ui')
Parser = require('./parser')

module.exports =
class CilkscreenModule

  view: null
  currentState: null
  name: "Cilksan"

  props: null
  changePanel: null
  getSettings: null
  onStateChange: null

  violations: null
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

    @view = new CilkscreenView({
      changePanel: (() =>
        @changePanel()
        @tab.click()
      )
      path: @path
    })

    atom.commands.add('atom-workspace', 'cilkpride:debug', () =>
      console.log("[debug]")
      console.log(@currentState)
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

  # TODO: the modules should push updates to the project class, which will manage everything
  startThread: () ->
    @runner.spawn(@getSettings().cilksanCommand, [], {}, (err, output) =>
      @runnerCallback(err, output)
    )
    @startState()

  runnerCallback: (err, output) ->
    settings = @getSettings(true)
    console.log("[cilkscreen] Received code #{err}")
    console.log("[cilkscreen] Received output #{output}")
    @currentState.output = output
    if err is 0
      console.log("[cilkscreen] Killing old markers, if any...")
      console.log("[cilkscreen] Parsing data...")
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
    console.log("[cilksan] Resetting state.")
    @currentState.ready = true
    @currentState.startTime = null
    @onStateChange()

  # TODO: figure this out
  updateState: (err, results) ->
    console.log("[cilksan] Update state.")
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
    console.log("[cilksan] Start state.")
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
