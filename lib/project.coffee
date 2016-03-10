{CompositeDisposable} = require('atom')
exec = require('child_process').exec
extend = require('util')._extend;
process = require('process')
spawn = require('child_process').spawn

MarkerView = require('./cilkscreen-marker-view')
ProjectView = require('./cilkscreen-plugin-view')

module.exports =
class Project
  idleTimeout: null
  currentState: null
  subscriptions: null
  editorSubscriptions: null
  editorIds: null
  projectView: null
  markers: null

  # Properties from parent
  props: null
  onMarkerClickCallback: null
  onPanelCloseCallback: null
  path: null
  statusBar: null

  constructor: (props) ->
    @props = props
    @path = props.path
    @onMarkerClickCallback = @props.onMarkerClickCallback
    @onPanelCloseCallback = @props.onPanelCloseCallback
    @statusBar = @props.statusBar
    console.log("Status bar for #{@path}")
    console.log(@statusBar)

    @editorSubscriptions = {}
    @editorIds = []
    @currentState = {}
    @subscriptions = new CompositeDisposable()
    @markers = {}

    @projectView = new ProjectView({
      onCloseCallback: (() => @onPanelCloseCallback())
    })

  # Timer functions

  initializeCilkscreenTimer: () ->
    @idleTimeout = setTimeout(
      () =>
        console.log("Idle timeout start! #{new Date()}")
        @makeExecutable()
      , atom.config.get('cilkscreen-plugin.idleSeconds') * 1000
    )

  clearCilkscreenTimer: () ->
    clearInterval(@idleTimeout)
    if @currentState.start?
      @currentState.start = null;
    @killCilkscreen()

  startCilkscreen: () ->
    cilkLibPath = atom.config.get('cilkscreen-plugin.cilkLibPath')
    cilktoolsPath = atom.config.get('cilkscreen-plugin.cilktoolsPath')

    console.log(process.env)
    envCopy = extend({'LD_LIBRARY_PATH': cilkLibPath, 'LIBRARY_PATH': cilkLibPath}, process.env)
    envCopy.PATH = envCopy.PATH + ":" + cilktoolsPath

    @currentState.start = Date.now()
    console.log("Just set cilkscreenTime #{@path} to #{@currentState.start}")
    console.log("Last runtime: #{@currentState.lastRuntime}")
    @updateStatusTile()
    @currentState.thread = spawn('cilkscreen', ['./cilkscreen'], {env: envCopy})
    thread = @currentState.thread
    cilkscreenOutput = ""

    thread.stderr.on('data', (data) ->
      cilkscreenOutput += data
    )

    thread.on('close', (code) =>
      console.log("stderr: #{cilkscreenOutput}")
      console.log("cilkscreen process exited with code #{code}")
      if code is 0
        console.log("Killing old markers, if any...")
        @destroyOldMarkers()
        console.log("Parsing data...")
        parsedResults = @parseCilkscreenOutput(cilkscreenOutput)
        @currentState.violations = parsedResults
        @currentState.lastRuntime = Date.now() - @currentState.start
        console.log("Just set lastRuntime #{@path} to #{@currentState.lastRuntime}")
        @currentState.numViolations = parsedResults.length
        console.log("The last run took #{@currentState.lastRuntime / 1000} seconds.")
        @createMarkers(parsedResults)
      @currentState.start = null
      @updateStatusTile()
    )

    # Debug event handlers
    thread.on('error', (err) =>
      console.log("cilkscreen thread error: #{err}")
      @currentState.start = null
    )

    thread.on('exit', (code, signal) ->
      if code?
        console.log("cilkscreen exit: code #{code}")
      if signal?
        console.log("cilkscreen exit: signal #{signal}")
    )

  # Uses the cilkscreen target in the Makefile to make the executable so that
  # we can use cilkscreen on the executable.
  makeExecutable: () ->
    # First change the directory to the folder where the Makefile is.
    try
      process.chdir(@path)
      console.log("Successfully changed pwd to: #{@path}")
    catch error
      console.err("Could not change pwd to #{@path} with error #{error}")

    # Invoke the cilkscreen target to run cilkscreen on.
    # TODO: potentially allow the user to specify a make target
    makeThread = exec('make cilkscreen',
      (error, stdout, stderr) =>
        console.log("stdout: #{stdout}")
        console.log("stderr: #{stderr}")
        if error isnt null
          console.log('child process exited with code ' + error)
        else if not stdout.includes("Nothing to be done")
          @startCilkscreen()
    )

  createMarkers: (results) ->
    # Build a small cache of file path -> editor
    editorCache = {}
    editors = atom.workspace.getTextEditors()
    for textEditor in editors
      editorPath = textEditor.getPath?()
      if editorPath
        if editorPath in editorCache
          editorCache[editorPath].push(textEditor)
        else
          editorCache[editorPath] = [textEditor]

    @projectView.setViolations(results)

    # Go through each of the cilkscreen violations and make markers accordingly.
    for i in [0 .. results.length - 1]
      violation = results[i]
      path1 = violation.line1.filename
      path2 = violation.line2.filename
      line1 = +violation.line1.line
      line2 = +violation.line2.line

      editorCache[path1].forEach((textEditor) =>
        @createCilkscreenMarker(textEditor, line1, i)
      )
      editorCache[path2].forEach((textEditor) =>
        @createCilkscreenMarker(textEditor, line2, i)
      )

  createCilkscreenMarker: (editor, line, i) ->
    cilkscreenGutter = editor.gutterWithName('cilkscreen-lint')
    range = [[line - 1, 0], [line - 1, Infinity]]
    marker = editor.markBufferRange(range, {id: 'cilkscreen'})
    cilkscreenGutter.decorateMarker(marker, {type: 'gutter', item: new MarkerView(
      {index: i},
      (index) =>
        @onMarkerClickCallback(index)
    )})

  killCilkscreen: () ->
    console.log("Attempting to kill cilkscreen for path #{@path}...")
    thread = @currentState.thread
    if thread
      console.log(thread)
      thread.kill('SIGKILL')
      console.log("Killed thread...?")
      console.log(thread)
      delete @currentState.thread

  destroyOldMarkers: () ->
    for editorId in @editorIds
      console.log("Trying to find editor id #{editorId}")
      editor = null
      for tEditor in atom.workspace.getTextEditors()
        if tEditor.id is editorId
          editor = tEditor
      markers = editor.findMarkers({id: 'cilkscreen'})
      console.log("Removing markers...")
      console.log(markers)
      for marker in markers
        marker.destroy()

  # Cilkscreen-related functions
  parseCilkscreenOutput: (text) ->
    text = text.split('\n')
    violations = []
    currentViolation = null

    # Run through it line by line to figure out what the race conditions are
    for line in text
      if line.indexOf("Race condition on location ") isnt -1
        # We have found the first line in a violation
        currentViolation = {stacktrace: [], memoryLocation: line}
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
            accessType: accessType,
            filename: sourceCodeFile,
            line: +sourceCodeLine,
            rawText: line
          }

          console.log(lineData)

          if currentViolation.line1
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

  registerEditor: (editor) ->
    console.log("Trying to register an editor with project path #{@path}.")
    console.log(editor)
    if editor.id not in @editorIds
      @editorIds.push(editor.id)

    # After the user stops changing the text, we start the timer to when we
    # initiate cilkscreen.
    stopChangeDisposable = editor.onDidStopChanging(()=>
      console.log("Editor stopped changing: " + editor.id)
      console.log(new Date())
      @initializeCilkscreenTimer()
    )
    changeDisposable = editor.onDidChange(()=>
      @clearCilkscreenTimer()
    )
    saveDisposable = editor.onDidSave(()=>
      console.log("Saved!")
    )

    @editorSubscriptions[editor.id] = [stopChangeDisposable, changeDisposable, saveDisposable]
    @subscriptions.add(changeDisposable)
    @subscriptions.add(stopChangeDisposable)
    @subscriptions.add(saveDisposable)

  unregisterEditor: (editorId) ->
    for disposable in @editorSubscriptions[editorId]
      @subscriptions.remove(disposable)
    delete @editorSubscriptions[editorId]
    index = @editorIds.indexOf(editorId)
    @editorIds.splice(index, 1)

  updateStatusTile: () ->
    console.log("Updating status bar for #{@path}, current path being #{@statusBar.getCurrentPath()}")
    console.log(@statusBar)
    if @path is @statusBar.getCurrentPath()
      if @currentState.start
        if @currentState.lastRuntime
          @statusBar.displayCountdown(@currentState.start + @currentState.lastRuntime)
        else
          @statusBar.displayUnknownCountdown()
      else if @currentState.numViolations
        @statusBar.displayErrors(@currentState.numViolations)
      else
        @statusBar.displayNoErrors()

  highlightViolationInDetailPanel: (index) ->
    @projectView.highlightViolation(index)

  scrollToViolation: () ->
    @projectView.scrollToViolation()

  getDetailPanel: () ->
    return @projectView.getElement()
