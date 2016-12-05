extend = require('util')._extend;
process = require('process')
spawn = require('child_process').spawn
Debug = require('./utils/debug')

module.exports =
class Runner

  instance: null
  getInstance: null
  callback: null
  refreshConfFile: null

  thread: null
  threadOutput: null

  constructor: (props) ->
    @getInstance = props.getInstance
    @getSettings = props.getSettings
    @refreshConfFile = props.refreshConfFile

  getNewInstance: (readyCallback) ->
    @getInstance((instance) =>
      @instance = instance
      Debug.log("[runner] Got a new instance.")
      instance.once('destroyed', (() => @getNewInstance(readyCallback)))
      instance.once('initialized', () ->
        readyCallback()
      )
      instance.on('data', (errCode, output) =>
        @callback(errCode, output)
      )
    )

  # TODO: better way of handling options
  spawn: (command, args, options, callback) ->
    @kill()
    settings = @getSettings()
    @callback = callback
    if settings.hostname
      if @instance
        @instance.spawn(command, args, {pwd: settings.remoteBaseDir})
      else
        return false
    else
      try
        process.chdir(settings.localBaseDir)
        Debug.log("[runner] Successfully changed pwd to: #{settings.localBaseDir}")
      catch error
        Debug.err("[runner] Could not change pwd to #{settings.localBaseDir} with error #{error}")
      cilkLibPath = atom.config.get('cilkpride.cilkLibPath')
      cilktoolsPath = atom.config.get('cilkpride.cilktoolsPath')
      Debug.log("[runner] Process environment: ")
      Debug.log(process.env)
      envCopy = extend({'LD_LIBRARY_PATH': cilkLibPath, 'LIBRARY_PATH': cilkLibPath}, process.env)
      envCopy.PATH = envCopy.PATH + ":" + cilktoolsPath

      thread = spawn(command, args, {env: envCopy})
      @thread = thread
      @threadOutput = ''

      thread.on('data', (data) =>
        @threadOutput += data
      ).on('close', (code) =>
        Debug.log("[runner] output (code #{code}): #{@threadOutput}")
        if code isnt 130
          @callback(code, @threadOutput)
      ).on('error', (err) ->
        Debug.log("[runner] nodejs child process error: #{err}")
      ).on('exit', (code, signal) =>
        if code?
          Debug.log("[runner] child process exit: code #{code}")
        if signal?
          Debug.log("[runner] child process exit: signal #{signal}")
      )

  kill: () ->
    if @instance
      Debug.log("[runner] Killed instance...?")
      return @instance.kill()
    if @thread
      @thread.kill('SIGINT')
      Debug.log("[runner] Killed thread...?")
      Debug.log(@thread)
      @thread = null
      return true
    return false

  destroy: () ->
    @instance.destroy() if @instance
    @thread.kill('SIGINT') if @thread
