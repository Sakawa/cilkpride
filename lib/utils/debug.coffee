###
Debug class. DEBUG_ON = true will show all console messages for debug purposes,
while DEBUG_ON = false should be for production purposes.
###

DEBUG_ON = true

module.exports =
class Debug
  if DEBUG_ON then @log = console.log.bind(window.console) else @log = () ->

  if DEBUG_ON then @error = console.error.bind(window.console) else @error = () ->

  if DEBUG_ON then @info = console.info.bind(window.console) else @info = () ->

  if DEBUG_ON then @warn = console.warn.bind(window.console) else @warn = () ->
