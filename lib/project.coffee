{CompositeDisposable} = require('atom')
fs = require('fs')
exec = require('child_process').exec
extend = require('util')._extend;
path = require('path');
process = require('process')
spawn = require('child_process').spawn

FileLineReader = require('./file-read-lines')
MarkerView = require('./cilkscreen-marker-view')
ProjectView = require('./cilkscreen-plugin-view')
CustomSet = require('./set')

module.exports =
class Project
  idleTimeout: null
  currentState: null
  subscriptions: null
  editorSubscriptions: null
  editorIds: null
  projectView: null
  markers: null
  settings: null

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
    @settings = JSON.parse(fs.readFileSync(
      path.resolve(@path, 'cilkscreen-conf.json'),
      {
        flags: 'r',
        encoding: 'utf-8',
      }
    ))
    console.log(@settings)

    @projectView = new ProjectView({
      onCloseCallback: (() => @onPanelCloseCallback())
    })

  # Timer functions

  initializeCilkscreenTimer: () ->
    clearInterval(@idleTimeout) if @idleTimeout
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
    # Ensure only one cilkscreen thread per project is active.
    @killCilkscreen()

    cilkLibPath = atom.config.get('cilkscreen-plugin.cilkLibPath')
    cilktoolsPath = atom.config.get('cilkscreen-plugin.cilktoolsPath')

    console.log(process.env)
    envCopy = extend({'LD_LIBRARY_PATH': cilkLibPath, 'LIBRARY_PATH': cilkLibPath}, process.env)
    envCopy.PATH = envCopy.PATH + ":" + cilktoolsPath

    @currentState.start = Date.now()
    console.log("Just set cilkscreenTime #{@path} to #{@currentState.start}")
    console.log("Last runtime: #{@currentState.lastRuntime}")
    @updateStatusTile()
    @currentState.thread = spawn('cilkscreen', @settings.commandArgs, {env: envCopy})
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
        @processViolations(cilkscreenOutput)
      else
        console.log("Code not 0...")
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
    makeThread = exec(@settings.makeCommand,
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

    # Go through each of the cilkscreen violations and make markers accordingly.
    for i in [0 .. results.length - 1]
      violation = results[i]
      path1 = violation.line1.filename
      path2 = violation.line2.filename
      line1 = +violation.line1.line
      line2 = +violation.line2.line
      violation.markers = []

      editorCache[path1]?.forEach((textEditor) =>
        violation.markers.push(@createCilkscreenMarker(textEditor, line1, i))
      )
      editorCache[path2]?.forEach((textEditor) =>
        violation.markers.push(@createCilkscreenMarker(textEditor, line2, i))
      )

    @projectView.setViolations(results)

  createCilkscreenMarker: (editor, line, i) ->
    cilkscreenGutter = editor.gutterWithName('cilkscreen-lint')
    range = [[line - 1, 0], [line - 1, Infinity]]
    marker = editor.markBufferRange(range, {id: 'cilkscreen'})
    markerView = new MarkerView(
      {index: i},
      (index) =>
        @onMarkerClickCallback(index)
    )
    cilkscreenGutter.decorateMarker(marker, {type: 'gutter', item: markerView})
    return markerView

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
          markers = editor?.findMarkers({id: 'cilkscreen'})
          console.log("Removing markers...")
          console.log(markers)
          for marker in markers
            marker.destroy()

  ###
    Violation processing code
  ###

  processViolations: (text) ->
    violations = @parseCilkscreenOutput(text)
    @getViolationLineCode(violations,
      (violations) =>
        @currentState.violations = violations
        @currentState.lastRuntime = Date.now() - @currentState.start
        console.log("Just set lastRuntime #{@path} to #{@currentState.lastRuntime}")
        @currentState.numViolations = violations.length
        console.log("The last run took #{@currentState.lastRuntime / 1000} seconds.")
        @createMarkers(violations)
        @currentState.start = null
        @updateStatusTile()
    )

  # Cilkscreen-related functions
  parseCilkscreenOutput: (text) ->
    text = text.split('\n')
    violations = []
    currentViolation = null

    # Run through it line by line to figure out what the race conditions are
    for line in text
      if line.indexOf("Race condition on location ") isnt -1
        # We have found the first line in a violation
        currentViolation = {stacktrace: {}, memoryLocation: line}
        currentStacktrace = []
        continue

      if currentViolation isnt null
        if line.indexOf("access at") isnt -1
          splitLine = line.trim().split(' ')
          accessType = splitLine[0]
          # console.log(splitLine)
          sourceCodeLine = splitLine[4].slice(1, -1)
          # console.log(sourceCodeLine)
          splitSC = sourceCodeLine.split(',')
          # There will be 6 elements if the line has a source code annotation.
          if splitLine.length is 6
            sourceCodeLine = splitSC[0]
            # console.log(sourceCodeLine)
            splitIndex = sourceCodeLine.lastIndexOf(':')
            sourceCodeFile = sourceCodeLine.substr(0, splitIndex)
            sourceCodeLine = +sourceCodeLine.substr(splitIndex + 1)
          # Otherwise, for some cilk_for calls, there is no extra information.
          else
            sourceCodeFile = null
            sourceCodeLine = null;

          lineData = {
            accessType: accessType,
            filename: sourceCodeFile,
            line: sourceCodeLine,
            rawText: line
          }

          # console.log(lineData)

          if currentViolation.line1
            currentViolation.line2 = lineData
            lineId = lineData.filename + ":" + lineData.line
            currentViolation.stacktrace[lineId] = []
          else
            currentViolation.line1 = lineData
            lineId = lineData.filename + ":" + lineData.line
            currentViolation.stacktrace[lineId] = []
        else if line.indexOf("called by") isnt -1
          # console.log(currentViolation)
          currentStacktrace.push(line)
        else
          lineId = currentViolation.line2.filename + ":" + currentViolation.line2.line
          currentViolation.stacktrace[lineId].push(currentStacktrace)
          violations.push(currentViolation)
          currentViolation = null

    mergeStacktraces = (entry, item) ->
      lineId = item.line2.filename + ":" + item.line2.line
      entry.stacktrace[lineId].push(item.stacktrace[lineId][0])

    # TODO: yes, fill this out
    isEqual = (obj1, obj2) ->
      isFileEqual = (file1, file2) ->
        return file1.filename is file2.filename and file1.line is file2.line

      return (isFileEqual(obj1.line1, obj2.line1) and isFileEqual(obj1.line2, obj2.line2)) or
        (isFileEqual(obj1.line2, obj2.line1) and isFileEqual(obj1.line1, obj2.line2))

    violationSet = new CustomSet(isEqual)
    violationSet.add(violations, mergeStacktraces)
    violations = violationSet.getContents()

    console.log("Pruned violations...")
    console.log(violations)
    return violations

  getViolationLineCode: (violations, next) ->
    HALF_CONTEXT = 2

    readRequestArray = []
    violations.forEach((item) =>
      if item.line1.filename
        readRequestArray.push([
          item.line1.filename,
          [item.line1.line - HALF_CONTEXT, item.line1.line + HALF_CONTEXT]
        ])
      if item.line2.filename
        readRequestArray.push([
          item.line2.filename,
          [item.line2.line - HALF_CONTEXT, item.line2.line + HALF_CONTEXT]
        ])
    )

    FileLineReader.readLineNumBatch(readRequestArray, (texts) =>
      @groupCodeWithViolations(violations, texts)
      next(violations)
    )

  groupCodeWithViolations: (violations, texts) ->
    for violation in violations
      codeSnippetsFound = 0
      # console.log(violation)
      for text in texts
        # console.log(text)
        if codeSnippetsFound is 2
          break
        if violation.line1.filename is text.filename and violation.line1.line - 2 is text.lineRange[0]
          violation.line1.text = text.text
          violation.line1.lineRange = text.lineRange
          codeSnippetsFound++
        if violation.line2.filename is text.filename and violation.line2.line - 2 is text.lineRange[0]
          violation.line2.text = text.text
          violation.line2.lineRange = text.lineRange
          codeSnippetsFound++
      if codeSnippetsFound < 2 and violation.line1.filename isnt null and violation.line2.filename isnt null
        console.log("groupCodeWithViolations: too few texts found for a violation")
    console.log("Finished groupCodeWithViolations")
    console.log(violations)

  ###
    Hooks
  ###

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
    console.log("highlightViolationInDetailPanel called: #{index}")
    @projectView.highlightViolation(index, true)

  scrollToViolation: () ->
    @projectView.scrollToViolation()

  getDetailPanel: () ->
    return @projectView.getElement()
