###
This class handles the execution of command line tools. There are two cases
that this class handles: SSH and Local. For SSH, Runner receives an "instance"
(see SSHModule) that represents a remote shell, which it uses to run the tools
and parse the output. For Local, Runner uses NodeJS APIs to execute the tools.
###

exec = require('child_process').exec
process = require('process')

Debug = require('./utils/debug')
PathUtils = require('./utils/path')

module.exports =
class Runner

  instance: null            # For SSH-enabled projects, an Object representing a remote shell
  getInstance: null         # Function that fetches an Instance object from SSHModule
  callback: null            # Callback for when a command line tool finishes running
  refreshConfFile: null     # Function that fetches an updated copy of the project config
  moduleName: null          # Name of the module that this Runner is attached to
                            # Used to access the appropriate make directory ('.cilksan', '.cilkprof')

  thread: null              # For SSH-disabled projects, the thread running the command line tool locally

  constructor: (props) ->
    @getInstance = props.getInstance
    @getSettings = props.getSettings
    @refreshConfFile = props.refreshConfFile
    @moduleName = props.moduleName

  getNewInstance: (readyCallback) ->
    @getInstance((instance) =>
      @instance = instance
      Debug.log("[runner] Got a new instance.")
      instance.once('destroyed', (() => @getNewInstance(readyCallback)))
      instance.once('initialized', () ->
        readyCallback()
      )
      instance.on('data', (errCode, output) =>
        # chop off the first line, which is the command
        outputLines = output.split('\n')
        outputLines.splice(0, 1)
        output = outputLines.join('\n')
        @callback(errCode, output)
      )
    )

  # TODO: better way of handling options
  spawn: (command, args, options, callback) ->
    @kill()
    settings = @getSettings()
    @callback = callback
    command = "mkdir -p .#{@moduleName} && cp -r * .#{@moduleName} && cd .#{@moduleName} && make clean && #{command}"
    # If we're using SSH for this project, we spawn an instance of a shell.
    if settings.sshEnabled
      if @instance
        @instance.spawn(command, args, {pwd: settings.remoteBaseDir})
      else
        return false
    # Otherwise we're going to run everything locally, which means we need to
    # make sure that the shell we're spawning has the appropriate locations of all libs and bins.
    else
      try
        process.chdir(settings.localBaseDir)
        Debug.log("[runner] Successfully changed pwd to: #{settings.localBaseDir}")
      catch error
        Debug.err("[runner] Could not change pwd to #{settings.localBaseDir} with error #{error}")
      # Grab the specified directories from the configuration file
      extraPathDirectories = atom.config.get('cilkpride.tapirSettings.extraPathDirectories')
      extraLibraryPathDirectories = atom.config.get('cilkpride.tapirSettings.extraLibraryPathDirectories')
      extraLDLibraryPathDirectories = atom.config.get('cilkpride.tapirSettings.extraLDLibraryPathDirectories')
      gccDirectory = atom.config.get('cilkpride.tapirSettings.gccLocation')
      # Add GCC-related directories
      extraPathDirectories += ":#{gccDirectory}/bin"
      extraLibraryPathDirectories += ":#{gccDirectory}/lib:#{gccDirectory}/lib64"
      extraLDLibraryPathDirectories += ":#{gccDirectory}/lib:#{gccDirectory}/lib64"
      Debug.log("[runner] Process environment: ")
      Debug.log(process.env)
      envCopy = Object.assign({}, process.env)
      PathUtils.combine(envCopy, 'PATH', extraPathDirectories)
      PathUtils.combine(envCopy, 'LD_LIBRARY_PATH', extraLDLibraryPathDirectories)
      PathUtils.combine(envCopy, 'LIBRARY_PATH', extraLibraryPathDirectories)
      PathUtils.combine(envCopy, 'CXX': "#{gccDirectory}/bin/g++")
      PathUtils.combine(envCopy, 'CC': "#{gccDirectory}/bin/gcc")
      Debug.info("[runner] envCopy")
      Debug.info(envCopy)

      thread = exec(command, {cwd: settings.localBaseDir, env: envCopy}, (error, stdout, stderr) =>
        if error
          Debug.log("[runner] exec (#{command}) finished with error #{error.code}")
          Debug.info("[runner] #{stdout}")
          Debug.info("[runner] #{stderr}")
          @callback(error.code, stdout + stderr)
        else
          Debug.info("[runner] exec (#{command}) finished with error code 0")
          Debug.info("[runner] #{stdout}")
          Debug.info("[runner] #{stderr}")
          @callback(0, stdout + stderr)
      )
      @thread = thread

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
