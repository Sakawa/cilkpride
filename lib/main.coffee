###
The main class of the Cilkpride package. This file specifies the core actions
of the package, including all setup and disassembly actions needed. Most
Cilkpride-global functions can be found here, including singleton-UI items
(status bar, detail panel).
###

{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path').posix

Debug = require('./utils/debug')
{normalizePath} = require('./utils/utils')
Project = require('./project')
StatusBarView = require('./status-bar-view')

module.exports = Cilkpride =
  projects: {}               # dictionary (project path -> Project object)
  subscriptions: null        # CompositeDisposable for all editor hooks

  editorToPath: {}           # dictionary (editor ID -> project path)
  pathToPath: {}             # dictionary (file path -> project path)

  # Singleton UI elements
  detailPanel: null          # CilkprideDetailPanel object, to house detailed info
  panelPath: null            # project path of the info being shown in the detail panel
  statusBarElement: null     # StatusBarView object, showing Cilkpride's status
  statusBarTile: null        # status bar object from 3rd party status-bar package

  activate: (state) ->
    # Install dependencies first, if the user doesn't have them.
    require('atom-package-deps').install('cilkpride').then(() =>
      # Add a hook on all text editors open / will be opened in the future.
      @subscriptions.add(atom.workspace.observeTextEditors((editor) => @registerEditor(editor)))
    )

    @subscriptions = new CompositeDisposable()

    @statusBarElement = new StatusBarView({
      onClickCallback: () => @onStatusTileClick()
      onRegisterProjectCallback: (directories) => @onRegisterProject(directories)
      onConnectCallback: () => @connectCurrentProject()
    })

    # Add a hook when we're changing active panes so that the status tile shows
    # the correct status for the current project.
    @subscriptions.add(atom.workspace.onDidChangeActivePaneItem((item) =>
      Debug.log("Changed active pane item...")
      @updateStatusBar()
    ))

    # Local -> Remote syncing.
    atom.commands.add('atom-workspace', 'cilkpride:sync-local-remote', (event) =>
      event.stopPropagation()
      if editorPath = @getActivePanePath()
        @projects[editorPath].sync(true)
    )

    # Remote -> Local syncing.
    atom.commands.add('atom-workspace', 'cilkpride:sync-remote-local', (event) =>
      event.stopPropagation()
      if editorPath = @getActivePanePath()
        @projects[editorPath].sync(false)
    )

    Debug.log("Cilkpride plugin activated!")

  deactivate: ->
    @subscriptions.dispose()
    @statusBarTile.destroy()
    @detailPanel.destroy() if @detailPanel
    for projectPath in @projects
      @projects[projectPath].destroy()

  serialize: ->

  # Status bar related items

  consumeStatusBar: (statusBar) ->
    @statusBarTile = statusBar.addLeftTile(item: @statusBarElement.getElement(), priority: -1)
    @statusBarElement.updatePath(@getActivePanePath())
    @updateStatusBar()

  updateStatusBar: () ->
    # The current pane is a non-text editor (settings view, etc.)
    if not editor = atom.workspace.getActiveTextEditor()
      @statusBarElement.updatePath(null)
      @statusBarElement.displayPluginDisabled()
      return

    Debug.log("Switched active panes. Editor id is #{editor.id}.")
    if projectPath = @editorToPath[editor.id]
      @statusBarElement.updatePath(projectPath)
      @projects[projectPath].updateState(true)
    else
      @statusBarElement.updatePath(null)
      @statusBarElement.displayPluginDisabled()
    Debug.log("Project path is #{projectPath}")

  onStatusTileClick: () ->
    @changeDetailPanel(@getActivePanePath())

  # Panel-based methods

  changeDetailPanel: (projectPath) ->
    project = @projects[projectPath]
    if projectPath isnt @panelPath or not @detailPanel
      if @detailPanel
        @detailPanel.destroy()
        Debug.log("Destroyed detail panel.")
      @detailPanel = atom.workspace.addBottomPanel(item: project.getDetailPanel(), visible: true)
      @panelPath = projectPath
    else
      @detailPanel.show()

  onPanelCloseCallback: () ->
    @detailPanel.hide()

  getActivePanePath: () ->
    return @editorToPath[atom.workspace.getActiveTextEditor()?.id]

  # Event handlers

  registerEditor: (editor) ->
    Debug.log("Received a new editor (id #{editor.id})")

    # Cancel if this editor is already associated with a path.
    return if @editorToPath[editor.id]

    # Add the gutter to the newly registered editor. We do this to all
    # editors for consistency - otherwise there will be a flicker as the gutter appears.
    editor.addGutter({name: 'cilksan-lint', priority: -2, visible: true}) if not editor.gutterWithName('cilksan-lint')
    editor.addGutter({name: 'cilkprof', priority: -1, visible: true}) if not editor.gutterWithName('cilkprof')

    # Hook for when a file is renamed/deleted
    @subscriptions.add(editor.onDidChangePath(
      () =>
        Debug.log("Editor changed path: " + editor.id)
        Debug.log("The new path is now: #{normalizePath(editor.getPath?())}")
        if oldPath = @editorToPath[editor.id]
          @projects[oldPath].unregisterEditor(editor.id)
        if newPath = normalizePath(editor.getPath?())
          if newProjectPath = @findConfFile(newPath)
            @editorToPath[editor.id] = newProjectPath
            @registerEditorWithProject(newProjectPath, editor)
          else
            delete @editorToPath[editor.id]
        else
          delete @editorToPath[editor.id]
    ))

    # If the editor has no path or we can't find a config file, stop.
    return if not filePath = normalizePath(editor.getPath?())
    return if not projectPath = @findConfFile(filePath)

    @editorToPath[editor.id] = projectPath
    Debug.log("[main] Registering #{editor.id} with path #{projectPath}")
    @registerEditorWithProject(projectPath, editor)

  # Traverse the directories to determine if this file has a parent directory
  # that contains a cilkpride configuration file.
  findConfFile: (filePath) ->
    traversedPaths = []
    Debug.log("File path: #{filePath}")
    projectPath = path.join(filePath, '..')
    Debug.log("Project path: #{projectPath}")
    if not rootDir = path.parse(projectPath).root
      # On Windows machines, due to path normalization we must break on '.'
      rootDir = '.'
    Debug.log("Root dir: #{rootDir}")
    loop
      Debug.log("Testing for Makefile: #{projectPath}")
      traversedPaths.push(projectPath)
      # If we've seen this path before, break early.
      if @pathToPath[projectPath] isnt undefined
        Debug.log("Quick escape: #{@pathToPath[projectPath]}")
        return @pathToPath[projectPath]
      try
        stats = fs.statSync(path.join(projectPath, 'cilkpride-conf.json'))
        if stats.isFile()
          for tpath in traversedPaths
            @pathToPath[tpath] = projectPath
          return projectPath
      catch error
        projectPath = path.join(projectPath, '..')
      finally
        if projectPath is rootDir
          for tpath in traversedPaths
            @pathToPath[tpath] = null
          return null

  onRegisterProject: (directories) ->
    if directories
      for directory in directories
        @createConfFile(normalizePath(directory))

  createConfFile: (directory) ->
    Debug.log("Generating a configuration file in #{directory}...")
    confPath = path.join(directory, 'cilkpride-conf.json')
    fs.open(confPath, 'wx', (err, fd) ->
      if err
        # do some error handling here - currently assumes the only error is that
        # the file already exists
        atom.notifications.addError("Cilkpride configuration file already exists in #{directory}.", {
          title: "Edit the existing configuration file, or delete it and re-register the directory."
        })
      else
        fs.write(fd, """
{
  "username": "your athena username here",
  "remoteBaseDir": "full directory path of the project directory on the remote instance",
  "cilksanCommand": "make CILKSAN=1 && ./queens",
  "cilkprofCommand": "make CILKPROF=1 && ./queens",

  "sshEnabled": true,
  "hostname": "athena.dialup.mit.edu",
  "port": 22,
  "launchInstance": false,
  "localBaseDir": "#{directory}",
  "syncIgnoreFile": ["/cilkpride-conf.json"],
  "syncIgnoreDir": ["/.git", "/log.awsrun", "/log.cqrun", "/.cilksan", "/.cilkprof"],
  "targetNumberOfCores": 8
}
        """, {encoding: "utf8"}, (err, written, buffer) ->
          atom.workspace.open(confPath)
          atom.notifications.addSuccess("Cilkpride configuration file created for #{directory}.", {
            title: "Customize the configuration for your Cilkpride project to start using the plugin!"
          })
        )
    )

  checkActiveEditorsForProject: () ->
    # Clear the path-to-path cache.
    @pathToPath = {}

    atom.workspace.getTextEditors().forEach((editor) =>
      @registerEditor(editor)
    )

  connectCurrentProject: () ->
    if currentProject = @getActivePanePath()
      @projects[currentProject].connectSSH()

  destroyProject: (projectPath) ->
    return if not @projects[projectPath]

    Debug.log("[main] Destroying project #{projectPath}")
    Debug.log(@editorToPath)
    if projectPath is @panelPath
      @onPanelCloseCallback()
      @detailPanel.destroy()
      @panelPath = null
    for editorId in Object.getOwnPropertyNames(@editorToPath)
      Debug.log("[main] Destroying project, testing editor #{editorId}")
      if @editorToPath[editorId] is projectPath
        delete @editorToPath[editorId]
    @projects[projectPath].destroy()
    @pathToPath = {}
    delete @projects[projectPath]
    @updateStatusBar()

  registerEditorWithProject: (projectPath, editor) ->
    Debug.log("Trying to register editor id #{editor.id} with #{projectPath} from cilkpride.")
    if projectPath not in Object.getOwnPropertyNames(@projects)
      Debug.log("Path doesn't currently exist, so making a new one...")
      @projects[projectPath] = new Project({
        changeDetailPanel: ((tpath) => @changeDetailPanel(tpath))
        onPanelCloseCallback: (() => @onPanelCloseCallback())
        onDestroy: (() => @destroyProject(projectPath))
        path: projectPath
        statusBar: @statusBarElement
      })
      # Re-check old editors - redundant on start-up but will help prevent bugs.
      @checkActiveEditorsForProject()
      @updateStatusBar()
    @projects[projectPath].registerEditor(editor)
