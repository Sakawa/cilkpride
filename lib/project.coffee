{CompositeDisposable} = require('atom')
exec = require('child_process').exec
extend = require('util')._extend;
fs = require('fs')
path = require('path');
process = require('process')
spawn = require('child_process').spawn

FileLineReader = require('./utils/file-reader')
CustomSet = require('./utils/set')

CilkscreenModule = require('./cilkscreen/main')
SSHModule = require('./ssh-module')
FileSync = require('./file-sync')
Runner = require('./runner')

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
      start: null
      lastRuntime: null
      lastUpdated: null
      manual: false
    }
    @subscriptions = new CompositeDisposable()
    @refreshConfFile()

    @init()

    if @settings.hostname
      @sshMod = new SSHModule({settings: @settings, refreshConfFile: (() => @getUpdatedConf())})
      @sshMod.eventEmitter.on('ready', () =>
        console.log("[project] Received ready on SSHModule")
        @signalModules()
      )
      @fileSync = new FileSync({getSFTP: ((callback) => @getSFTP(callback))})

  # TODO: this is jank
  init: () ->
    # Initialize modules
    @cilkscreenMod = new CilkscreenModule({
      changePanel: (() => @changeDetailPanel(@path))
      onCloseCallback: (() => @onPanelCloseCallback())
      getConfSettings: ((refresh) => @getConfSettings(refresh))
      changeState: ((code) => @changeState("cilkscreen", code))
      runner: new Runner({
        getInstance: ((callback) => @getInstance(callback))
        settings: @settings
        refreshConfFile: (() => @getUpdatedConf())
      })
      path: @path
    })

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
      @settings = JSON.parse(fs.readFileSync(
        path.resolve(@path, 'cilkscreen-conf.json'),
        {
          flags: 'r',
          encoding: 'utf-8',
        }
      ))
      console.log(@settings)
      return true
    catch error
      @currentState.state = "conf_error"
      @currentState.lastUpdated = Date.now()
      @updateStatusTile()
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

    # # First change the directory to the folder where the Makefile is.
    # try
    #   process.chdir(@path)
    #   console.log("Successfully changed pwd to: #{@path}")
    # catch error
    #   console.err("Could not change pwd to #{@path} with error #{error}")
    #
    # # Invoke the cilkscreen target to run cilkscreen on.
    # makeThread = exec(@settings.makeCommand,
    #   (error, stdout, stderr) =>
    #     console.log("stdout: #{stdout}")
    #     console.log("stderr: #{stderr}")
    #     if error isnt null
    #       console.log('child process exited with code ' + error)
    #       @currentState.state = "make_error"
    #       @currentState.lastUpdated = Date.now()
    #       @updateStatusTile()
    #     else if not stdout.includes("Nothing to be done")
    @startModules()
   #)

  startModules: () ->
    if not @killModules(false)
      return

    # TODO: This should be turned into a cancellable promise, so that
    # we know when to modify the status bar to mark everything complete.
    # All the modules should be run in parallel (at least, up to the UI changes)
    @currentState.start = Date.now()
    @changeState("cilkscreen", "running")
    console.log("Just set cilkscreenTime #{@path} to #{@currentState.start}")
    console.log("Last runtime: #{@currentState.lastRuntime}")
    @cilkscreenMod.startThread()

  killModules: (force) ->
    console.log("Attempting to kill modules for path #{@path}...")
    if @currentState.manual and not force
      return false

    if @currentState.start?
      @currentState.start = null;

    clearInterval(@idleTimeout)
    if @currentState.start?
      @currentState.start = null;

    @cilkscreenMod.kill()
    @currentState.state = "ok"
    @currentState.manual = false
    return true

  ###
    Hooks
  ###

  registerEditor: (editor) ->
    console.log("Trying to register an editor with project path #{@path}.")
    console.log(editor)
    if editor.id not in @editorIds
      @editorIds.push(editor.id)

    # After the user stops changing the text, we start the timer to when we
    # initiate running cilktools.
    # stopChangeDisposable = editor.onDidStopChanging(()=>
    #   console.log("Editor stopped changing: " + editor.id)
    #   console.log("Current state: #{@currentState.state}")
    #   # if @currentState.state isnt "complete"
    #   #   console.log("Initializing timer with state as #{@currentState.state}")
    #   #   @initializeTimer()
    # )
    # changeDisposable = editor.onDidChange(()=>
    #   @clearTimer() if @idleTimeout
    # )
    saveDisposable = editor.onDidSave(()=>
      console.log("Saved!")
      @currentState.state = "ok"
      if @settings.hostname
        @fileSync.copyFile(path.relative(@settings.localBaseDir, editor.getPath()), true, () =>
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

  changeState: (moduleName, status) ->
    if status is "complete"
      @currentState.lastRuntime = Date.now() - @currentState.start
      console.log("Just set lastRuntime #{@path} to #{@currentState.lastRuntime}")
      console.log("The last run took #{@currentState.lastRuntime / 1000} seconds.")
    if status isnt "running"
      @currentState.manual = false
      @currentState.start = null
    @currentState.state = status
    @currentState.lastUpdated = Date.now()
    @updateStatusTile()

  # TODO: this needs to be generalized
  updateStatusTile: () ->
    console.log("Updating status bar for #{@path}, current path being #{@statusBar.getCurrentPath()}")
    console.log("Current state is #{@currentState.state}")
    if @path is @statusBar.getCurrentPath()
      if @currentState.state is "complete" or @currentState.state is "running"
        if @currentState.start
          if @currentState.lastRuntime
            @statusBar.displayCountdown(@currentState.start + @currentState.lastRuntime)
          else
            @statusBar.displayUnknownCountdown()
        else if @currentState.numViolations
          @statusBar.displayErrors(@currentState.numViolations, @currentState.lastUpdated)
        else
          @statusBar.displayNoErrors(@currentState.lastUpdated)
      else if @currentState.state is "make_error"
        @statusBar.displayMakeError(@currentState.lastUpdated)
      else if @currentState.state is "execution_error"
        @statusBar.displayExecError(@currentState.lastUpdated)
      else if @currentState.state is "conf_error"
        @statusBar.displayConfError(@currentState.lastUpdated)
      else if @currentState.state is "start"
        @statusBar.displayStart()

  manuallyRun: () ->
    @currentState.manual = true
    @killModules(true)
    @makeExecutable()

  manuallyCancel: () ->
    @killModules(true)
    @updateStatusTile()

  getConfSettings: (refresh) ->
    if refresh
      @refreshConfFile()
    return @settings

  # Core UI functions
  getDetailPanel: () ->
    return @cilkscreenMod.getDetailPanel()
