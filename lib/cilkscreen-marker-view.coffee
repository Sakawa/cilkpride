CilkscreenPluginView = require('./cilkscreen-plugin-view')

module.exports =
class CilkscreenMarkerView
  state: null
  pluginView: null
  modal: null

  constructor: (state) ->
    @state = state
    @pluginView = new CilkscreenPluginView(state, @onModalCloseClick)
    @modal = atom.workspace.addModalPanel(item: @pluginView.getElement(), visible: false)
    # TODO: This really sucks, please save me from such horrors
    @modal.item.parentElement.classList.add("cilkscreen-detail-modal")
    console.log(@modal)

    # Create root element
    @element = document.createElement('div')
    @element.classList.add('cilkscreen-marker')
    @element.textContent = "1"

    @element.title = "Click to view more details."

    @element.onclick = (e) =>
      @gutterOnClick()

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->
    @modal.destroy()
    @element.remove()
    @pluginView.destroy()

  getElement: ->
    @element

  gutterOnClick: () ->
    @modal.show()

  onModalCloseClick: (e) =>
    @modal.hide()
