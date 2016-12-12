###
A medley of small Util classes.

MinimapUtil: Util class for figuring out the exact positioning of minimap lines.
TextEditorUtil: Util class for creating an Atom TextEditor.
extractLast: Extracts the last n characters in a string.
normalizePath: Replaces all Windows-style '\' characters in a path with POSIX '/'.
###

path = require('path').posix
TextEditor = null

class MinimapUtil
  VERTICAL_PADDING = 5
  HORIZONTAL_PADDING = 20
  CANVAS_WIDTH = 150
  LINE_HEIGHT = 4

  constructor: () ->

  @getLeftSide: (index, offset) ->
    leftSide = (index * (HORIZONTAL_PADDING * 2 + CANVAS_WIDTH)) + HORIZONTAL_PADDING
    leftSide += offset if offset
    return leftSide

  @getRightSide: (index) ->
    return (index + 1) * (HORIZONTAL_PADDING * 2 + CANVAS_WIDTH) - HORIZONTAL_PADDING

  @getLineTop: (line, offset) ->
    top = line * LINE_HEIGHT - 2
    top += offset if offset
    return top

class TextEditorUtil
  @constructTextEditor: (params) ->
    if atom.workspace.buildTextEditor?
      lineEditor = atom.workspace.buildTextEditor(params)
    else
      TextEditor ?= require("atom").TextEditor
      lineEditor = new TextEditor(params)
    return lineEditor

extractLast = (str, numChar) ->
  return str.substring(str.length - numChar, str.length)

normalizePath = (filePath) ->
  if filePath
    return path.normalize(filePath.replace(/\\/g, '/'))
  else
    return null

module.exports = {MinimapUtil, TextEditorUtil, extractLast, normalizePath}
