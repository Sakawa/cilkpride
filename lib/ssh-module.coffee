Client = require('ssh2').Client
EventEmitter = require('events')

{extractLast} = require('./utils/utils')
PasswordView = require('./password-view')

class SSHModule

  props: null
  refreshConfFile: null
  settings: null

  connection: null
  connectionTimeout: null
  consecFailedAttempts: null
  eventEmitter: null

  password: null
  passwordView: null

  constructor: (props) ->
    console.log("[ssh-module] Created a new instance of SSHModule")
    @props = props
    @settings = props.settings
    @refreshConfFile = props.refreshConfFile
    @eventEmitter = new EventEmitter()
    @consecFailedAttempts = 0

    @startConnection()

  startConnection: () ->
    @eventEmitter.emit('connecting')

    conn = new Client()
    @connection = conn

    conn.on('ready', () =>
      console.log("[ssh-module] Connection ready.")
      @eventEmitter.emit('ready')
      @consecFailedAttempts = 0
    ).on('close', (hadError) =>
      console.log("[ssh-module] SFTP :: closed")
      @clean(conn)
    ).on('continue', () ->
      console.log("[ssh-module] SFTP :: continue received")
    ).on('end', () =>
      console.log("[ssh-module] SFTP :: end signal received")
      @clean(conn)
    ).on('error', (error) =>
      console.log("[ssh-module] SFTP :: received error #{error.level}")
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
      console.log("[ssh-module] SFTP :: received keyboard interactive request")
      if @passwordView
        # rewire the old password view to pass the password to the new connection
        # TODO: potential race condition here where @connection is still connecting after a d/c
        @passwordView.onEnter = ((password) => @onEnterPassword(password, finish))
      else
        @passwordView = new PasswordView({
          description: "Please enter your password for #{@settings.username}@#{@settings.hostname}.\n
            Note: The plugin will attempt to login with this password in the event of network interruptions for the rest of this session."
          onEnter: ((password) => @onEnterPassword(password, finish))
          onCancel: (() => @onCancelPassword())
        })
    )

    conn.connect({
      host: @settings.hostname
      port: @settings.port
      username: @settings.username
      password: if @password then @password else null
      tryKeyboard: true
      readyTimeout: 20000
      keepaliveInterval: 60000
    })
    console.log("[ssh-module] Starting to connect...")

  clean: (conn) ->
    if conn is @connection
      @connection = null
      console.log("[ssh-module] Module cleaned")

  getSFTP: (callback) ->
    try
      @connection.sftp((err, sftp) =>
        if err
          console.log("[ssh-module] Received error in sftp")
          console.log(err)
          @reconnect()
        else
          console.log("[ssh-module] SFTP :: ready")
          callback(new SFTP({sftp: sftp, settings: @settings}))
      )
    catch error
      console.log("[ssh-module] Received error in getSFTP")
      console.log(error)
      @reconnect()

  getInstance: (callback) ->
    try
      @connection.shell({pty: true}, (err, stream) =>
        if err
          console.log("[ssh-module] Received error in shell")
          console.log(err)
          @reconnect()
        else
          console.log("[ssh-module] Instance :: ready")
          callback(new Instance({instance: stream, password: @password, settings: @settings}))
      )
    catch error
      console.log("[ssh-module] Received error in getInstance")
      console.log(error)
      @reconnect()

  reconnect: () ->
    @clean(@connection)
    @settings = @refreshConfFile()
    if @consecFailedAttempts > 3
      console.log("[ssh-module] >3 consecutive failed attempts, pausing for 30 seconds")
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
    console.log("Cancel initiated.")
    @connection.end() if @connection

  destroy: () ->
    clearTimeout(@connectionTimeout) if @connectionTimeout
    @connection.end() if @connection
    @eventEmitter.removeAllListeners()
    @passwordView.detach() if @passwordView

###
Wrapper class for using FTP to transfer files
###

class SFTP

  sftp: null
  settings: null

  constructor: (props) ->
    @sftp = props.sftp
    @settings = props.settings

###
Wrapper class for using an instance [6.172 launch-instance]
Extends EventEmitter to emulate being a thread
###

# This regex allows us to quickly grab the exit code.
regex = /cilkide exit code: ([0-9]+)/

class Instance extends EventEmitter

  instance: null
  initialized: false
  passwordFlag: false
  ready: false
  killFlag: false

  output: null
  command: null

  constructor: (props) ->
    console.log('[instance] Instance constructed')
    @instance = props.instance
    @stderr = @instance.stderr
    @instance.write('launch-instance\n')
    @output = ''
    # 'ready' event denotes that the instance is ready to process another command
    @on('ready', () =>
      console.log('[instance] Instance received ready signal')
      if @command
        console.log('[instance] Performing backlogged command...')
        command = @command
        @command = null
        command()
    )
    @init(props.password)

  init: (password) ->
    @instance.on('close', () =>
      console.log('[instance] Connection closed')
      @destroy()
    ).on('end', () =>
      console.log('[instance] Connection ended')
      @destroy()
    ).on('data', (data) =>
      @output += data
      console.log('STDOUT: ' + data)
      # Deals with entering in the user's password on launch-instance
      if not @passwordFlag and extractLast(@output, 10) is "Password: "
        @instance.write("#{password}\n")
        @passwordFlag = true
        @resetOutput()
        return

      # Deals with the initial command prompt
      if not @initialized and extractLast(@output, 14) is "@localhost:~$ "
        @initialized = true
        @ready = true
        @emit('initialized')
        @resetOutput()
        return

      # Deals with with identifying when a command is finished
      if extractLast(@output, 2) is "$ "
        exitResults = @parseExitCode(@output)
        if exitResults
          @ready = true
          if exitResults.exitCode isnt 130 # 130 - CTRL-C kill
            @emit('data', exitResults.exitCode, @output.substring(0, exitResults.index))
          @resetOutput()
          @emit('ready')
          console.log("[ssh-module] Instance emitted ready!")
    ).stderr.on('data', (data) ->
      console.log('STDERR: ' + data)
    ).on('error', (err) =>
      console.log("[instance] Error received")
      console.log(err)
      @destroy()
    )

  spawn: (command, args, options) ->
    # TODO: Should we ignore commands that are input when the network isn't ready?
    console.log("[instance] received spawn request: init: #{@initialized} | ready: #{@ready}")
    if not @initialized or not @ready
      @command = (() => @spawn(command, args, options))
      return
    @ready = false
    commandString = ''
    if options?.pwd
      commandString += "cd #{options.pwd}; "
    commandString += command + " " + args.join(' ')
    console.log("[instance] running #{commandString};")
    @instance.write("#{commandString}; echo cilkide exit code: $?\n")

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
      console.log("[instance] no cilkide exit code found")
      return false
    else
      console.log("[instance] found exit code #{parseInt(results[1])}")
      return {exitCode: parseInt(results[1]), index: results.index}

  destroy: () ->
    @instance = null
    @initialized = false
    @ready = false
    @output = null
    @emit('destroyed')

module.exports = SSHModule
