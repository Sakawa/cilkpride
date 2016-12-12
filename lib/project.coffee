###
This file represents a Cilkpride project, and handles all project-level actions.
A Cilkpride project consists of a directory that contains a Cilkpride config
file and all subdirectories.
###

chokidar = require('chokidar')
{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path').posix;

CilkprideDetailPanel = require('./cilkpride-detail-panel')
CilksanModule = require('./cilksan/main')
CilkprofModule = require('./cilkprof/main')
Console = require('./console/console')
Debug = require('./utils/debug')
FileSync = require('./file-sync')
{normalizePath} = require('./utils/utils')
Runner = require('./runner')
SSHModule = require('./ssh-module')

# The non-essential modules are declared here. Since the goal of these modules
# is to be fairly plug-and-play, if additional modules are created, they should
# be placed in this array and initialized automatically.
MODULES_ENABLED = [CilksanModule, CilkprofModule]

module.exports =
class Project
  idleTimeout: null           # timeout before the project starts running the modules
  currentState: null          # string representing the current state of the project
  subscriptions: null         # CompositeDisposable for text editor hooks
  editorSubscriptions: null   # dictionary (editor ID -> text editor Disposables)
  editorIds: null             # Array containing editor IDs for this project
  settings: null              # Object containing the config file settings for this project
  configWatch: null           # FileWatch for the project config file
  directoryWatch: null        # FileWatch for the project directory/subdirectories

  # Properties from parent
  props: null                 # Object containing parent-specified properties
  changeDetailPanel: null     # Callback to show this project's detail panel
  onPanelCloseCallback: null  # Callback to hide this project's detail panel
  onDestroy: null             # Callback when this project is destroyed
  path: null                  # String for this project's root directory (where the config file is)
  statusBar: null             # StatusBar to control the displayed status in the editor

  # Module imports
  modules: null               # Array containing the initialized non-essential modules
  sshMod: null                # (Essential) Module for SSH connections
  consoleMod: null            # (Essential) Module for displaying console output
  fileSync: null              # (Essential) Module for SFTP file syncing

  # ui
  detailPanel: null           # Element containing this project's detail panel UI

  constructor: (props) ->
    @props = props
    @path = props.path
    @changeDetailPanel = @props.changeDetailPanel
    @onPanelCloseCallback = @props.onPanelCloseCallback
    @statusBar = @props.statusBar
    @onDestroy = @props.onDestroy

    @editorSubscriptions = {}
    @editorIds = []
    @subscriptions = new CompositeDisposable()
    @detailPanel = new CilkprideDetailPanel({
        onCloseCallback: (() => @onPanelCloseCallback())
    })
    @currentState = "start"

    @refreshConfFile()

    # Set a watch so that we know when the configuration file is changed.
    @configWatch = chokidar.watch(path.join(@path, 'cilkpride-conf.json'))
    @configWatch.on('change', (path) =>
      Debug.log("[project] Received watch (change) notification on config")
      @refreshConfFile()
      Debug.log("Refreshed config file, state is #{@currentState}")
      if @currentState is "ok" and not @modules
        @init()
    ).on('unlink', (path) =>
      Debug.log("[project] Received watch (unlink) notification on config")
      @onDestroy()
    )

    @init()

  init: () ->
    # Check the configuration file for errors first.
    return if @currentState is "config_error"

    @consoleMod = new Console({})

    # For each module, create a tab for it and initialize the module.
    @modules = MODULES_ENABLED.map((obj) =>
      module = new obj({
        changePanel: (() => @changeDetailPanel(@path))
        getSettings: (() => return @settings)
        onStateChange: (() => @updateState(false, module))
        runner: new Runner({
          getInstance: ((callback) => @getInstance(callback))
          getSettings: (() => return @settings)
          moduleName: obj.id
        })
        path: @path
      })
      module.tab = @detailPanel.registerModuleTab(obj.moduleName, module.getView())
      @consoleMod.registerModule(obj.moduleName)
      return module
    )

    @consoleMod.tab = @detailPanel.registerModuleTab("Console", @consoleMod)

    if @settings.sshEnabled
      @sshMod = new SSHModule({
        getSettings: (() => return @settings)
        onStateChange: (() => @updateState(false))
      })
      @sshMod.eventEmitter.on('ready', () =>
        Debug.log("[project] Received ready on SSHModule")
        @signalModules()
      )
      @sshMod.startConnection()
      @fileSync = new FileSync({getSFTP: ((callback) => @getSFTP(callback))})
    else
      @createDirectoryWatch()

  updateState: (repressUpdate, module) ->
    Debug.log("[project] Updating status bar for #{@path}, current path being #{@statusBar.getCurrentPath()}")
    Debug.log("[project] Current state is #{@currentState}")
    Debug.log(@settings)

    if module and module.currentState.output
      @consoleMod.updateOutput(module.constructor.moduleName, module.currentState.output)

    if @path isnt @statusBar.getCurrentPath()
      Debug.log("[project] status bar: path mismatch")
      return

    # Global project states take priority - config errors, etc.
    if @currentState is "config_error"
      Debug.log("[project] status bar: config error")
      return @statusBar.displayConfigError(repressUpdate)

    # SSH statuses take next priority
    if @settings.sshEnabled and @sshMod
      if @sshMod.state is "not_connected"
        Debug.log("[project] status bar: not connected")
        return @statusBar.displayNotConnected(repressUpdate)

      # SSHModule still loading...
      if @sshMod.state is "connecting"
        Debug.log("[project] status bar: sshMod still connecting")
        return @statusBar.displayLoading(repressUpdate)

    # All modules loaded, display status based off if (in priority)
    # 1. Any module is still running
    # 2. Any module is reporting a execution error
    # 3. Any module is reporting a error
    # 4. All modules are reporting start.
    # 5. All modules are reporting OK.
    if @modules
      # Priority 1 - we need to find the longest ETA and display that.
      longestETA = -1
      etaModule = null
      for module in @modules
        if not module.currentState.ready and module.currentState.lastRuntime > longestETA
          longestETA = module.currentState.lastRuntime
          etaModule = module
      if etaModule
        if longestETA > 0
          return @statusBar.displayCountdown(etaModule.currentState.startTime +
            longestETA)
        else
          return @statusBar.displayCountdown()

      # Priorities 2-5
      statuses = @modules.map((module) -> return module.currentState.state)
      if "execution_error" in statuses
        return @statusBar.displayExecutionError(repressUpdate)

      if "error" in statuses
        return @statusBar.displayErrors(repressUpdate)

      if "start" in statuses
        return @statusBar.displayStart(repressUpdate)

    Debug.log("[project] status bar: fallthrough")
    @statusBar.displayNoErrors(repressUpdate)

    return

  connectSSH: () ->
    @sshMod.startConnection()

  signalModules: () ->
    # Start watching directories when FileSync is good to go.
    @fileSync.updateSFTP((() => @createDirectoryWatch()))
    module.updateInstance() for module in @modules

    @currentState = "ok"

  createDirectoryWatch: () ->
    Debug.log("[project] in createDirectoryWatch")
    return if @directoryWatch or not atom.config.get('cilkpride.generalSettings.watchDirectory', false)

    @directoryWatch = chokidar.watch(@path, {ignored: /[\/\\]\./, persistent: true})

    @directoryWatch.on('add', (filePath) =>
      Debug.log("File #{filePath} has been added")
      if @settings.sshEnabled
        @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(filePath)), true, @settings, () =>
          Debug.log("[project] Initializing timer with state as #{@currentState}")
          @initializeTimer()
        )
      else
        @initializeTimer()
    )
    @directoryWatch.on('change', (filePath) =>
      Debug.log("File #{filePath} has been changed")
      if @settings.sshEnabled
        @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(filePath)), true, @settings, () =>
          Debug.log("[project] Initializing timer with state as #{@currentState}")
          @initializeTimer()
        )
      else
        @initializeTimer()
    )
    # TODO: For now, don't clean up, but consider removing old files on remote
    @directoryWatch.on('unlink', (filePath) =>
      Debug.log("File #{filePath} has been removed")
      if @settings.sshEnabled
        @fileSync.unlink(path.relative(@settings.localBaseDir, normalizePath(filePath)), @settings) if @fileSync
    )
    @directoryWatch.on('unlinkDir', (filePath) =>
      Debug.log("[project] Directory #{filePath} has been removed")
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
        Debug.log("Idle timeout start! #{new Date()}")
        @startModules()
        @idleTimeout = null
      , atom.config.get('cilkpride.idleSeconds') * 1000
    )

  clearTimer: () ->
    @killModules()

  refreshConfFile: () ->
    checkSettings = (settings) ->
      Debug.log("[project] Checking settings...")
      # TODO: For now, require users to give a cilksan and cilkprof command.
      # In the future, this should be optional and should turn off modules as necessary.
      return false unless settings.cilksanCommand and settings.cilkprofCommand
      if settings.sshEnabled
        return false unless settings.username?.trim?().split(' ').length is 1
        Debug.log("[project] passed username check")
        return false unless settings.hostname?.trim?().split(' ').length is 1
        Debug.log("[project] passed hostname check")
        return false unless settings.localBaseDir # Windows can have spaces.
        Debug.log("[project] passed localBaseDir check")
        return false unless settings.remoteBaseDir?.trim?().split(' ').length is 1
        Debug.log("[project] passed remoteBaseDir check")
        return false unless typeof settings.port is "number"
        return false unless settings.syncIgnoreDir?.constructor is Array
        return false unless settings.syncIgnoreFile?.constructor is Array
      return true

    try
      Debug.log(path.join(@path, 'cilkpride-conf.json'))
      @settings = JSON.parse(fs.readFileSync(
        path.join(@path, 'cilkpride-conf.json'),
        {
          flags: 'r',
          encoding: 'utf-8',
        }
      ))
      throw new Error() if not checkSettings(@settings)
      Debug.log("[project] Passed settings check.")
      Debug.log(@settings)
      @currentState = "ok"
      @updateState()
      return true
    catch error
      Debug.log(error)
      @currentState = "config_error"
      @updateState()
      atom.notifications.addError("Cilkpride was unable to read #{path.join(@path, 'cilkpride-conf.json')}.
        Please make sure the configuration file is correctly formatted, and the appropriate fields are filled out.")
      return false

  # Starts running the command line tools, unless the configuration is broken.
  startModules: () ->
    return if @currentState is "config_error"
    module.startThread() for module in @modules

  killModules: () ->
    Debug.log("Attempting to kill modules for path #{@path}...")
    clearInterval(@idleTimeout)

    module.kill() for module in @modules
    return true

  # Hooks

  registerEditor: (editor) ->
    Debug.log("[project] Trying to register an editor with project path #{@path}.")
    Debug.log(editor)
    if editor.id not in @editorIds
      @editorIds.push(editor.id)

    if not atom.config.get('cilkpride.generalSettings.watchDirectory', false)
      saveDisposable = editor.onDidSave(()=>
        Debug.log("Saved!")

        if @sshMod
          @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(editor.getPath())), true, @settings, () =>
            Debug.log("[project] Initializing timer with state as #{@currentState}")
            @initializeTimer()
          )
        else
          @initializeTimer()
      )

      @editorSubscriptions[editor.id] = saveDisposable
      @subscriptions.add(saveDisposable)
    module.registerEditor(editor) for module in @modules

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

    module.destroy() for module in @modules
    @sshMod.destroy() if @sshMod
    @fileSync.destroy() if @fileSync
    @consoleMod.destroy() if @consoleMod
    @configWatch.close() if @configWatch
    @watchDirectory.close() if @watchDirectory
