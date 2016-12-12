###
Handles SSH file syncing, with the help of an SFTP object from the
SSHModule file. Does not serve any purpose if the user is running
everything locally.
###

fs = require('fs')
path = require('path').posix

Debug = require('./utils/debug')

module.exports =
class FileSync

  sftp: null         # an SFTP object (see ssh-module.coffee)
  getSettings: null  # function that gets updated Cilkpride config settings
  getSFTP: null      # function that gets a new SFTP object

  # Constructs a new FileSync object.
  constructor: (props) ->
    @getSFTP = props.getSFTP

  # Gets a new SFTP object, and then calls callback.
  updateSFTP: (callback) ->
    @getSFTP((sftp) =>
      previousSFTP = @sftp

      @sftp = sftp.sftp
      @getSettings = sftp.getSettings
      Debug.log("[file-sync] Got a new SFTP.")

      callback() if callback
    )

  # Folder syncing

  copyFolder: (folder, localToRemote) ->
    if not @sftp
      return false

    settings = @getSettings()
    source = @sftp
    dest = fs
    sourceBaseDir = path.join(settings.remoteBaseDir, folder)
    messageStr = "Synced #{sourceBaseDir} to #{path.join(settings.localBaseDir, folder)}."

    if localToRemote
      source = fs
      dest = @sftp
      sourceBaseDir = path.join(settings.localBaseDir, folder)
      messageStr = "Synced #{sourceBaseDir} to #{path.join(settings.remoteBaseDir, folder)}."

    # Verify that the directory we're trying to copy from actually exists.
    (new Promise((resolve, reject) ->
      source.stat(sourceBaseDir, (err, stats) ->
        Debug.log(err) if err
        Debug.log(stats) if stats
        unless stats?.isDirectory()
          atom.notifications.addError("Error: Source directory #{sourceBaseDir} doesn't exist.")
          reject()
        else
          resolve()
      )
    )).then(() =>
      @copyFolderRecur(folder, localToRemote, source, dest, sourceBaseDir, settings)
      atom.notifications.addSuccess(messageStr)
    )

  copyFolderRecur: (folder, localToRemote, source, dest, sourceBaseDir, settings) ->
    # Check if we should ignore this directory.
    if folder[0] = '/'
      folderAlternative = folder.substring(1)
    else
      folderAlternative = "/#{folder}"
    if folder in settings.syncIgnoreDir or folderAlternative in settings.syncIgnoreDir
      Debug.log("[file-sync] Ignore dir #{folder} encountered.")
      return

    destPath = path.join(settings.localBaseDir, folder)
    if localToRemote
      destPath = path.join(settings.remoteBaseDir, folder)

    # Check if the destination folder we're trying to copy to exists.
    # If it doesn't, create it (and any parent folders, too).
    (new Promise((resolve, reject) =>
      @createDestFolderIfNecessary(destPath, dest, settings, resolve, reject)
    )).then(() =>
      source.readdir(path.join(sourceBaseDir, folder), (err, files) =>
        for file in files
          if localToRemote
            newPath = path.join(folder, file)
          else
            newPath = path.join(folder, file.filename)
          fullPath = path.join(sourceBaseDir, newPath)
          Debug.log("[file-sync] STAT :: statting #{fullPath}")
          do (newPath) =>
            source.stat(fullPath, (err, stats) =>
              throw "Something went wrong when trying to get information on #{fullPath}." if err
              if stats.isFile()
                @copyFileInternal(newPath, localToRemote, settings)
              else if stats.isDirectory()
                @copyFolderRecur(newPath, localToRemote, source, dest, sourceBaseDir, settings)
              else
                Debug.log("[file-sync] SFTP :: unknown filetype #{newPath} encountered")
            )
      )
    )

  copyFile: (file, localToRemote, settings, callback) ->
    if not @sftp
      return false

    # Check if we should ignore this file.
    if file[0] isnt '/'
      fileAlternative = "/#{file}"
    else
      fileAlternative = file.substring(1)
    if file in settings.syncIgnoreFile or fileAlternative in settings.syncIgnoreFile
      Debug.log("[file-sync] SFTP :: ignored file #{file}")
      callback() if callback
      return

    Debug.log("[file-sync STFP] :: received request for #{file} : #{localToRemote} local -> remote")
    if localToRemote
      (new Promise((resolve, reject) =>
        @createDestFolderIfNecessary(path.dirname(path.join(settings.remoteBaseDir, file)), @sftp, settings, resolve, reject)
      )).then(() =>
        @copyFileInternal(file, localToRemote, settings, callback)
      )
    else
      (new Promise((resolve, reject) =>
        @createDestFolderIfNecessary(path.dirname(path.join(settings.localBaseDir, file)), fs, settings, resolve, reject)
      )).then(() =>
        @copyFileInternal(file, localToRemote, settings, callback)
      )

  copyFileInternal: (file, localToRemote, settings, callback) ->
    if not @sftp
      return false

    # Check if we should ignore this file.
    if file[0] isnt '/'
      fileAlternative = "/#{file}"
    else
      fileAlternative = file.substring(1)
    if file in settings.syncIgnoreFile or fileAlternative in settings.syncIgnoreFile
      Debug.log("[file-sync] SFTP :: ignored file #{file}")
      callback() if callback
      return

    Debug.log("[file-sync STFP] :: received request for #{file} : #{localToRemote} local -> remote")
    if localToRemote
      @sftp.fastPut(path.join(settings.localBaseDir, file), path.join(settings.remoteBaseDir, file), (err) ->
        throw "Something went wrong when trying to copy #{file} to the remote server." if err
        Debug.log("[file-sync] SFTP :: fastPut LTR #{file} succeeded")
        callback() if callback
      )
    else
      @sftp.fastGet(path.join(settings.remoteBaseDir, file), path.join(settings.localBaseDir, file), (err) ->
        throw "Something went wrong when trying to copy #{file} from the remote server." if err
        Debug.log("[file-sync] SFTP :: fastPut RTL #{file} succeeded")
        callback() if callback
      )

  unlink: (file, settings, callback) ->
    @sftp.unlink(path.join(settings.remoteBaseDir, file), (err) ->
      if err
        Debug.log("[file-sync] Failed to remove #{file}")
      else
        Debug.log("[file-sync] SFTP :: unlink #{file} succeeded")
      callback() if callback
    )

  rmdir: (folder, settings, callback) ->
    @sftp.rmdir(path.join(settings.remoteBaseDir, folder), (err) ->
      if err
        Debug.log(err)
        Debug.log("[file-sync] Failed to remove folder #{folder}")
      else
        Debug.log("[file-sync] SFTP:: rmdir #{folder} succeeded")
      callback() if callback
    )

  createDestFolderIfNecessary: (destPath, dest, settings, resolve, reject) ->
    Debug.log("[file-sync] Checking folder #{destPath}")

    # TODO: Is there a better way of doing this?
    (new Promise((resolve, reject) =>
      parentDirectory = path.join(destPath, '..')
      dest.stat(parentDirectory, (err, stats) =>
        if err
          @createDestFolderIfNecessary(parentDirectory, dest, settings, resolve, reject)
        else if not stats.isDirectory()
          throw "#{destPath} exists but is not a directory - please verify that the paths are correct in your config file."
        else
          Debug.log("[file-sync] SFTP :: verified #{destPath} folder exists")
          resolve()
      )
    )).then(() =>
      dest.stat(destPath, (err, stats) =>
        Debug.log("[file-sync] SFTP :: stat on #{destPath}")
        Debug.log(stats)
        if err
          Debug.log(err)
          dest.mkdir(destPath, (err) =>
            Debug.log(["file-sync] SFTP :: dest folder creation"])
            Debug.log(err)
            resolve()
          )
        else if not stats.isDirectory()
          throw "#{destPath} exists but is not a directory - please verify that the paths are correct in your config file."
        else
          Debug.log("[file-sync] SFTP :: verified #{destPath} folder exists")
          resolve()
      )
    )

  destroy: () ->
    @sftp.end() if @sftp
