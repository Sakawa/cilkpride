CilkscreenMarkerView = require('./cilkscreen-marker-view')
{CompositeDisposable} = require('atom')
fs = require('fs')
path = require('path')
process = require('process')
exec = require('child_process').exec
spawn = require('child_process').spawn
extend = require('util')._extend;

module.exports = CilkscreenPlugin =
  subscriptions: null
  idleTimeout: null
  cilkscreenThread: null
  editorToPath: {}
  pathToEditor: {}

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'cilkscreen-plugin:toggle': => @toggle()

    # Add a hook on every single text editor that is open (and will be opened in the future)
    @subscriptions.add(atom.workspace.observeTextEditors(
      (editor) =>
        @registerEditor(editor)
    ))

  deactivate: ->
    @subscriptions.dispose()

  serialize: ->
    cilkscreenPluginViewState: @cilkscreenPluginView.serialize()

  toggle: ->
    console.log 'CilkscreenPlugin was toggled!'

  # Timer functions

  initializeCilkscreenTimer: (id) ->
    @idleTimeout = setTimeout(
      () =>
        console.log(new Date())
        @makeExecutable(id)
      , 5000
    )

  clearCilkscreenTimer: () ->
    clearInterval(@idleTimeout)
    @killCilkscreen()

  startCilkscreen: (editorId) ->
    currentProjectPath = @editorToPath[editorId]
    # TODO: turn this into a config setting to allow users to designate cilk locations
    cilkLinkerPath = "/home/taiga/gcc/lib:/home/taiga/gcc/lib64"
    cilkLibPath = "/home/taiga/gcc/lib:/home/taiga/gcc/lib64"

    envCopy = extend({'LD_LIBRARY_PATH': cilkLinkerPath, 'LIBRARY_PATH': cilkLibPath}, process.env)

    @cilkscreenThread = spawn('cilkscreen', ['./cilkscreen'], {env: envCopy})
    cilkscreenOutput = ""

    @cilkscreenThread.stderr.on('data', (data) ->
      cilkscreenOutput += data
    )

    @cilkscreenThread.on('close', (code) =>
        console.log("stderr: #{cilkscreenOutput}")
        console.log("cilkscreen process exited with code #{code}")
        if code is 0
          console.log("Killing old markers, if any...")
          @destroyOldMarkers(currentProjectPath)
          console.log("Parsing data...")
          parsedResults = @parseCilkscreenOutput(cilkscreenOutput)
          @createCilkscreenMarkers(parsedResults)
    )

    # Debug event handlers
    @cilkscreenThread.on('error', (err) =>
      console.log("cilkscreen thread error: #{err}")
    )

    @cilkscreenThread.on('exit', (code, signal) =>
      if code?
        console.log("cilkscreen exit: code #{code}")
      if signal?
        console.log("cilkscreen exit: signal #{signal}")
    )

    console.log(envCopy)

  # Uses the cilkscreen target in the Makefile to make the executable so that
  # we can use cilkscreen on a well-defined object.
  makeExecutable: (editorId) ->
    currentProjectPath = @editorToPath[editorId]

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
          @startCilkscreen(editorId)
    )

  killCilkscreen: () ->
    console.log("Attempting to kill cilkscreen...")
    if @cilkscreenThread
      console.log(@cilkscreenThread)
    if @cilkscreenThread
      @cilkscreenThread.kill('SIGKILL')
      console.log("Killed thread...?")
      console.log(@cilkscreenThread)
      @cilkscreenThread = null

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
            line: sourceCodeLine,
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

  createCilkscreenMarkers: (results) ->
    # Build a small cache of file path -> editor
    editorCache = {}
    editors = atom.workspace.getTextEditors()
    for textEditor in editors
      editorCache[textEditor.getPath()] = textEditor

    # Go through each of the cilkscreen violations and make markers accordingly.
    for i in [0 .. results.length - 1]
      violation = results[i]
      path1 = violation.line1.file
      path2 = violation.line2.file
      line1 = parseInt(violation.line1.line, 10)
      line2 = parseInt(violation.line2.line, 10)

      if editorCache[path1]?
        @createCilkscreenMarker(editorCache[path1], line1, results, i)
      if editorCache[path2]?
        @createCilkscreenMarker(editorCache[path2], line2, results, i)

  createCilkscreenMarker: (editor, line, violations, i) ->
    cilkscreenGutter = editor.gutterWithName('cilkscreen-lint')
    range = [[line - 1, 0], [line - 1, Infinity]]
    marker = editor.markBufferRange(range, {id: 'cilkscreen'})
    cilkscreenGutter.decorateMarker(marker, {type: 'gutter', item: new CilkscreenMarkerView({violations: violations, index: i})})

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

  # Event handlers
  registerEditor: (editor) ->
    console.log("Received a new editor")
    console.log(editor)
    # Add the editor to the newly registered editor.
    editor.addGutter({name: 'cilkscreen-lint', priority: -1, visible: true})

    # Register the editor with the package - if it has a Makefile.
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

    # After the user stops changing the text, we start the timer to when we
    # initiate cilkscreen.
    @subscriptions.add(editor.onDidStopChanging(()=>
      console.log("Editor stopped changing: " + editor.id)
      console.log(new Date())
      @initializeCilkscreenTimer(editor.id)
    ))
    @subscriptions.add(editor.onDidChange(()=>
      @clearCilkscreenTimer()
    ))
    @subscriptions.add(editor.onDidSave(()=>
      console.log("Saved!")
    ))
