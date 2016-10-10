{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path').posix

{normalizePath} = require('./utils/utils')

Project = require('./project')
StatusBarView = require('./status-bar-view')

module.exports = Cilkide =
  projects: {}
  subscriptions: null

  # Editor/path bookkeeping
  editorToPath: {}
  pathToPath: {}

  # Singleton global UI elements
  detailPanel: null
  panelPath: null
  statusBarElement: null
  statusBarTile: null

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
    })

    # Add a hook when we're changing active panes so that the status tile shows
    # the correct status for the current project.
    @subscriptions.add(atom.workspace.onDidChangeActivePaneItem((item) =>
      console.log("Changed active pane item...")
      if atom.workspace.getActiveTextEditor()
        @statusBarElement.show()
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

    console.log("Cilkscreen plugin activated!")

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
    # The status bar should disappear and not be visible.
    if not editor = atom.workspace.getActiveTextEditor()
      @statusBarElement.updatePath(null)
      @statusBarElement.displayPluginDisabled()
      return

    console.log("Switched active panes. Editor id is #{editor.id}.")
    if projectPath = @editorToPath[editor.id]
      @statusBarElement.updatePath(projectPath)
      @projects[projectPath].updateState(true)
    else
      @statusBarElement.updatePath(null)
      @statusBarElement.displayPluginDisabled()
    console.log("Project path is #{projectPath}")

  onStatusTileClick: () ->
    @changeDetailPanel(@getActivePanePath())

  # Panel-based methods

  changeDetailPanel: (tpath) ->
    project = @projects[tpath]
    if tpath isnt @panelPath or not @detailPanel
      if @detailPanel
        @detailPanel.destroy()
        console.log("Destroyed detail panel.")
      @detailPanel = atom.workspace.addBottomPanel(item: project.getDetailPanel(), visible: true)
      @panelPath = tpath
    else
      @detailPanel.show()

  onPanelCloseCallback: () ->
    @detailPanel.hide()

  getActivePanePath: () ->
    return @editorToPath[atom.workspace.getActiveTextEditor()?.id]

  # Event handlers

  registerEditor: (editor) ->
    console.log("Received a new editor (id #{editor.id})")

    # Cancel if this editor is already associated with a path.
    return if @editorToPath[editor.id]

    # Add the gutter to the newly registered editor. We do this to all
    # editors for consistency - otherwise there will be flashing.
    editor.addGutter({name: 'cilksan-lint', priority: -1, visible: true}) if not editor.gutterWithName('cilksan-lint')

    @subscriptions.add(editor.onDidChangePath(
      () =>
        console.log("Editor changed path: " + editor.id)
        console.log("The new path is now: #{normalizePath(editor.getPath?())}")
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
    console.log("[main] Registering #{editor.id} with path #{projectPath}")
    @registerEditorWithProject(projectPath, editor)

  # Traverse the directories to determine if this file has a parent directory
  # that contains a configuration file.
  findConfFile: (filePath) ->
    traversedPaths = []
    console.log("File path: #{filePath}")
    projectPath = path.join(filePath, '..')
    console.log("Project path: #{projectPath}")
    if not rootDir = path.parse(projectPath).root
      # On Windows machines, due to path normalization we must break on '.'
      rootDir = '.'
    console.log("Root dir: #{rootDir}")
    loop
      console.log("Testing for Makefile: #{projectPath}")
      traversedPaths.push(projectPath)
      # If we've seen this path before, break early.
      if @pathToPath[projectPath] isnt undefined
        console.log("Quick escape: #{@pathToPath[projectPath]}")
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
    console.log("Generating a configuration file in #{directory}...")
    confPath = path.join(directory, 'cilkpride-conf.json')
    fs.open(confPath, 'wx', (err, fd) ->
      if err
        # do some error handling here
        atom.notifications.addError("Cilkpride configuration file already exists in #{directory}.", {
          title: "Edit the existing configuration file, or delete it and re-register the directory."
        })
      else
        fs.write(fd, """
{
  "cilksanCommand": "make cilksan && ./queens",

  "sshEnabled": true,
  "hostname": "athena.dialup.mit.edu",
  "port": 22,
  "username": "your athena username here",
  "launchInstance": false,
  "localBaseDir": "#{directory}",
  "remoteBaseDir": "full directory path of the project directory on the remote instance"
}
        """, {encoding: "utf8"}, (err, written, buffer) ->
          atom.workspace.open(confPath)
          atom.notifications.addSuccess("Cilkpride configuration file created for #{directory}.", {
            title: "Customize the configuration for your particular project to start using the plugin!"
          })
        )
    )

  checkActiveEditorsForProject: () ->
    # Clear the path-to-path cache.
    @pathToPath = {}

    atom.workspace.getTextEditors().forEach((editor) =>
      @registerEditor(editor)
    )

  registerEditorWithProject: (projectPath, editor) ->
    console.log("Trying to register editor id #{editor.id} with #{projectPath} from cilkpride.")
    if projectPath not in Object.getOwnPropertyNames(@projects)
      console.log("Path doesn't currently exist, so making a new one...")
      @projects[projectPath] = new Project({
        changeDetailPanel: ((tpath) => @changeDetailPanel(tpath))
        onPanelCloseCallback: (() => @onPanelCloseCallback())
        path: projectPath
        statusBar: @statusBarElement
      })
      # Re-check old editors - redundant on start-up but will help prevent bugs.
      @checkActiveEditorsForProject()
    @projects[projectPath].registerEditor(editor)
