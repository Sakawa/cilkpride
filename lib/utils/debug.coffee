DEBUG_ON = false

module.exports =
class Debug
  @log: (string) ->
    console.log(string) if DEBUG_ON

  @error: (string) ->
    console.error(string) if DEBUG_ON

  @info: (string) ->
    console.info(string) if DEBUG_ON

  @warn: (string) ->
    console.warn(string) if DEBUG_ON
