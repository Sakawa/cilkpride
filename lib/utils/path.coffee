###
A quick helper function to add a series of directories into
an environment object, given a specific key. We expect the
directories to be separated by colons.
###

module.exports =
class PathUtils

  @combine: (object, key, values) ->
    if key not in Object.getOwnPropertyNames(object)
      object[key] = values
    else
      directories = values.split(':')
      if object[key].slice(-1) is ':'
        newDirectories = object[key].slice(0, -1)
      else
        newDirectories = object[key]
      existingDirectories = newDirectories.split(':')
      for dir in directories
        if dir not in existingDirectories
          newDirectories += ":#{dir}"
      object[key] = newDirectories
    return object
