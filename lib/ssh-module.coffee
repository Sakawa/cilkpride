Client = require('ssh2').Client
EventEmitter = require('events')

{extractLast} = require('./utils/utils')
PasswordView = require('./password-view')

module.exports =
class SSHModule

  settings: null
  props: null

  connection: null
  eventEmitter: null

  password: null

  constructor: (props) ->
    console.log("[ssh-module] Created a new instance of SSHModule")
    @props = props
    @settings = props.settings
    @eventEmitter = new EventEmitter()

    @startConnection()

  startConnection: () ->
    conn = new Client()
    @connection = conn
    conn.on('ready', () =>
      console.log("[ssh-module] Connection ready.")
      @eventEmitter.emit('ready')
    ).on('close', (hadError) =>
      console.log("[ssh-module] SFTP :: closed")
      @clean(conn)
    ).on('continue', () ->
      console.log("[ssh-module] SFTP :: continue received")
    ).on('end', () =>
      console.log("[ssh-module] SFTP :: end signal received")
      @clean(conn)
    ).on('error', (error) =>
      console.log("[ssh-module] SFTP :: received error")
      console.log(error)
      @clean(conn)
      if error.level is 'client-authentication'
        @startConnection()
    ).on('keyboard-interactive', (name, instructions, instructionsLang, prompts, finish) =>
      console.log("[ssh-module] SFTP :: received keyboard interactive request")
      new PasswordView(
        "Please enter your password for #{@settings.username}@#{@settings.hostname}.\n
        Note: your password will be saved for this session in case of network issues."
        , (password) =>
          if @connection
            @password = password
            finish([password])
          else
            @startConnection()
        , () =>
          console.log("Cancel initiated.")
          conn.end()
          @clean(conn)
      )
    )
    conn.connect({
      host: @settings.hostname
      port: @settings.port
      username: @settings.username
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
    @connection.sftp((err, sftp) =>
      throw err if err
      console.log("[ssh-module] SFTP :: ready")
      callback(new SFTP(sftp, @settings))
    )

  getInstance: (callback) ->
    @connection.shell({pty: true}, (err, stream) =>
      throw err if err
      console.log("[ssh-module] Instance :: ready")
      callback(new Instance(stream, @password, @settings))
    )

class SFTP

  sftp: null
  settings: null

  constructor: (sftp, settings) ->
    @sftp = sftp
    @settings = settings

class Instance

  instance: null
  initialized: false
  passwordFlag: false
  ready: false
  eventEmitter: null

  output: null
  command: null

  constructor: (instance, password) ->
    console.log('[instance] Instance constructed')
    @instance = instance
    @instance.write('launch-instance\n')
    @output = ''
    @eventEmitter = new EventEmitter()
    @eventEmitter.on('ready', () =>
      console.log('[instance] Instance is ready!')
      if @command
        command = @command
        @command = null
        command()
    )
    @init(password)

  init: (password) ->
    @instance.on('close', () =>
      console.log('[instance] Connection closed')
      @destroy()
    ).on('end', () =>
      console.log('[instance] Connection ended')
      @destroy()
    ).on('data', (data) =>
      @output += data
      if not @passwordFlag and extractLast(@output, 10) is "Password: "
        @instance.write(password + '\n')
        @passwordFlag = true
        @resetOutput()

      if extractLast(@output, 14) is "@localhost:~$ "
        @ready = true
        @initialized = true
        @resetOutput()
        @eventEmitter.emit('ready')
        console.log("[ssh-module] Instance is ready!")
      console.log('STDOUT: ' + data)
    ).stderr.on('data', (data) ->
      console.log('STDERR: ' + data)
    )

  spawn: (command, args, options, callback) ->
    if not @initialized
      @command = (() => @spawn(command, args, options, callback))
      return
    if not @ready
      @command = (() => @spawn(command, args, options, callback))
      @kill()
      return
    @ready = false
    commandString = command + " " + args.join(' ')
    @instance.write(commandString + '\n')

  kill: () ->
    if @instance
      @instance.write('\u0003')

  resetOutput: () ->
    @output = ''

  destroy: () ->
    @instance = null
    @initialized = false
    @ready = false
    @output = null
