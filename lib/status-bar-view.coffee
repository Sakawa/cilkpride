$ = require('jquery')

MILLI_IN_HOUR = 1000 * 60 * 60
MILLI_IN_MIN = 1000 * 60
MILLI_IN_SEC = 1000

module.exports =
class StatusBarView
  element: null
  icon: null
  interval: null
  currentPath: null

  # Properties from parents
  props: null
  onErrorClickCallback: null

  constructor: (props) ->
    @props = props
    @onErrorClickCallback = props.onErrorClickCallback

    @element = document.createElement('div')
    @element.classList.add('cilkscreen-status-view', 'inline-block')
    @icon = document.createElement('span')
    @element.appendChild(@icon)

    @displayNoErrors()

  displayNoErrors: () ->
    if @interval?
      clearInterval(@interval)
    @icon.className = ''
    @icon.classList.add('icon', 'icon-check')
    @icon.textContent = "No races found"
    $(@icon).prop('onclick',null).off('click')

  displayErrors: (numErrors) ->
    if @interval?
      clearInterval(@interval)
    @icon.className = ''
    @icon.classList.add('icon', 'icon-issue-opened')
    @icon.textContent = "#{numErrors} errors found"
    $(@icon).on('click', (e) =>
      @onErrorClickCallback()
    )

  displayCountdown: (estFinished) ->
    if @interval?
      clearInterval(@interval)

    @icon.className = ''
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
    $(@icon).prop('onclick',null).off('click')

  displayUnknownCountdown: () ->
    @icon.className = ''
    @icon.classList.add('icon', 'icon-clock')
    @icon.textContent = "ETA Unknown"
    $(@icon).prop('onclick',null).off('click')

  constructTimerText: (time) ->
    msToFinish = time - Date.now()

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

  getCurrentPath: () ->
    return @currentPath

  hide: () ->
    @element.style.display = "none"

  show: () ->
    @element.style.display = "inline-block"

  getElement: () ->
    return @element
