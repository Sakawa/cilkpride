MarkerView = require('./cilkscreen-marker-view')
PluginView = require('./cilkscreen-plugin-view')

{normalizePath} = require('../utils/utils')

module.exports =
class CilkscreenUI

  props: null
  changePanel: null
  path: null

  pluginView: null
  currentViolationIndex: null
  currentViolations: null
  currentHighlightedIndex: null

  constructor: (props) ->
    @props = props
    @changePanel = props.changePanel
    @path = props.path

    @pluginView = new PluginView({
      changePanel: (() => @changePanel())
      onMarkerClick: (() => @onMarkerClickCallback())
      highlightCallback: ((e, index) => @highlightViolation(e, index, false))
      path: @path
    })

    @currentViolations = []

  createUI: (violations) ->
    @currentViolations = violations
    @createMarkers(violations)
    @pluginView.setViolations(violations)

  # Marker related functions

  createMarkers: (results) ->
    # Build a small cache of file path -> editor
    editorCache = {}
    editors = atom.workspace.getTextEditors()
    for textEditor in editors
      editorPath = normalizePath(textEditor.getPath?())
      if editorPath
        if editorPath in editorCache
          editorCache[editorPath].push(textEditor)
        else
          editorCache[editorPath] = [textEditor]

    # workaround to removing dupe markers
    markerCache = {}

    for i in [0 ... results.length]
      violation = results[i]
      path1 = violation.line1.filename
      path2 = violation.line2.filename
      line1 = +violation.line1.line
      line2 = +violation.line2.line
      violation.markers = []

      editorCache[path1]?.forEach((textEditor) =>
        id = textEditor.id + ":" + path1 + ":" + line1
        if markerCache[id]
          violation.markers.push(markerCache[id])
        else
          markerCache[id] = @createCilkscreenMarker(textEditor, line1, i)
          violation.markers.push(markerCache[id])
      )
      editorCache[path2]?.forEach((textEditor) =>
        id = textEditor.id + ":" + path2 + ":" + line2
        if markerCache[id]
          violation.markers.push(markerCache[id])
        else
          markerCache[id] = @createCilkscreenMarker(textEditor, line2, i)
          violation.markers.push(markerCache[id])
      )

  createMarkersForEditor: (editor) ->
    return if not editorPath = normalizePath(editor.getPath?())
    markerCache = {}

    for i in [0 ... @currentViolations.length]
      violation = @currentViolations[i]
      path1 = violation.line1.filename
      path2 = violation.line2.filename
      line1 = +violation.line1.line
      line2 = +violation.line2.line

      if path1 is editorPath
        id = editor.id + ":" + path1 + ":" + line1
        if markerCache[id]
          violation.markers.push(markerCache[id])
        else
          markerCache[id] = @createCilkscreenMarker(editor, line1, i)
          violation.markers.push(markerCache[id])
      if path2 is editorPath
        id = editor.id + ":" + path2 + ":" + line2
        if markerCache[id]
          violation.markers.push(markerCache[id])
        else
          markerCache[id] = @createCilkscreenMarker(editor, line2, i)
          violation.markers.push(markerCache[id])

    if @currentHighlightedIndex isnt null
      @highlightMarkers(@currentHighlightedIndex)

  createCilkscreenMarker: (editor, line, i) ->
    cilkscreenGutter = editor.gutterWithName('cilksan-lint')
    range = [[line - 1, 0], [line - 1, Infinity]]
    marker = editor.markBufferRange(range, {id: 'cilkscreen'})
    markerView = new MarkerView(
      {index: i},
      (index) =>
        @onMarkerClickCallback(index)
    )
    cilkscreenGutter.decorateMarker(marker, {type: 'gutter', item: markerView})
    return markerView

  onMarkerClickCallback: (index) ->
    @changePanel()
    @highlightViolation(null, index, true)

  destroyOldMarkers: () ->
    if @currentViolations
      for violation in @currentViolations
        console.log("Removing markers...")
        console.log(violation.markers)
        for marker in violation.markers
          marker.destroy()

  highlightMarkers: (index) ->
    console.log("[ui] marker")
    console.log(@currentViolations[index])
    for marker in @currentViolations[index].markers
      console.log("Highlighting marker...")
      marker.highlightMarker()
    if @currentViolations[index].minimapMarkers
      for marker in @currentViolations[index].minimapMarkers
        console.log("[ui] highlighting marker")
        console.log(marker)
        marker.classList.add('highlighted')

  resetMarkers: () ->
    console.log("in reset markers")
    console.log(@currentHighlightedIndex)
    if @currentHighlightedIndex isnt null
      console.log(@currentViolations[@currentHighlightedIndex])
      for marker in @currentViolations[@currentHighlightedIndex].markers
        console.log("Resetting marker...")
        marker.resetMarker()
      if @currentViolations[@currentHighlightedIndex].minimapMarkers
        for marker in @currentViolations[@currentHighlightedIndex].minimapMarkers
          marker.classList.remove('highlighted')

  # Highlight-related functions

  highlightViolation: (e, index, shouldScroll) ->
    console.log("highlightViolation called: #{index}")
    e.stopPropagation() if e

    # If we're already highlighting the correct violation, just scroll.
    if @currentHighlightedIndex is index
      @scrollToViolation(index)
      return

    # Otherwise, reset the other highlight and markers.
    if @currentHighlightedIndex isnt null
      @resetHighlight(@currentHighlightedIndex)

    @currentHighlightedIndex = index
    @pluginView.highlightViolation(index, shouldScroll)
    @highlightMarkers(index)

  resetHighlight: () ->
    @pluginView.resetHighlight(@currentHighlightedIndex)
    @resetMarkers()
    @currentHighlightedIndex = null

  scrollToViolation: (index) ->
    @pluginView.scrollToViolation(index)

  resetUI: () ->
    @resetHighlight()

  getElement: () ->
    return @pluginView.getElement()
