$ = require('jquery')

module.exports =
class CilkideDetailPanel

  props: null
  onCloseCallback: null

  element: null
  header: null
  moduleContainer: null

  currentTab: null

  constructor: (props) ->
    @props = props
    @onCloseCallback = props.onCloseCallback

    # Create root element
    @element = document.createElement('div')
    @element.classList.add('cilkide-detail-panel', 'table')

    resizeDiv = document.createElement('div')
    resizeDiv.classList.add('cilkide-detail-resize')

    @element.appendChild(resizeDiv)
    $(resizeDiv).on('mousedown', @resizeStart)

    header = document.createElement('div')
    @header = header
    header.classList.add('header', 'table-row')
    close = document.createElement('div')
    close.classList.add('header-close', 'icon', 'icon-x')
    $(close).on('click', () =>
      @onCloseCallback()
      @currentTab.view.resetUI() if @currentTab
    )
    header.appendChild(close)

    @element.appendChild(header)

    # Everything else goes here.
    moduleContainer = document.createElement('div')
    @moduleContainer = moduleContainer
    moduleContainer.classList.add('cilkide-module-view-container', 'table-row')

    @element.appendChild(moduleContainer)

    @clickTriggers = {}

  resizeStart: () =>
    # console.log("Resize start")
    $(document).on('mousemove', @resizeMove)
    $(document).on('mouseup', @resizeStop)

  resizeStop: () =>
    # console.log("Resize stop")
    $(document).off('mousemove', @resizeMove)
    $(document).off('mouseup', @resizeStop)

  resizeMove: (event) =>
    return @resizeStop() unless event.which is 1

    element = $(@element)
    # console.log("Horizontal resize move")
    height = element.offset().top + element.outerHeight() - event.pageY
    element.height(height)

  clickTab: (newTab) ->
    if @currentTab is newTab
      return

    if @currentTab
      @currentTab.getElement().classList.remove('selected')
      @currentTab.view.resetUI()
    @currentTab = newTab
    newTab.getElement().classList.add('selected')
    $(@moduleContainer.firstChild).detach()
    @moduleContainer.appendChild(@currentTab.view.getElement())

  registerModuleTab: (name, view) ->
    tab = new Tab({name: name, onClickCallback: ((tab) => @clickTab(tab, name)), view: view})
    @header.appendChild(tab.getElement())
    if not @currentTab
      @clickTab(tab)
    return tab

class Tab
  element: null
  onClickCallback: null
  view: null

  constructor: (props) ->
    @onClickCallback = props.onClickCallback
    @view = props.view

    @element = document.createElement('div')
    @element.classList.add('cilkide-tab', 'inline-block')
    @icon = document.createElement('span')
    @icon.textContent = props.name
    @element.appendChild(@icon)
    $(@element).on('click', (e) =>
      @onClickCallback(this)
    )

  setState: (state) ->
    console.log("[tab] setting state to #{state}")
    @resetState()
    if state is "ok"
      @icon.classList.add('icon', 'icon-check')
    else if state is "execution_error"
      @icon.classList.add('icon', 'icon-x')
    else if state is "error"
      @icon.classList.add('icon', 'icon-issue-opened')
    else if state is "busy"
      @icon.classList.add('icon', 'icon-clock')
    else if state is "initializing"
      @icon.classList.add('icon', 'icon-sync')

  resetState: () ->
    @icon.className = ""

  # Programatically force a click (for module use)
  click: () ->
    @onClickCallback(this)

  getElement: () ->
    return @element
