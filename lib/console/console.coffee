###
This class controls the Console module for Cilkpride, which simply shows
raw output that the console gives back when running Cilkpride command line
tools. Since this module only shows text, it is fairly simple.

This is considered an 'essential' module, and must be initialized before any
unessential modules so that those modules can register with this console class.
###

dateFormat = require('dateformat')

module.exports =
class Console

  props: null       # Object containing parent-specified properties

  element: null     # Element containing the entire console view
  outputs: null     # Dictionary (module name -> console div for that module)

  # TODO: Fill this out
  constructor: (props) ->
    @props = props
    @element = document.createElement('div')
    @element.classList.add('console-container')

    @outputs = {}

  registerModule: (name) ->
    moduleDiv = document.createElement('div')
    moduleDiv.classList.add('console-div')

    moduleDescriptor = document.createElement('div')
    moduleDescriptor.classList.add('console-div-descriptor')
    moduleDescriptor.textContent = "#{name} - no updates yet!"

    moduleContainer = document.createElement('div')
    moduleContainer.classList.add('console-div-container')
    moduleContainer.textContent = "No output has been reported yet."

    moduleDiv.appendChild(moduleDescriptor)
    moduleDiv.appendChild(moduleContainer)

    @element.appendChild(moduleDiv)

    @outputs[name] = moduleDiv

  updateOutput: (name, output) ->
    if not @outputs[name]
      throw new Error("Module was not correctly registered with the console.")

    currentTime = dateFormat(new Date(), "h:MM TT")

    @outputs[name].children[0].textContent = "#{name} - last updated at #{currentTime}"
    @outputs[name].children[1].textContent = output

  resetUI: () ->
    return # nothing needed here

  destroy: () ->
    return

  getElement: () ->
    return @element
