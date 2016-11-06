Parser = require('./parser')

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

    # @view = new CilkscreenView({
    #   changePanel: (() =>
    #     @changePanel()
    #     @tab.click()
    #   )
    #   path: @path
    # })

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
    @runner.spawn(@getSettings().cilkprofCommand, [], {}, (err, output) =>
      @runnerCallback(err, output)
    )
    @startState()

  runnerCallback: (err, output) ->
    settings = @getSettings(true)
    console.log("[cilkprof] Received code #{err}")
    console.log("[cilkprof] Received output #{output}")
    @currentState.output = output
    if err is 0
      Parser.parseResults(output, (results) =>
        console.log("[cilkprof] Received results")
        console.log(results)
      )
    else
      @updateState(err, null)

  generateUI: (parserResults) ->
    # @violations = parserResults
    # @view.createUI(parserResults)

  # State-based functions

  resetState: () ->
    console.log("[cilkprof] Resetting state.")
    @currentState.ready = true
    @currentState.startTime = null
    @onStateChange()

  # TODO: figure this out
  updateState: (err, results) ->
    console.log("[cilkprof] Update state.")
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
    console.log("[cilkprof] Start state.")
    @currentState.ready = false
    @currentState.startTime = Date.now()
    @tab.setState("busy")
    @onStateChange()

  registerEditor: (editor) ->
    # @view.createMarkersForEditor(editor)

  getView: () ->
    # return @view

  destroy: () ->
    @runner.destroy()
