###
Class representing the status bar view in the text editor. Mostly contains
functions that wil change the displayed status, for other modules to call.
###

$ = require('jquery')
path = require('path').posix

Debug = require('./utils/debug')

MILLI_IN_SEC = 1000
MILLI_IN_MIN = MILLI_IN_SEC * 60
MILLI_IN_HOUR = MILLI_IN_MIN * 60

module.exports =
class StatusBarView
  currentPath: null       # The path of the project that the active text editor belongs to
  currentText: null       # The current text being shown in the status bar
  interval: null          # Interval for updating the status bar on ETA countdowns
  lastUpdatedTimer: null  # Timeout for updating the status bar last updated feature
  lastUpdated: null       # Time (in Unix time milliseconds) of the last status update

  # UI elements
  element: null           # Element for the status bar div
  icon: null              # The visual icon next to the status bar text
  tooltip: null           # Tooltip to be displayed on status bar hover

  # Properties from parents
  props: null                      # Object containing parent-specified properties
  onClickCallback: null            # Callback when status bar is clicked
  onRegisterProjectCallback: null  # Callback when user selects directory to create Cilkpride project in
  onConnectCallback: null          # Callback when user clicks "Connect to SSH" status bar

  constructor: (props) ->
    @props = props
    @onClickCallback = props.onClickCallback
    @onRegisterProjectCallback = props.onRegisterProjectCallback
    @onConnectCallback = props.onConnectCallback

    @element = document.createElement('div')
    @element.classList.add('cilkpride-status-view', 'inline-block')
    @icon = document.createElement('span')
    @element.appendChild(@icon)
    @lastUpdated = Date.now()

  displayNoErrors: (update) ->
    @resetState()
    @icon.classList.add('icon', 'icon-check')
    @currentText = "No issues!"
    $(@icon).on('click', (e) => @onClickCallback())
    @lastUpdated = Date.now() unless update
    @setTimer(@lastUpdated)

  displayPluginDisabled: () ->
    @resetState()
    @icon.classList.add('icon', 'icon-repo-create')
    @icon.textContent = "Register Cilk project"
    $(@icon).on('click', (e) =>
      atom.pickFolder((paths) =>
        @onRegisterProjectCallback(paths)
      )
    )
    @tooltip = atom.tooltips.add(@element, {
      title: "Click to enable the Cilkpride plugin for a project."
    })

  displayErrors: (update) ->
    @resetState()
    @icon.classList.add('icon', 'icon-issue-opened')
    @currentText = "Errors reported"
    $(@icon).on('click', (e) => @onClickCallback())
    @lastUpdated = Date.now() unless update
    @setTimer(@lastUpdated)

  displayCountdown: (estFinished) ->
    @resetState()
    @icon.classList.add('icon', 'icon-clock')
    $(@icon).on('click', (e) => @onClickCallback())

    if estFinished
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
    else
      @icon.textContent = "Running (ETA Unknown)"

  displayExecutionError: (update) ->
    @resetState()
    @icon.classList.add('icon', 'icon-x')
    @currentText = "Execution error"
    @lastUpdated = Date.now() unless update
    @setTimer(@lastUpdated)
    $(@icon).on('click', (e) => @onClickCallback())

  displayConfigError: (update) ->
    @resetState()
    @icon.classList.add('icon', 'icon-issue-opened', 'clickable')
    @currentText = "Configuration error"
    @lastUpdated = Date.now() unless update
    @setTimer(@lastUpdated)
    $(@icon).on('click', (e) =>
      atom.workspace.open(path.join(@currentPath, "cilkpride-conf.json"))
    )

  displayLoading: (update) ->
    @resetState()
    @icon.classList.add('icon', 'icon-sync')
    @currentText = "SSHing..."
    @lastUpdated = Date.now() unless update
    @setTimer(@lastUpdated)
    $(@icon).on('click', (e) => @onClickCallback())

  displayStart: () ->
    @resetState()
    @icon.classList.add('icon', 'icon-question')
    @icon.textContent = "Cilkpride not yet run (Save to start)"
    $(@icon).on('click', (e) => @onClickCallback())

  displayNotConnected: () ->
    @resetState()
    @icon.classList.add('icon', 'icon-plug')
    @icon.textContent = "Not connected to SSH server"
    $(@icon).on('click', (e) => @onConnectCallback())

  constructTimerText: (time) ->
    msToFinish = time - Date.now()

    if msToFinish < 0
      return "Running (ETA Unknown)"

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
    Debug.log("Updating status bar tile path to #{path}.")
    @currentPath = path

  setTimer: () ->
    @updateLastUpdated()

  updateLastUpdated: () ->
    currentTime = Date.now()
    secAgo = Math.floor((currentTime - @lastUpdated) / MILLI_IN_SEC)
    if secAgo < 60
      @icon.textContent = "#{@currentText} (<1 min ago)"
      @lastUpdatedTimer = setTimeout((() => @updateLastUpdated()), MILLI_IN_MIN)
      return
    if secAgo < 3600
      minAgo = Math.floor(secAgo / 60)
      @icon.textContent = "#{@currentText} (#{minAgo} min ago)"
      @lastUpdatedTimer = setTimeout((() => @updateLastUpdated()), MILLI_IN_MIN)
      return

    hrAgo = Math.floor(secAgo / 60 / 60)
    @icon.textContent = "#{@currentText} (#{hrAgo} hrs ago)"
    @lastUpdatedTimer = setTimeout((() => @updateLastUpdated()), MILLI_IN_HOUR)
    return

  getCurrentPath: () ->
    return @currentPath

  hide: () ->
    @element.style.display = "none"

  show: () ->
    @element.style.display = "inline-block"

  resetState: () ->
    clearInterval(@interval) if @interval
    @tooltip.dispose() if @tooltip
    clearInterval(@lastUpdatedTimer) if @lastUpdatedTimer
    @currentText = null

    @icon.className = ""
    @icon.textContent = ""
    @icon.title = ""
    $(@icon).prop('onclick',null).off('click')

  getElement: () ->
    return @element
