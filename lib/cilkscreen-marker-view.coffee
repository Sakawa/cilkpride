CilkscreenPluginView = require('./cilkscreen-plugin-view')

module.exports =
class CilkscreenMarkerView
  state: null
  pluginView: null
  modal: null

  constructor: (state) ->
    @state = state
    @pluginView = new CilkscreenPluginView(state, @onModalCloseClick)
    # TODO: Replace this with a bottom panel or something - modals are not good.
    @modal = atom.workspace.addModalPanel(item: @pluginView.getElement(), visible: false)
    @modal.item.parentElement.classList.add("cilkscreen-detail-modal")
    console.log(@modal)

    # Create root element
    @element = document.createElement('span')
    @element.classList.add('alert')
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
