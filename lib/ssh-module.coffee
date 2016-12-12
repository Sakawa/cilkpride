###
This file contains a few classes: SSHModule, SFTP, and Instance.
SSHModule controls the core SSH-related functionality - it establishes
the SSH connection and provides the interface for other modules to get
SFTP and Instance objects.
###

Client = require('ssh2').Client
EventEmitter = require('events')

Debug = require('./utils/debug')
{extractLast} = require('./utils/utils')
PasswordView = require('./password-view')

class SSHModule

  props: null                  # Object containing parent-specified properties
  getSettings: null            # Function to retrieve updated project config settings
  onStateChange: null          # Callback for when the SSH connection changes (disconnect, connect, etc.)

  connection: null             # Client object representing the SSH connection
  connectionTimeout: null      # Timeout for the next connection attempt after a number of failed attempts
  consecFailedAttempts: null   # Number of consecutive failed SSH attempts
  eventEmitter: null           # EventEmitter for ready declaration

  state: null                  # String representing current SSHModule state

  destroyed: false             # True if the SSHModule is destroyed and no longer usable

  password: null               # Cached password for SSH auth in case of spontaneous disconnect
  passwordView: null           # PasswordView UI for user password prompt

  constructor: (props) ->
    Debug.log("[ssh-module] Created a new instance of SSHModule")
    @props = props
    @getSettings = props.getSettings
    @onStateChange = props.onStateChange
    @eventEmitter = new EventEmitter()
    @consecFailedAttempts = 0
    @state = "not_connected"

  startConnection: () ->
    clearTimeout(@connectionTimeout) if @connectionTimeout

    conn = new Client()
    @connection = conn

    @state = "connecting"
    @onStateChange()


    conn.on('ready', () =>
      Debug.log("[ssh-module] Connection ready.")
      settings = @getSettings()
      atom.notifications.addSuccess("Successfully SSHed into #{settings.username}@#{settings.hostname}.")
      @eventEmitter.emit('ready')
      @state = "connected"
      @onStateChange()
      @consecFailedAttempts = 0
    ).on('close', (hadError) =>
      Debug.log("[ssh-module] SFTP :: closed")
      @clean(conn)
      @state = "not_connected"
      @onStateChange()
    ).on('continue', () ->
      Debug.log("[ssh-module] SFTP :: continue received")
    ).on('end', () =>
      Debug.log("[ssh-module] SFTP :: end signal received")
      @clean(conn)
    ).on('error', (error) =>
      Debug.log("[ssh-module] SFTP :: received error #{error.level}")
      @clean(conn)
      # possible errors:
      # client-dns - DNS failure to lookup a hostname
      # client-timeout - auth timeout on client side or keepalive went unanswered too many times
      # client-socket - socket received an error
      # protocol - procotol failure? probably shouldn't happen
      # client-authentication - auth failed
      # agent - agent failed, probably shouldn't happen
      if error.level isnt 'client-authentication'
        @consecFailedAttempts += 1
      else
        @password = null
      @reconnect()
    ).on('keyboard-interactive', (name, instructions, instructionsLang, prompts, finish) =>
      Debug.log("[ssh-module] SFTP :: received keyboard interactive request")
      if @passwordView
        # rewire the old password view to pass the password to the new connection
        # TODO: potential race condition here where @connection is still connecting after a d/c
        @passwordView.onEnter = ((password) => @onEnterPassword(password, finish))
      else
        settings = @getSettings()

        @passwordView = new PasswordView({
          username: "#{settings.username}@#{settings.hostname}"
          onEnter: ((password) => @onEnterPassword(password, finish))
          onCancel: (() => @onCancelPassword())
        })
    )

    settings = @getSettings()
    conn.connect({
      host: settings.hostname
      port: settings.port
      username: settings.username
      password: if @password then @password else null
      tryKeyboard: true
      readyTimeout: 20000
      keepaliveInterval: 60000
    })
    Debug.log("[ssh-module] Starting to connect...")

  clean: (conn) ->
    if conn and conn is @connection
      clearTimeout(@connectionTimeout) if @connectionTimeout
      @connectionTimeout = null
      @connection.end()
      @connection = null
      Debug.log("[ssh-module] Module cleaned")

  getSFTP: (callback) ->
    return if @destroyed
    try
      @connection.sftp((err, sftp) =>
        if err
          Debug.log("[ssh-module] Received error in sftp")
          Debug.log(err)
          @reconnect()
        else
          Debug.log("[ssh-module] SFTP :: ready")
          callback(new SFTP({sftp: sftp, getSettings: (() => return @getSettings())}))
      )
    catch error
      Debug.log("[ssh-module] Received error in getSFTP")
      Debug.log(error)
      @reconnect()

  getInstance: (callback) ->
    return if @destroyed
    try
      @connection.shell({pty: true}, (err, stream) =>
        if err
          Debug.log("[ssh-module] Received error in shell")
          Debug.log(err)
          @reconnect()
        else
          Debug.log("[ssh-module] Instance :: ready")
          callback(new Instance({instance: stream, password: @password, getSettings: (() => return @getSettings())}))
      )
    catch error
      Debug.log("[ssh-module] Received error in getInstance")
      Debug.log(error)
      @reconnect()

  reconnect: () ->
    return if @destroyed

    @clean(@connection)

    # TODO: should change this to an backoff approach
    if @consecFailedAttempts > 3
      Debug.log("[ssh-module] >3 consecutive failed attempts, pausing for 30 seconds")
      clearTimeout(@connectionTimeout) if @connectionTimeout
      @connectionTimeout = setTimeout((() => @startConnection()), 30000)
    else
      @startConnection()

  onEnterPassword: (password, finish) ->
    @passwordView = null
    if @connection
      @password = password
      finish([password])
    else
      @startConnection()

  onCancelPassword: () ->
    @passwordView = null
    Debug.log("Cancel initiated.")
    @clean(@connection)
    @state = "not_connected"
    @onStateChange()

  destroy: () ->
    @destroyed = true
    clearTimeout(@connectionTimeout) if @connectionTimeout
    @eventEmitter.removeAllListeners()
    @connection.end() if @connection
    @passwordView.detach() if @passwordView

###
Wrapper class for using SFTP to transfer files.
###

class SFTP

  props: null             # Object containing parent-specified properties
  sftp: null              # SFTP connection interface (from SSHModule)
  getSettings: null       # Function to retrieve updated project config settings

  constructor: (props) ->
    @props = props
    @sftp = props.sftp
    @getSettings = props.getSettings

###
Wrapper class for using a remote SSH shell.
Extends EventEmitter to emulate being a thread.
###

# Regex for quickly grabbing the exit code.
regex = /cilkpride exit code: ([0-9]+)/

class Instance extends EventEmitter

  props: null          # Object containing parent-specified properties
  instance: null       # SSH connection interface (from SSHModule)
  initialized: false   # Boolean - true if the SSH interface is fully setup and functional
  passwordFlag: false  # Boolean - used if we're doing a double-SSH (6.172 launch-instance, for example)
                       #           to keep track of which SSH we're in
  getSettings: null    # Function to retrieve updated project config settings
  ready: false         # Boolean - true if the SSH interface is ready to take another command

  output: null         # String containing the output of the current command running
  command: null        # String containing the next command queued

  constructor: (props) ->
    Debug.log('[instance] Instance constructed')
    @props = props
    @instance = props.instance
    @getSettings = props.getSettings

    settings = @getSettings()
    if settings.launchInstance
      @instance.write('launch-instance\n')
    else
      # We run bash so that the command prompt looks like ~$
      @instance.write('bash\n')
    @output = ''
    # 'ready' event denotes that the instance is ready to process another command
    @on('ready', () =>
      Debug.log('[instance] Instance received ready signal')
      if @command
        Debug.log('[instance] Performing backlogged command...')
        command = @command
        @command = null
        command()
    )
    @init(props.password)

  init: (password) ->
    @instance.on('close', () =>
      Debug.log('[instance] Connection closed')
      @destroy()
    ).on('end', () =>
      Debug.log('[instance] Connection ended')
      @destroy()
    ).on('data', (data) =>
      @output += data
      Debug.log('STDOUT: ' + data)

      settings = @getSettings()
      # Deals with entering in the user's password on launch-instance
      if settings.launchInstance and not @passwordFlag and extractLast(@output, 10) is "Password: "
        @instance.write("#{password}\n")
        @passwordFlag = true
        @resetOutput()
        return

      # Deals with the initial command prompt
      if not @initialized and extractLast(@output, 4) is ":~$ "
        @initialized = true
        @ready = true
        @emit('initialized')
        @resetOutput()
        return

      # Deals with with identifying when a command is finished
      if extractLast(@output, 2) is "$ "
        exitResults = @parseExitCode(@output)
        @ready = true
        if exitResults # right now, false signifies a kill
          @emit('data', exitResults.exitCode, @output.substring(0, exitResults.index))
        @resetOutput()
        @emit('ready')
        Debug.log("[ssh-module] Instance emitted ready!")
    ).on('error', (err) =>
      Debug.log("[instance] Error received")
      Debug.log(err)
      @destroy()
    ).on('finish', () =>
      Debug.log('[instance] Instance finished.')
      @destroy()
    )

  spawn: (command, args, options) ->
    # TODO: Should we ignore commands that are input when the network isn't ready?
    Debug.log("[instance] received spawn request: init: #{@initialized} | ready: #{@ready}")
    if not @initialized or not @ready
      @command = (() => @spawn(command, args, options))
      return
    @ready = false
    commandString = ''
    if options?.pwd
      commandString += "cd #{options.pwd}; "
    commandString += command + " " + args.join(' ')
    Debug.log("[instance] running #{commandString};")
    @instance.write("#{commandString}; echo cilkpride exit code: $?\n")

  kill: () ->
    if @instance and @initialized and not @ready
      @instance.write('\u0003')
      return true
    return false

  resetOutput: () ->
    @output = ''

  parseExitCode: (output) ->
    results = regex.exec(output)
    if results is null
      Debug.log("[instance] no cilkpride exit code found")
      return false
    else
      Debug.log("[instance] found exit code #{parseInt(results[1])}")
      return {exitCode: parseInt(results[1]), index: results.index}

  destroy: () ->
    @instance.end() if @instance
    @instance = null
    @initialized = false
    @ready = false
    @output = null
    @emit('destroyed')

module.exports = SSHModule
