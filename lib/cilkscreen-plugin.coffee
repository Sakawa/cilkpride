{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path')
process = require('process')
exec = require('child_process').exec
spawn = require('child_process').spawn
extend = require('util')._extend;
$ = require('jquery')

CilkscreenMarkerView = require('./cilkscreen-marker-view')
CilkscreenPluginView = require('./cilkscreen-plugin-view')
StatusBarView = require('./status-bar-view')

module.exports = CilkscreenPlugin =
  subscriptions: null
  idleTimeout: {}
  # cilkscreenThread: {}
  # cilkscreenTime: {}
  # lastRunTime: {}
  currentCilkscreenState: {}
  editorToPath: {}
  pathToEditor: {}
  fileToEditor: {}
  pluginView: {}

  # Singleton UI elements
  detailPanel: null
  statusBarElement: null
  statusBarTile: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable()

    # Register command that toggles this view
    @subscriptions.add(atom.commands.add('atom-workspace', 'cilkscreen-plugin:toggle': => @toggle()))

    # Add a hook on every single text editor that is open (and will be opened in the future)
    @subscriptions.add(atom.workspace.observeTextEditors(
      (editor) =>
        @registerEditor(editor)
    ))

    # Add a hook when we're changing active panes so that the status tile can show the correct
    # race condition status for the current project.
    @subscriptions.add(atom.workspace.onDidChangeActivePaneItem((item) =>
      if atom.workspace.getActiveTextEditor()
        @statusBarElement.show()
        @updateStatusTile()
      else
        @statusBarElement.hide()
    ))

    console.log("Activated!")

  consumeStatusBar: (statusBar) ->
    # Figure this thing out.
    @statusBarElement = new StatusBarView( (() => @onStatusTileClick()) )
    @statusBarElement.updatePath(@getActivePanePath())
    @statusBarTile = statusBar.addLeftTile(item: @statusBarElement.getElement(), priority: -1)

  deactivate: ->
    @subscriptions.dispose()
    @statusBarTile.destroy()
    @statusBarTile = null

  serialize: ->
    cilkscreenPluginViewState: @cilkscreenPluginView.serialize()

  toggle: ->
    console.log('CilkscreenPlugin was toggled!')

  # Timer functions

  initializeCilkscreenTimer: (path) ->
    @idleTimeout[path] = setTimeout(
      () =>
        console.log("Idle timeout start! #{new Date()}")
        @makeExecutable(path)
      , atom.config.get('cilkscreen-plugin.idleSeconds') * 1000
    )

  clearCilkscreenTimer: (path) ->
    clearInterval(@idleTimeout[path])
    if @currentCilkscreenState[path].start?
      @currentCilkscreenState[path].start = null;
    @killCilkscreen(path)

  startCilkscreen: (currentProjectPath) ->
    # TODO: add the cilktool path
    cilkLibPath = atom.config.get('cilkscreen-plugin.cilkLibPath')

    envCopy = extend({'LD_LIBRARY_PATH': cilkLibPath, 'LIBRARY_PATH': cilkLibPath}, process.env)

    @currentCilkscreenState[currentProjectPath].start = Date.now()
    console.log("Just set cilkscreenTime #{currentProjectPath} to #{@currentCilkscreenState[currentProjectPath].start}")
    console.log("Last runtime: #{@currentCilkscreenState[currentProjectPath].lastRuntime}")
    if @editorToPath[atom.workspace.getActiveTextEditor().id] is currentProjectPath
      if estTime = @currentCilkscreenState[currentProjectPath].lastRuntime?
        @statusBarElement.displayCountdown(@currentCilkscreenState[currentProjectPath].start + estTime)
      else
        @statusBarElement.displayUnknownCountdown()
    cilkscreenThread = spawn('cilkscreen', ['./cilkscreen'], {env: envCopy})
    @currentCilkscreenState[currentProjectPath].thread = cilkscreenThread
    cilkscreenOutput = ""

    cilkscreenThread.stderr.on('data', (data) ->
      cilkscreenOutput += data
    )

    cilkscreenThread.on('close', (code) =>
        console.log("stderr: #{cilkscreenOutput}")
        console.log("cilkscreen process exited with code #{code}")
        if code is 0
          console.log("Killing old markers, if any...")
          @destroyOldMarkers(currentProjectPath)
          console.log("Parsing data...")
          parsedResults = @parseCilkscreenOutput(cilkscreenOutput)
          @currentCilkscreenState[currentProjectPath].lastRuntime = Date.now() - @currentCilkscreenState[currentProjectPath].start
          @currentCilkscreenState[currentProjectPath].start = null
          console.log("Just set lastRuntime #{currentProjectPath} to #{@currentCilkscreenState[currentProjectPath].lastRuntime}")
          @currentCilkscreenState[currentProjectPath].numViolations = parsedResults.length
          currentPath = @getActivePanePath()
          if currentPath is currentProjectPath
            if parsedResults.length > 0
              @statusBarElement.displayErrors(parsedResults.length)
            else
              @statusBarElement.displayNoErrors()
          console.log("The last run took #{@currentCilkscreenState[currentProjectPath].lastRuntime / 1000} seconds.")
          @createCilkscreenMarkers(currentProjectPath, parsedResults)
    )

    # Debug event handlers
    cilkscreenThread.on('error', (err) ->
      console.log("cilkscreen thread error: #{err}")
    )

    cilkscreenThread.on('exit', (code, signal) ->
      if code?
        console.log("cilkscreen exit: code #{code}")
      if signal?
        console.log("cilkscreen exit: signal #{signal}")
    )

    console.log(envCopy)

  # Uses the cilkscreen target in the Makefile to make the executable so that
  # we can use cilkscreen on a well-defined object.
  makeExecutable: (currentProjectPath) ->
    # First change the directory to the folder where the Makefile is.
    try
      process.chdir(currentProjectPath)
      console.log("Successfully changed pwd to: #{currentProjectPath}")
    catch error
      console.err("Could not change pwd to #{currentProjectPath}")

    # Invoke the cilkscreen target to run cilkscreen on.
    makeThread = exec('make cilkscreen',
      (error, stdout, stderr) =>
        console.log("stdout: #{stdout}")
        console.log("stderr: #{stderr}")
        if error isnt null
          console.log('child process exited with code ' + error)
        else if not stdout.includes("Nothing to be done")
          @startCilkscreen(currentProjectPath)
    )

  killCilkscreen: (path) ->
    console.log("Attempting to kill cilkscreen...")
    thread = @currentCilkscreenState[path].thread
    if thread
      console.log(thread)
      thread.kill('SIGKILL')
      console.log("Killed thread...?")
      console.log(thread)
      delete @currentCilkscreenState[path].thread

  # Cilkscreen-related functions
  parseCilkscreenOutput: (text) ->
    text = text.split('\n')
    violations = []
    currentViolation = null

    # Run through it line by line to figure out what the race conditions are
    for line in text
      if line.indexOf("Race condition on location ") isnt -1
        # We have found the first line in a violation
        currentViolation = {stacktrace: [], location: line}
        continue

      if currentViolation isnt null
        if line.indexOf("access at") isnt -1
          splitLine = line.trim().split(' ')
          accessType = splitLine[0]
          console.log(splitLine)
          sourceCodeLine = splitLine[4].slice(1, -1)
          console.log(sourceCodeLine)
          sourceCodeLine = sourceCodeLine.split(',')[0]
          console.log(sourceCodeLine)
          splitIndex = sourceCodeLine.lastIndexOf(':')
          sourceCodeFile = sourceCodeLine.substr(0, splitIndex)
          sourceCodeLine = sourceCodeLine.substr(splitIndex + 1)

          lineData = {
            type: accessType,
            file: sourceCodeFile,
            line: parseInt(sourceCodeLine),
            raw: line
          }

          console.log(lineData)

          if currentViolation.line1?
            currentViolation.line2 = lineData
          else
            currentViolation.line1 = lineData
        else if line.indexOf("called by") isnt -1
          console.log(currentViolation)
          currentViolation.stacktrace.push(line)
        else
          violations.push(currentViolation)
          currentViolation = null

    console.log(violations)
    return violations

  createCilkscreenMarkers: (path, results) ->
    # Build a small cache of file path -> editor
    editorCache = {}
    editors = atom.workspace.getTextEditors()
    for textEditor in editors
      textEditorPath = textEditor.getPath()
      if textEditor.getPath() in editorCache
        editorCache[textEditorPath].push(textEditor)
      else
        editorCache[textEditorPath] = [textEditor]

    pluginView = new CilkscreenPluginView({}, ((e) => @onPanelClose(e)), ((path) => @getEditorFromPath(path)))
    @pluginView[path] = pluginView
    pluginView.setViolations(results)

    # Go through each of the cilkscreen violations and make markers accordingly.
    for i in [0 .. results.length - 1]
      violation = results[i]
      path1 = violation.line1.file
      path2 = violation.line2.file
      line1 = parseInt(violation.line1.line, 10)
      line2 = parseInt(violation.line2.line, 10)

      editorCache[path1].forEach((textEditor) =>
        @createCilkscreenMarker(path, textEditor, line1, results, i)
      )
      editorCache[path2].forEach((textEditor) =>
        @createCilkscreenMarker(path, textEditor, line2, results, i)
      )

  createCilkscreenMarker: (path, editor, line, violations, i) ->
    cilkscreenGutter = editor.gutterWithName('cilkscreen-lint')
    range = [[line - 1, 0], [line - 1, Infinity]]
    marker = editor.markBufferRange(range, {id: 'cilkscreen'})
    cilkscreenGutter.decorateMarker(marker, {type: 'gutter', item: new CilkscreenMarkerView(
      {index: i},
      (index) =>
        @onMarkerClick(path, index)
    )})

  onMarkerClick: (path, violationIndex) ->
    console.log("Marker clicked")
    console.log(violationIndex)
    console.log(this)
    console.log(@detailPanel)

    pluginView = @pluginView[path]
    pluginView.highlightViolation(violationIndex)
    # TODO: possibly further investigate flow issue here
    if @detailPanel
      @detailPanel.destroy()
    @detailPanel = atom.workspace.addBottomPanel(item: pluginView.getElement(), visible: true)
    pluginView.scrollToViolation()

  onStatusTileClick: () ->
    path = @editorToPath[atom.workspace.getActiveTextEditor().id]

    pluginView = @pluginView[path]
    # TODO: possibly further investigate flow issue here
    if @detailPanel
      @detailPanel.destroy()
    @detailPanel = atom.workspace.addBottomPanel(item: pluginView.getElement(), visible: true)

  updateStatusTile: () ->
    path = @getActivePanePath()
    if @currentCilkscreenState[path]
      if path and path isnt @statusBarElement.getCurrentPath()
        @statusBarElement.updatePath(@getActivePanePath())
        # Change the violation status...?
        if @currentCilkscreenState[path].start
          if @currentCilkscreenState[path].lastRuntime
            @statusBarElement.displayCountdown(@currentCilkscreenState[path].start + @currentCilkscreenState[path].lastRuntime)
          else
            @statusBarElement.displayUnknownCountdown()
        else if @currentCilkscreenState[path].numViolations
          @statusBarElement.displayErrors(@currentCilkscreenState[path].numViolations)
        else
          @statusBarElement.displayNoErrors()
    else
      @statusBarElement.displayNoErrors()

  onPanelClose: (e) ->
    @detailPanel.hide()

  destroyOldMarkers: (project) ->
    console.log(@pathToEditor)
    console.log(project)
    for editorId in @pathToEditor[project]
      editor = null
      for tEditor in atom.workspace.getTextEditors()
        if tEditor.id is editorId
          editor = tEditor
      markers = editor.findMarkers({id: 'cilkscreen'})
      console.log("Removing markers...")
      console.log(markers)
      for marker in markers
        marker.destroy()

  getEditorFromPath: (path) ->
    if path in @pathToEditor
      return @pathToEditor[path]
    return null

  getActivePanePath: () ->
    return @editorToPath[atom.workspace.getActiveTextEditor()?.id]

  # Event handlers
  registerEditor: (editor) ->
    console.log("Received a new editor")
    console.log(editor)
    # Add the editor to the newly registered editor.
    editor.addGutter({name: 'cilkscreen-lint', priority: -1, visible: true})

    @subscriptions.add(editor.onDidChangePath(()=>
      console.log("Editor changed path: " + editor.id)
    ))

    if not editor.getPath()?
      return

    # Register the editor with the package if it has a Makefile.
    # If it doesn't have a Makefile, then we don't register it with the plugin,
    # and none of the package callbacks will be called.
    filePath = path.resolve(editor.getPath(), '..')
    rootDir = path.parse(filePath).root
    console.log("Root dir: ", rootDir)
    loop
      console.log("Testing for Makefile: " + filePath)
      try
        stats = fs.statSync(path.resolve(filePath, 'Makefile'))
        if stats.isFile()
          break
      catch error
        filePath = path.resolve(filePath, '..')
      finally
        if filePath is rootDir
          return

    # Add the entry to the editor-to-path dictionary as well as the reverse
    # path-to-editor dictionary. This is for convenience later.
    @editorToPath[editor.id] = filePath
    if @pathToEditor[filePath]?
      @pathToEditor[filePath].push(editor.id)
    else
      @pathToEditor[filePath] = [editor.id]
    console.log(@editorToPath)

    @currentCilkscreenState[filePath] = {}

    # After the user stops changing the text, we start the timer to when we
    # initiate cilkscreen.
    @subscriptions.add(editor.onDidStopChanging(()=>
      console.log("Editor stopped changing: " + editor.id)
      console.log(new Date())
      currentProjectPath = @editorToPath[editor.id]
      @initializeCilkscreenTimer(currentProjectPath)
    ))
    @subscriptions.add(editor.onDidChange(()=>
      currentProjectPath = @editorToPath[editor.id]
      @clearCilkscreenTimer(currentProjectPath)
    ))
    @subscriptions.add(editor.onDidSave(()=>
      console.log("Saved!")
    ))
