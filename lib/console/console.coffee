dateFormat = require('dateformat')

module.exports =
class Console

  props: null

  element: null
  outputs: null

  # TODO: Fill this out
  constructor: (props) ->
    @element = document.createElement('div')
    @element.classList.add('console-container')

    @outputs = {}

  registerModule: (name) ->
    moduleDiv = document.createElement('div')
    moduleDiv.classList.add('console-div')

    moduleDescriptor = document.createElement('div')
    moduleDescriptor.classList.add('console-div-descriptor')
    moduleDescriptor.textContent = "#{name} - last updated some time ago"

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

    # TODO: update the last updated
    currentTime = dateFormat(new Date(), "h:MM TT")

    @outputs[name].children[0].textContent = "#{name} - last updated at #{currentTime}"
    @outputs[name].children[1].textContent = output

  resetUI: () ->
    return # nothing needed here

  destroy: () ->
    return

  getElement: () ->
    return @element
