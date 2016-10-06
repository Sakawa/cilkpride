extend = require('util')._extend;
process = require('process')
spawn = require('child_process').spawn

module.exports =
class Runner

  instance: null
  settings: null
  getInstance: null
  callback: null
  refreshConfFile: null

  thread: null
  threadOutput: null

  constructor: (props) ->
    @getInstance = props.getInstance
    @settings = props.settings
    @refreshConfFile = props.refreshConfFile

  getNewInstance: (readyCallback) ->
    @getInstance((instance) =>
      @instance = instance
      console.log("[runner] Got a new instance.")
      instance.once('destroyed', (() => @getNewInstance()))
      instance.once('initialized', () ->
        readyCallback()
      )
      instance.on('data', (errCode, output) =>
        @callback(errCode, output)
      )
    )

  updateConfFile: () ->
    @settings = @refreshConfFile()

  # TODO: better way of handling options
  spawn: (command, args, options, callback) ->
    @kill()
    @updateConfFile()
    @callback = callback
    if @settings.hostname
      if @instance
        @instance.spawn(command, args, {pwd: @settings.remoteBaseDir})
      else
        return false
    else
      try
        process.chdir(@settings.localBaseDir)
        console.log("[runner] Successfully changed pwd to: #{@settings.localBaseDir}")
      catch error
        console.err("[runner] Could not change pwd to #{@settings.localBaseDir} with error #{error}")
      cilkLibPath = atom.config.get('cilkpride.cilkLibPath')
      cilktoolsPath = atom.config.get('cilkpride.cilktoolsPath')
      console.log("[runner] Process environment: ")
      console.log(process.env)
      envCopy = extend({'LD_LIBRARY_PATH': cilkLibPath, 'LIBRARY_PATH': cilkLibPath}, process.env)
      envCopy.PATH = envCopy.PATH + ":" + cilktoolsPath

      thread = spawn(command, args, {env: envCopy})
      @thread = thread
      @threadOutput = ''

      thread.on('data', (data) =>
        @threadOutput += data
      ).on('close', (code) =>
        console.log("[runner] output (code #{code}): #{@threadOutput}")
        if code isnt 130
          @callback(code, @threadOutput)
      ).on('error', (err) ->
        console.log("[runner] nodejs child process error: #{err}")
      ).on('exit', (code, signal) =>
        if code?
          console.log("[runner] child process exit: code #{code}")
        if signal?
          console.log("[runner] child process exit: signal #{signal}")
      )

  kill: () ->
    if @instance
      console.log("[runner] Killed instance...?")
      return @instance.kill()
    if @thread
      @thread.kill('SIGINT')
      console.log("[runner] Killed thread...?")
      console.log(@thread)
      @thread = null
      return true
    return false

  destroy: () ->
    @instance.destroy() if @instance
    @thread.kill('SIGINT') if @thread
