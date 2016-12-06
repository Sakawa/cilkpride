DEBUG_ON = false

module.exports =
class Debug
  if DEBUG_ON then @log = console.log.bind(window.console) else @log = () ->

  if DEBUG_ON then @error = console.error.bind(window.console) else @error = () ->

  if DEBUG_ON then @info = console.info.bind(window.console) else @info = () ->

  if DEBUG_ON then @warn = console.warn.bind(window.console) else @warn = () ->
