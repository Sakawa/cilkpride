{CompositeDisposable} = require('atom')
exec = require('child_process').exec
extend = require('util')._extend;
fs = require('fs')
path = require('path').posix;
process = require('process')
spawn = require('child_process').spawn

FileLineReader = require('./utils/file-reader')
CustomSet = require('./utils/set')
{normalizePath} = require('./utils/utils')

CilkideDetailPanel = require('./cilkide-detail-panel')
CilkscreenModule = require('./cilkscreen/main')
SSHModule = require('./ssh-module')
FileSync = require('./file-sync')
Runner = require('./runner')
Console = require('./console/console')

module.exports =
class Project
  idleTimeout: null
  currentState: null
  subscriptions: null
  editorSubscriptions: null
  editorIds: null
  projectView: null
  settings: null

  # Properties from parent
  props: null
  changeDetailPanel: null
  onPanelCloseCallback: null
  path: null
  statusBar: null

  # Module imports
  cilkscreenMod: null
  sshMod: null
  fileSync: null
  consoleMod: null

  # ui
  detailPanel: null

  constructor: (props) ->
    @props = props
    @path = props.path
    @changeDetailPanel = @props.changeDetailPanel
    @onPanelCloseCallback = @props.onPanelCloseCallback
    @statusBar = @props.statusBar
    console.log("Status bar for #{@path}")
    console.log(@statusBar)

    @editorSubscriptions = {}
    @editorIds = []
    @currentState = {
      state: "start"
    }
    @subscriptions = new CompositeDisposable()
    @detailPanel = new CilkideDetailPanel({
        onCloseCallback: (() => @onPanelCloseCallback())
    })

    @init()

  # TODO: this is jank
  init: () ->
    # Check the configuration file for errors first.
    if not @refreshConfFile()
      return

    # For each module, create a tab for it and initialize the module.
    @cilkscreenMod = new CilkscreenModule({
      changePanel: (() => @changeDetailPanel(@path))
      onCloseCallback: (() => @onPanelCloseCallback())
      getConfSettings: ((refresh) => @getConfSettings(refresh))
      onStateChange: (() => @updateState(true, @cilkscreenMod))
      runner: new Runner({
        getInstance: ((callback) => @getInstance(callback))
        settings: @settings
        refreshConfFile: (() => @getUpdatedConf())
      })
      path: @path
      tab: @detailPanel.registerModuleTab("Cilksan", (() => return @cilkscreenMod.getDetailPanel()))
    })

    @consoleMod = new Console({
      tab: @detailPanel.registerModuleTab("Console", (() => return @consoleMod.getDetailPanel()))
    })

    @consoleMod.registerModule(@cilkscreenMod.name)

    if @settings.sshEnabled
      @sshMod = new SSHModule({settings: @settings, refreshConfFile: (() => @getUpdatedConf())})
      @sshMod.eventEmitter.on('ready', () =>
        console.log("[project] Received ready on SSHModule")
        @signalModules()
      )
      @fileSync = new FileSync({getSFTP: ((callback) => @getSFTP(callback))})

  updateState: (repressUpdate, module) ->
    console.log("[project] Updating status bar for #{@path}, current path being #{@statusBar.getCurrentPath()}")
    console.log("[project] Current state is #{@currentState.state}")

    if module and module.currentState.output
      @consoleMod.updateOutput(module.name, module.currentState.output)

    if @path isnt @statusBar.getCurrentPath()
      console.log("[project] status bar: path mismatch")
      return

    # Global project states take priority - config errors, etc.
    if @currentState.state is "config_error"
      console.log("[project] status bar: config error")
      return @statusBar.displayConfigError(repressUpdate)

    # Modules still loading...
    if not @cilkscreenMod.currentState.initialized
      console.log("[project] status bar: cilkscreen not init'd")
      return @statusBar.displayLoading(repressUpdate)

    # All modules loaded, display status based off if (in priority)
    # 1. Any module is still running
    # 2. Any module is reporting a execution error
    # 3. Any module is reporting a error
    # 4. All modules are reporting start.
    # 4. All modules are reporting OK.
    if not @cilkscreenMod.currentState.ready
      if @cilkscreenMod.currentState.lastRuntime
        return @statusBar.displayCountdown(@cilkscreenMod.currentState.startTime +
          @cilkscreenMod.currentState.lastRuntime)
      else
        return @statusBar.displayCountdown()

    if @cilkscreenMod.currentState.state is "execution_error"
      return @statusBar.displayExecutionError(repressUpdate)

    if @cilkscreenMod.currentState.state is "error"
      return @statusBar.displayErrors(repressUpdate)

    if @cilkscreenMod.currentState.state is "start"
      return @statusBar.displayStart(repressUpdate)

    console.log("[project] status bar: fallthrough")
    @statusBar.displayNoErrors(repressUpdate)

    return

  signalModules: () ->
    @fileSync.updateSFTP()
    @cilkscreenMod.updateInstance()

  getInstance: (callback) ->
    @sshMod.getInstance(callback)

  getSFTP: (callback) ->
    @sshMod.getSFTP(callback)

  sync: (localToRemote) ->
    @fileSync.copyFolder('/', localToRemote)

  # Timer functions
  initializeTimer: () ->
    clearInterval(@idleTimeout) if @idleTimeout
    @idleTimeout = setTimeout(
      () =>
        console.log("Idle timeout start! #{new Date()}")
        @makeExecutable()
        @idleTimeout = null
      , atom.config.get('cilkide.idleSeconds') * 1000
    )

  clearTimer: () ->
    @killModules(false)

  # TODO: need error handling
  refreshConfFile: () ->
    try
      console.log(path.join(@path, 'cilkide-conf.json'))
      @settings = JSON.parse(fs.readFileSync(
        path.join(@path, 'cilkide-conf.json'),
        {
          flags: 'r',
          encoding: 'utf-8',
        }
      ))
      console.log(@settings)
      return true
    catch error
      @currentState.state = "config_error"
      @updateState()
      atom.notifications.addError("Cilkide was unable to read #{path.join(@path, 'cilkide-conf.json')}.
        Please make sure the configuration file is correctly formatted.")
      return false

  getUpdatedConf: () ->
    @refreshConfFile()
    return @settings

  # Uses the cilkscreen target in the Makefile to make the executable so that
  # we can use cilkscreen on the executable.
  makeExecutable: () ->
    # Refresh the configuration to make sure it's up to date.
    if not @refreshConfFile()
      return

    @startModules()

  startModules: () ->
    if not @killModules(false)
      return

    @cilkscreenMod.startThread()

  killModules: (force) ->
    console.log("Attempting to kill modules for path #{@path}...")
    if @currentState.manual and not force
      return false

    clearInterval(@idleTimeout)

    @cilkscreenMod.kill()
    return true

  ###
    Hooks
  ###

  registerEditor: (editor) ->
    console.log("Trying to register an editor with project path #{@path}.")
    console.log(editor)
    if editor.id not in @editorIds
      @editorIds.push(editor.id)

    saveDisposable = editor.onDidSave(()=>
      console.log("Saved!")

      # If the project did not create modules because of a config error,
      # try to init when the error is fixed.
      if @currentState.state is "config_error"
        if @refreshConfFile()
          @init() if not @cilkscreenMod
        else return

      if @sshMod
        @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(editor.getPath())), true, () =>
          console.log("Initializing timer with state as #{@currentState.state}")
          @initializeTimer()
        )
      else
        @initializeTimer()
    )

    @editorSubscriptions[editor.id] = [saveDisposable]
    # @subscriptions.add(changeDisposable)
    # @subscriptions.add(stopChangeDisposable)
    @subscriptions.add(saveDisposable)

  # Uh, why do we need this? probably for minimap maintenance
  updateActiveEditor: () ->
    console.log("Called active editor in project")
    @cilkscreenMod.updateActiveEditor()

  unregisterEditor: (editorId) ->
    for disposable in @editorSubscriptions[editorId]
      @subscriptions.remove(disposable)
    delete @editorSubscriptions[editorId]
    index = @editorIds.indexOf(editorId)
    @editorIds.splice(index, 1)

  getConfSettings: (refresh) ->
    if refresh
      @refreshConfFile()
    return @settings

  # Core UI functions
  getDetailPanel: () ->
    return @detailPanel
