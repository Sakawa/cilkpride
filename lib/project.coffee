{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path').posix;
chokidar = require('chokidar')

{normalizePath} = require('./utils/utils')

CilkideDetailPanel = require('./cilkide-detail-panel')
CilksanModule = require('./cilksan/main')
CilkprofModule = require('./cilkprof/main')
SSHModule = require('./ssh-module')
FileSync = require('./file-sync')
Runner = require('./runner')
Console = require('./console/console')
Debug = require('./utils/debug')

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
  cilksanMod: null
  cilkprofMod: null
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
    @subscriptions = new CompositeDisposable()
    @detailPanel = new CilkideDetailPanel({
        onCloseCallback: (() => @onPanelCloseCallback())
    })
    @currentState = {
      state: "start"
    }

    @refreshConfFile()

    # Set a watch so that we know when the configuration file is changed.
    @configWatch = chokidar.watch(path.join(@path, 'cilkpride-conf.json'))
    @configWatch.on('change', (path) =>
      Debug.log("[project] Received watch (change) notification on config")
      @refreshConfFile()
      Debug.log("Refreshed config file, state is #{@currentState.state}")
      if @currentState.state is "ok" and not @cilksanMod
        @init()
    ).on('unlink', (path) =>
      Debug.log("[project] Received watch (unlink) notification on config")
      @onDestroy()
    )

    atom.commands.add('atom-workspace', 'cilkpride:debug', () =>
      Debug.log("[debug] Wow! Debug!")
    )

    @init()

  init: () ->
    # Check the configuration file for errors first.
    return if @currentState.state is "config_error"

    # For each module, create a tab for it and initialize the module.
    @cilksanMod = new CilksanModule({
      changePanel: (() => @changeDetailPanel(@path))
      getSettings: (() => return @settings)
      onStateChange: (() => @updateState(false, @cilksanMod))
      runner: new Runner({
        getInstance: ((callback) => @getInstance(callback))
        getSettings: (() => return @settings)
        moduleName: "cilksan"
      })
      path: @path
    })

    @cilkprofMod = new CilkprofModule({
      changePanel: (() => @changeDetailPanel(@path))
      getSettings: (() => return @settings)
      onStateChange: (() => @updateState(false, @cilkprofMod))
      runner: new Runner({
        getInstance: ((callback) => @getInstance(callback))
        getSettings: (() => return @settings)
        moduleName: "cilkprof"
      })
      path: @path
    })

    @consoleMod = new Console({})

    @cilksanMod.tab = @detailPanel.registerModuleTab("Cilksan", @cilksanMod.getView())
    @cilkprofMod.tab = @detailPanel.registerModuleTab("Cilkprof", @cilkprofMod.getView())
    @consoleMod.tab = @detailPanel.registerModuleTab("Console", @consoleMod)

    @consoleMod.registerModule(@cilksanMod.name)
    @consoleMod.registerModule(@cilkprofMod.name)

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
    Debug.log("[project] Current state is #{@currentState.state}")
    Debug.log(@settings)
    Debug.log(@sshMod)

    if module and module.currentState.output
      @consoleMod.updateOutput(module.name, module.currentState.output)

    if @path isnt @statusBar.getCurrentPath()
      Debug.log("[project] status bar: path mismatch")
      return

    # Global project states take priority - config errors, etc.
    if @currentState.state is "config_error"
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
    # 4. All modules are reporting OK.
    if @cilksanMod
      if not @cilksanMod.currentState.ready
        if @cilksanMod.currentState.lastRuntime
          return @statusBar.displayCountdown(@cilksanMod.currentState.startTime +
            @cilksanMod.currentState.lastRuntime)
        else
          return @statusBar.displayCountdown()

      if @cilksanMod.currentState.state is "execution_error"
        return @statusBar.displayExecutionError(repressUpdate)

      if @cilksanMod.currentState.state is "error"
        return @statusBar.displayErrors(repressUpdate)

      if @cilksanMod.currentState.state is "start"
        return @statusBar.displayStart(repressUpdate)

    Debug.log("[project] status bar: fallthrough")
    @statusBar.displayNoErrors(repressUpdate)

    return

  connectSSH: () ->
    @sshMod.startConnection()

  signalModules: () ->
    # Start watching directories when FileSync is good to go.
    @fileSync.updateSFTP((() => @createDirectoryWatch()))
    @cilksanMod.updateInstance()
    @cilkprofMod.updateInstance()

    @currentState.state = "ok"

  createDirectoryWatch: () ->
    Debug.log("[project] in createDirectoryWatch")
    return if @directoryWatch or not atom.config.get('cilkpride.generalSettings.watchDirectory', false)

    @directoryWatch = chokidar.watch(@path, {ignored: /[\/\\]\./, persistent: true})

    @directoryWatch.on('add', (filePath) =>
      Debug.log("File #{filePath} has been added")
      if @settings.sshEnabled
        @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(filePath)), true, @settings, () =>
          Debug.log("[project] Initializing timer with state as #{@currentState.state}")
          @initializeTimer()
        )
      else
        @initializeTimer()
    )
    @directoryWatch.on('change', (filePath) =>
      Debug.log("File #{filePath} has been changed")
      if @settings.sshEnabled
        @fileSync.copyFile(path.relative(@settings.localBaseDir, normalizePath(filePath)), true, @settings, () =>
          Debug.log("[project] Initializing timer with state as #{@currentState.state}")
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
        @makeExecutable()
        @idleTimeout = null
      , atom.config.get('cilkpride.idleSeconds') * 1000
    )

  clearTimer: () ->
    @killModules()

  refreshConfFile: () ->
    checkSettings = (settings) ->
      Debug.log("[project] Checking settings...")
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
      Debug.log(@settings)
      @currentState.state = "ok"
      @updateState()
      return true
    catch error
      Debug.log(error)
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
    @cilksanMod.startThread()
    @cilkprofMod.startThread()

  killModules: () ->
    Debug.log("Attempting to kill modules for path #{@path}...")
    clearInterval(@idleTimeout)

    @cilksanMod.kill()
    @cilkprofMod.kill()
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
            Debug.log("[project] Initializing timer with state as #{@currentState.state}")
            @initializeTimer()
          )
        else
          @initializeTimer()
      )

      @editorSubscriptions[editor.id] = saveDisposable
      @subscriptions.add(saveDisposable)
    @cilksanMod.registerEditor(editor) if @cilksanMod
    @cilkprofMod.registerEditor(editor) if @cilkprofMod

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

    @cilksanMod.destroy() if @cilksanMod
    @cilkprofMod.destroy() if @cilkprofMod
    @sshMod.destroy() if @sshMod
    @fileSync.destroy() if @fileSync
    @consoleMod.destroy() if @consoleMod
    @configWatch.close() if @configWatch
    @watchDirectory.close() if @watchDirectory
