$ = require('jquery')
{TimeUtil} = require('./utils')
path = require('path')

MILLI_IN_HOUR = 1000 * 60 * 60
MILLI_IN_MIN = 1000 * 60
MILLI_IN_SEC = 1000

module.exports =
class StatusBarView
  element: null
  icon: null
  interval: null
  currentPath: null
  tooltip: null

  # Properties from parents
  props: null
  onErrorClickCallback: null
  onRegisterProjectCallback: null

  constructor: (props) ->
    @props = props
    @onErrorClickCallback = props.onErrorClickCallback
    @onRegisterProjectCallback = props.onRegisterProjectCallback

    @element = document.createElement('div')
    @element.classList.add('cilkscreen-status-view', 'inline-block')
    @icon = document.createElement('span')
    @element.appendChild(@icon)

  displayNoErrors: (lastUpdated) ->
    @resetState()
    @icon.classList.add('icon', 'icon-check')
    @icon.textContent = "No races found"
    if lastUpdated
      @addTooltip(lastUpdated)

  displayPluginDisabled: () ->
    @resetState()
    @icon.classList.add('icon', 'icon-repo-create')
    @icon.textContent = "Register Cilk project"
    $(@icon).on('click', (e) =>
      atom.pickFolder((paths) =>
        console.log(paths)
        @onRegisterProjectCallback(paths)
      )
    )
    @tooltip = atom.tooltips.add(@element, {
      title: "Click to enable the Cilktool plugin for a project."
    })

  displayErrors: (numErrors, lastUpdated) ->
    @resetState()
    @icon.classList.add('icon', 'icon-issue-opened')
    @icon.textContent = "#{numErrors} errors found"
    $(@icon).on('click', (e) =>
      @onErrorClickCallback()
    )
    @addTooltip(lastUpdated)

  displayCountdown: (estFinished) ->
    @resetState()
    @icon.classList.add('icon', 'icon-clock')
    @icon.textContent = @constructTimerText(estFinished)
    @interval = setInterval(
      () =>
        msToFinish = estFinished - Date.now()
        if msToFinish < 0
          clearInterval(@interval)
        else
          @icon.textContent = @constructTimerText(estFinished)
      , 1000
    )

  displayUnknownCountdown: () ->
    @resetState()
    @icon.classList.add('icon', 'icon-clock')
    @icon.textContent = "Time Left Unknown"

  displayExecError: (lastUpdated) ->
    @resetState()
    @icon.classList.add('icon', 'icon-x')
    @icon.textContent = "Unable to run cilkscreen"
    @addTooltip(lastUpdated)

  displayMakeError: (lastUpdated) ->
    @resetState()
    @icon.classList.add('icon', 'icon-x', 'clickable')
    @icon.textContent = "Unable to make"
    @addTooltip(lastUpdated)
    $(@icon).on('click', (e) =>
      atom.workspace.open(path.join(@currentPath, "Makefile"))
    )

  displayConfError: (lastUpdated) ->
    @resetState()
    @icon.classList.add('icon', 'icon-x', 'clickable')
    @icon.textContent = "Configuration error"
    @addTooltip(lastUpdated)
    $(@icon).on('click', (e) =>
      atom.workspace.open(path.join(@currentPath, "cilkscreen-conf.json"))
    )

  displayStart: () ->
    @resetState()
    @icon.classList.add('icon', 'icon-question')
    @icon.textContent = "Cilktools not yet run"

  constructTimerText: (time) ->
    msToFinish = time - Date.now()

    if msToFinish < 0
      return "Time Left Unknown"

    timerText = ''
    h = Math.floor(msToFinish / MILLI_IN_HOUR)
    m = Math.floor((msToFinish % MILLI_IN_HOUR) / MILLI_IN_MIN)
    s = Math.floor((msToFinish % MILLI_IN_MIN) / MILLI_IN_SEC)

    if h > 0
      timerText += "#{h}h"
    timerText += "#{m}m"
    timerText += "#{s}s"
    return timerText

  updatePath: (path) ->
    console.log("Updating status bar tile path to #{path}.")
    @currentPath = path

  addTooltip: (lastUpdated) ->
    @tooltip = atom.tooltips.add(@element, {
      title: "Last updated: #{TimeUtil.getTimeSince(lastUpdated)}"
    })

  getCurrentPath: () ->
    return @currentPath

  hide: () ->
    @element.style.display = "none"

  show: () ->
    @element.style.display = "inline-block"

  resetState: () ->
    if @interval?
      clearInterval(@interval)
    if @tooltip
      @tooltip.dispose()

    @icon.className = ""
    @icon.textContent = ""
    @icon.title = ""
    $(@icon).prop('onclick',null).off('click')

  getElement: () ->
    return @element
