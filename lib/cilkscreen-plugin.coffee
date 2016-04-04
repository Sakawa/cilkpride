{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path')
$ = require('jquery')

Project = require('./project')
StatusBarView = require('./status-bar-view')

module.exports = CilkscreenPlugin =
  projects: {}
  subscriptions: null

  # Editor/path bookkeeping
  editorToPath: {}
  pathToPath: {}

  # Singleton UI elements
  detailPanel: null
  panelPath: null
  statusBarElement: null
  statusBarTile: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable()

    @statusBarElement = new StatusBarView({
      onErrorClickCallback: () => @onStatusTileClick()
      onRegisterProjectCallback: (directories) => @onRegisterProject(directories)
    })

    # Register command that toggles this view
    @subscriptions.add(atom.commands.add('atom-workspace', 'cilkscreen-plugin:toggle': () => @toggle()))

    # Add a hook on every single text editor that is open (and will be opened in the future)
    @subscriptions.add(atom.workspace.observeTextEditors((editor) => @registerEditor(editor)))

    # Add a hook when we're changing active panes so that the status tile can show the correct
    # race condition status for the current project.
    @subscriptions.add(atom.workspace.onDidChangeActivePaneItem((item) =>
      if atom.workspace.getActiveTextEditor()
        @statusBarElement.show()
        @updateStatusBar()
      else
        @statusBarElement.hide()
    ))

    console.log("Cilkscreen plugin activated!")

  consumeStatusBar: (statusBar) ->
    @statusBarTile = statusBar.addLeftTile(item: @statusBarElement.getElement(), priority: -1)
    @statusBarElement.updatePath(@getActivePanePath())
    @updateStatusBar()

  updateStatusBar: () ->
    editor = atom.workspace.getActiveTextEditor()
    console.log("Switched active panes. Editor id is #{editor.id}.")
    console.log(@editorToPath)
    projectPath = @editorToPath[editor.id]
    if projectPath
      @statusBarElement.updatePath(projectPath)
      @projects[projectPath].updateStatusTile()
    else
      @statusBarElement.updatePath(null)
      @statusBarElement.displayPluginDisabled()

  deactivate: ->
    @subscriptions.dispose()
    @statusBarTile.destroy()
    @detailPanel.destroy()
    @statusBarTile = null
    @statusBarElement = null
    @detailPanel = null
    @panelPath = null

  serialize: ->
    cilkscreenPluginViewState: null

  toggle: ->
    console.log('CilkscreenPlugin was toggled!')

  onMarkerClick: (cpath, violationIndex) ->
    console.log("Marker clicked")
    console.log(violationIndex)
    console.log(@detailPanel)

    project = @projects[cpath]
    # TODO: possibly further investigate flow issue here
    @changeDetailPanel(cpath)
    project.highlightViolationInDetailPanel(violationIndex)

  onStatusTileClick: () ->
    panePath = @getActivePanePath()
    @changeDetailPanel(panePath)

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
    # Add the gutter to the newly registered editor.
    editor.addGutter({name: 'cilkscreen-lint', priority: -1, visible: true})

    @subscriptions.add(editor.onDidChangePath(
      () =>
        # TODO: finish this
        console.log("Editor changed path: " + editor.id)
        console.log("The new path is now: #{editor.getPath?()}")
        oldPath = @editorToPath[editor.id]
        if oldPath
          @projects[oldPath].unregisterEditor(editor.id)
        newPath = editor.getPath?()
        if newPath
          newProjectPath = @findConfFile(newPath)
          if newProjectPath
            @editorToPath[editor.id] = newProjectPath
            @registerEditorWithProject(newProjectPath, editor)
        else
          delete @editorToPath[editor.id]
    ))

    filePath = editor.getPath?()
    if not filePath
      return

    projectPath = @findConfFile(filePath)
    if not projectPath
      return

    @editorToPath[editor.id] = projectPath
    @registerEditorWithProject(projectPath, editor)

  findConfFile: (filePath) ->
    traversedPaths = []
    projectPath = path.resolve(filePath, '..')
    rootDir = path.parse(projectPath).root
    console.log("Root dir: ", rootDir)
    loop
      console.log("Testing for Makefile: " + projectPath)
      traversedPaths.push(projectPath)
      if @pathToPath[projectPath] isnt undefined
        console.log("Quick escape: #{@pathToPath[projectPath]}")
        return @pathToPath[projectPath]
      try
        stats = fs.statSync(path.resolve(projectPath, 'cilkscreen-conf.json'))
        if stats.isFile()
          for tpath in traversedPaths
            @pathToPath[tpath] = projectPath
          return projectPath
      catch error
        projectPath = path.resolve(projectPath, '..')
      finally
        if projectPath is rootDir
          for tpath in traversedPaths
            @pathToPath[tpath] = null
          return null

  onRegisterProject: (directories) ->
    if directories
      for directory in directories
        @createConfFile(directory)

  createConfFile: (directory) ->
    console.log("Generating a configuration file in #{directory}...")
    confPath = path.join(directory, 'cilkscreen-conf.json')
    fs.open(confPath, 'wx', (err, fd) ->
      if err
        # do some error handling here
        atom.notifications.addError("Cilktools configuration file already exists in #{directory}.", {
          title: "Edit the existing configuration file, or delete it and re-register the directory."
        })
      else
        fs.write(fd, """
{
  "makeCommand": ["make target-name"],
  "commandArgs": ["./executable", "arg1", "arg2", "..."]
}
        """, {encoding: "utf8"}, (err, written, buffer) ->
          atom.workspace.open(confPath)
          atom.notifications.addSuccess("Cilktools configuration file created for #{directory}.", {
            title: "Customize the configuration for your particular project to start using the plugin!"
          })
        )
    )

  registerEditorWithProject: (projectPath, editor) ->
    console.log("Trying to register editor id #{editor.id} with #{projectPath} from cilkscreen-plugin.")
    if projectPath not in Object.getOwnPropertyNames(@projects)
      console.log("Path doesn't currently exist, so making a new one...")
      @projects[projectPath] = new Project({
        onMarkerClickCallback: ((index) => @onMarkerClick(projectPath, index))
        onPanelCloseCallback: (() => @onPanelCloseCallback())
        path: projectPath
        statusBar: @statusBarElement
      })
    @projects[projectPath].registerEditor(editor)
