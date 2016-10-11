fs = require('fs')
path = require('path').posix

module.exports =
class FileSync

  sftp: null
  getSettings: null

  constructor: (props) ->
    @getSFTP = props.getSFTP

  updateSFTP: () ->
    @getSFTP((sftp) =>
      @sftp = sftp.sftp
      @getSettings = sftp.getSettings
      console.log("[file-sync] Got a new SFTP.")
    )

  # Folder syncing

  copyFolder: (folder, localToRemote) ->
    if not @sftp
      return false

    source = @sftp
    dest = fs
    settings = @getSettings()
    sourceBaseDir = path.join(settings.remoteBaseDir, folder)
    messageStr = "Synced #{sourceBaseDir} to #{path.join(settings.localBaseDir, folder)}."

    if localToRemote
      source = fs
      dest = @sftp
      sourceBaseDir = path.join(settings.localBaseDir, folder)
      messageStr = "Synced #{sourceBaseDir} to #{path.join(settings.remoteBaseDir, folder)}."

    (new Promise((resolve, reject) ->
      source.stat(sourceBaseDir, (err, stats) ->
        console.log(err) if err
        console.log(stats) if stats
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
    if folder in settings.syncIgnoreDir
      console.log("[file-sync] Ignore dir #{folder} encountered.")
      return

    destPath = path.join(settings.localBaseDir, folder)
    if localToRemote
      destPath = path.join(settings.remoteBaseDir, folder)

    (new Promise((resolve, reject) =>
      @createDestFolderIfNecessary(destPath, dest, settings, resolve, reject)
    )).then(() =>
      source.readdir(path.join(sourceBaseDir, folder), (err, files) =>
        for file in files
          newPath = null
          if localToRemote
            newPath = path.join(folder, file)
          else
            newPath = path.join(folder, file.filename)
          fullPath = path.join(sourceBaseDir, newPath)
          console.log("[file-sync] STAT :: statting #{fullPath}")
          do (newPath) =>
            source.stat(fullPath, (err, stats) =>
              throw "Something went wrong when trying to get information on #{fullPath}." if err
              if stats.isFile()
                @copyFile(newPath, localToRemote, settings)
              else if stats.isDirectory()
                @copyFolderRecur(newPath, localToRemote, source, dest, sourceBaseDir, settings)
              else
                console.log("[file-sync] SFTP :: unknown filetype #{newPath} encountered")
            )
      )
    )

  copyFile: (file, localToRemote, settings, callback) ->
    if not @sftp or file in settings.syncIgnoreFile
      return false
    console.log("[file-sync STFP] :: received request for #{file} : #{localToRemote} local -> remote")
    if localToRemote
      @sftp.fastPut(path.join(settings.localBaseDir, file), path.join(settings.remoteBaseDir, file), (err) ->
        throw "Something went wrong when trying to copy #{file} to the remote server." if err
        console.log("[file-sync] SFTP :: fastPut LTR #{file} succeeded")
        callback() if callback
      )
    else
      @sftp.fastGet(path.join(settings.remoteBaseDir, file), path.join(settings.localBaseDir, file), (err) ->
        throw "Something went wrong when trying to copy #{file} from the remote server." if err
        console.log("[file-sync] SFTP :: fastPut RTL #{file} succeeded")
        callback() if callback
      )

  createDestFolderIfNecessary: (destPath, dest, settings, resolve, reject) ->
    console.log("[file-sync] Checking folder #{destPath}")

    # TODO: Is there a better way of doing this?
    (new Promise((resolve, reject) =>
      dest.stat(path.join(destPath, '..'), (err, stats) =>
        if err
          @createDestFolderIfNecessary(path.join(destPath, '..'), dest, settings, resolve, reject)
        else if not stats.isDirectory()
          throw "#{destPath} exists but is not a directory - please verify that the paths are correct in your config file."
        else
          console.log("[file-sync] SFTP :: verified #{destPath} folder exists")
          resolve()
      )
    )).then(() =>
      dest.stat(destPath, (err, stats) =>
        console.log("[file-sync] SFTP :: stat on #{destPath}")
        console.log(stats)
        if err
          dest.mkdir(destPath, (err) =>
            throw "Something went wrong when trying to create the directory #{destPath}." if err
            console.log("[file-sync] SFTP :: created dest folder #{destPath}")
            resolve()
          )
        else if not stats.isDirectory()
          throw "#{destPath} exists but is not a directory - please verify that the paths are correct in your config file."
        else
          console.log("[file-sync] SFTP :: verified #{destPath} folder exists")
          resolve()
      )
    )

  destroy: () ->
    @sftp.end() if @sftp
