{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path').posix;
chokidar = require('chokidar')

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
  settings: null
  configWatch: null

  directoryWatch: null

  # Properties from parent
  props: null
  changeDetailPanel: null
  onPanelCloseCallback: null
  onDestroy: null
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
    @onDestroy = @props.onDestroy

    @editorSubscriptions = {}
    @editorIds = []
    @currentState = {
      state: "start"
    }
    @subscriptions = new CompositeDisposable()
    @detailPanel = new CilkideDetailPanel({
        onCloseCallback: (() => @onPanelCloseCallback())
    })

    @refreshConfFile()
    # Set a watch so that we know when the configuration file is changed.
    @configWatch = chokidar.watch(path.join(@path, 'cilkpride-conf.json'))
    @configWatch.on('change', (path) =>
      console.log("[project] Received watch (change) notification on config")
      @refreshConfFile()
      console.log("Refreshed config file, state is #{@currentState.state}")
      if @currentState.state is "ok" and not @cilkscreenMod
        @init()
    ).on('unlink', (path) =>
      console.log("[project] Received watch (unlink) notification on config")
      @onDestroy()
    )

    atom.commands.add('atom-workspace', 'cilkpride:debug', () =>
      console.log("[debug] Wow! Debug!")
    )

    @init()

  init: () ->
    # Check the configuration file for errors first.
    return if @currentState.state is "config_error"

    # For each module, create a tab for it and initialize the module.
    @cilkscreenMod = new CilkscreenModule({
      changePanel: (() => @changeDetailPanel(@path))
      getSettings: (() => return @settings)
      onStateChange: (() => @updateState(false, @cilkscreenMod))
      runner: new Runner({
        getInstance: ((callback) => @getInstance(callback))
        getSettings: (() => return @settings)
      })
      path: @path
    })

    @consoleMod = new Console({})

    @cilkscreenMod.tab = @detailPanel.registerModuleTab("Cilksan", @cilkscreenMod.getView())
    @consoleMod.tab = @detailPanel.registerModuleTab("Console", @consoleMod)

    @consoleMod.registerModule(@cilkscreenMod.name)

    if @settings.sshEnabled
      @sshMod = new SSHModule({getSettings: (() => return @settings)})
      @sshMod.eventEmitter.on('ready', () =>
        console.log("[project] Received ready on SSHModule")
        @signalModules()
      )
      @fileSync = new FileSync({getSFTP: ((callback) => @getSFTP(callback))})
    else
      @createDirectoryWatch

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
    # Start watching directories when FileSync is good to go.
    @fileSync.updateSFTP((() => @createDirectoryWatch()))
    @cilkscreenMod.updateInstance()

  createDirectoryWatch: () ->
    console.log("[project] in createDirectoryWatch")
    return if @directoryWatch or not atom.config.get('cilkpride.watchDirectory', false)

    @directoryWatch = chokidar.watch(@path, {ignored: /[\/\\]\./, persistent: true})

    @directoryWatch.on('add', (filePath) =>
      console.log("File #{filePath} has been added")
      if @settings.sshEnabled
        @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(filePath)), true, @settings, () =>
          console.log("[project] Initializing timer with state as #{@currentState.state}")
          @initializeTimer()
        )
      else
        @initializeTimer()
    )
    @directoryWatch.on('change', (filePath) =>
      console.log("File #{filePath} has been changed")
      if @settings.sshEnabled
        @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(filePath)), true, @settings, () =>
          console.log("[project] Initializing timer with state as #{@currentState.state}")
          @initializeTimer()
        )
      else
        @initializeTimer()
    )
    # TODO: For now, don't clean up, but consider removing old files on remote
    @directoryWatch.on('unlink', (filePath) =>
      console.log("File #{filePath} has been removed")
      if @settings.sshEnabled
        @fileSync.unlink(path.relative(@settings.localBaseDir, normalizePath(filePath)), @settings) if @fileSync
    )
    @directoryWatch.on('unlinkDir', (filePath) =>
      console.log("[project] Directory #{filePath} has been removed")
      if @settings.sshEnabled
        @fileSync.rmdir(path.relative(@settings.localBaseDir, normalizePath(filePath)), @settings) if @fileSync
    )

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
      , atom.config.get('cilkpride.idleSeconds') * 1000
    )

  clearTimer: () ->
    @killModules()

  refreshConfFile: () ->
    checkSettings = (settings) ->
      console.log("[project] Checking settings...")
      return false unless settings.cilksanCommand
      if settings.sshEnabled
        return false unless settings.username?.trim?().split(' ').length is 1
        return false unless settings.hostname?.trim?().split(' ').length is 1
        return false unless settings.localBaseDir # Windows can have spaces.
        return false unless settings.remoteBaseDir?.trim?().split(' ').length is 1
        return false unless typeof settings.port is "number"
        return false unless settings.syncIgnoreDir?.constructor is Array
        return false unless settings.syncIgnoreFile?.constructor is Array
      return true

    try
      console.log(path.join(@path, 'cilkpride-conf.json'))
      @settings = JSON.parse(fs.readFileSync(
        path.join(@path, 'cilkpride-conf.json'),
        {
          flags: 'r',
          encoding: 'utf-8',
        }
      ))
      throw new Error() if not checkSettings(@settings)
      console.log(@settings)
      @currentState.state = "ok"
      return true
    catch error
      @currentState.state = "config_error"
      @updateState()
      atom.notifications.addError("Cilkpride was unable to read #{path.join(@path, 'cilkpride-conf.json')}.
        Please make sure the configuration file is correctly formatted, and the appropriate fields are filled out.")
      return false

  # Uses the cilkscreen target in the Makefile to make the executable so that
  # we can use cilkscreen on the executable.
  makeExecutable: () ->
    # Refresh the configuration to make sure it's up to date.
    return if @currentState.state is "config_error"

    @startModules()

  startModules: () ->
    @cilkscreenMod.startThread()

  killModules: () ->
    console.log("Attempting to kill modules for path #{@path}...")
    clearInterval(@idleTimeout)

    @cilkscreenMod.kill()
    return true

  # Hooks

  registerEditor: (editor) ->
    console.log("[project] Trying to register an editor with project path #{@path}.")
    console.log(editor)
    if editor.id not in @editorIds
      @editorIds.push(editor.id)

    if not atom.config.get('cilkpride.watchDirectory', false)
      saveDisposable = editor.onDidSave(()=>
        console.log("Saved!")

        if @sshMod
          @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(editor.getPath())), true, @settings, () =>
            console.log("[project] Initializing timer with state as #{@currentState.state}")
            @initializeTimer()
          )
        else
          @initializeTimer()
      )

      @editorSubscriptions[editor.id] = saveDisposable
      @subscriptions.add(saveDisposable)
    @cilkscreenMod.registerEditor(editor) if @cilkscreenMod

  unregisterEditor: (editorId) ->
    @subscriptions.remove(@editorSubscriptions[editorId])
    delete @editorSubscriptions[editorId]
    index = @editorIds.indexOf(editorId)
    @editorIds.splice(index, 1)

  # Core UI functions
  getDetailPanel: () ->
    return @detailPanel

  destroy: () ->
    @subscriptions.dispose()

    @cilkscreenMod.destroy() if @cilkscreenMod
    @sshMod.destroy() if @sshMod
    @fileSync.destroy() if @fileSync
    @consoleMod.destroy() if @consoleMod
    @configWatch.close() if @configWatch
    @watchDirectory.close() if @watchDirectory
