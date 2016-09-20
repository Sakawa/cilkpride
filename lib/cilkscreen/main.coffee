extend = require('util')._extend;
process = require('process')
spawn = require('child_process').spawn

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

  constructor: (props) ->
    @props = props
    @onCloseCallback = props.onCloseCallback
    @changePanel = props.changePanel
    @getConfSettings = props.getConfSettings
    @changeState = props.changeState

    @view = new CilkscreenView({
      onCloseCallback: (() => @onCloseCallback())
      changePanel: (() => @changePanel())
    })

  # TODO: where do I put the state and status bar updates for multiple modules?
  # TODO: the modules should push updates to the project class, which will manage everything
  startThread: () ->
    # Ensure only one cilkscreen thread per project is active.
    @killThread(false)

    cilkLibPath = atom.config.get('cilkide.cilkLibPath')
    cilktoolsPath = atom.config.get('cilkide.cilktoolsPath')

    console.log(process.env)
    envCopy = extend({'LD_LIBRARY_PATH': cilkLibPath, 'LIBRARY_PATH': cilkLibPath}, process.env)
    envCopy.PATH = envCopy.PATH + ":" + cilktoolsPath

    @thread = spawn('cilkscreen', @getConfSettings(false).commandArgs, {env: envCopy})
    cilkscreenOutput = ""

    @thread.stderr.on('data', (data) ->
      cilkscreenOutput += data
    )

    @thread.on('close', (code) =>
      console.log("stderr: #{cilkscreenOutput}")
      console.log("cilkscreen process exited with code #{code}")
      if code is 0
        console.log("Killing old markers, if any...")
        @view.destroyOldMarkers()
        console.log("Parsing data...")
        Parser.processViolations(cilkscreenOutput, ((results) => @generateUI(results)))
      else
        console.log("Code not 0...")
        @changeState("execution_error")
    )

    # Debug event handlers
    @thread.on('error', (err) =>
      console.log("cilkscreen thread error: #{err}")
      @changeState("execution_error")
    )

    @thread.on('exit', (code, signal) =>
      if code?
        console.log("cilkscreen exit: code #{code}")
      if signal?
        console.log("cilkscreen exit: signal #{signal}")
    )

  generateUI: (parserResults) ->
    @violations = parserResults
    @changeState("complete")
    @view.createUI(parserResults)

  killThread: () ->
    if @thread
      console.log(@thread)
      @thread.kill('SIGKILL')
      console.log("Killed thread...?")
      console.log(@thread)
      @thread = null

  updateActiveEditor: () ->
    return

  getDetailPanel: () ->
    return @view.getElement()
