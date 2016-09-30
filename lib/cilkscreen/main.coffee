extend = require('util')._extend;
process = require('process')

Parser = require('./parser')
CilkscreenView = require('./ui')

module.exports =
class CilkscreenModule

  view: null
  currentState: null
  settings: null

  props: null
  onCloseCallback: null
  changePanel: null
  getConfSettings: null
  changeState: null
  thread: null
  violations: null
  path: null

  runner: null

  constructor: (props) ->
    @props = props
    @onCloseCallback = props.onCloseCallback
    @changePanel = props.changePanel
    @getConfSettings = props.getConfSettings
    @changeState = props.changeState
    @runner = props.runner
    @path = props.path

    @view = new CilkscreenView({
      onCloseCallback: (() => @onCloseCallback())
      changePanel: (() => @changePanel())
    })

  updateInstance: () ->
    @runner.getNewInstance()

  kill: () ->
    @runner.kill()

  # TODO: where do I put the state and status bar updates for multiple modules?
  # TODO: the modules should push updates to the project class, which will manage everything
  startThread: () ->
    @runner.spawn(@getConfSettings(true).cilksanCommand, [], {}, (err, output) =>
      @runnerCallback(err, output)
    )

  runnerCallback: (err, output) ->
    settings = @getConfSettings(true)
    console.log("[cilkscreen] Received code #{err}")
    console.log("[cilkscreen] Received output #{output}")
    if err is 0
      console.log("[cilkscreen] Killing old markers, if any...")
      @view.destroyOldMarkers()
      console.log("[cilkscreen] Parsing data...")
      Parser.processViolations(output, ((results) => @generateUI(results)), settings.remoteBaseDir, settings.localBaseDir)

  generateUI: (parserResults) ->
    @violations = parserResults
    @changeState("complete")
    @view.createUI(parserResults)

  updateActiveEditor: () ->
    return

  getDetailPanel: () ->
    return @view.getElement()
