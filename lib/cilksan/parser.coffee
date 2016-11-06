path = require('path').posix

CustomSet = require('../utils/set')
FileLineReader = require('../utils/file-reader')

module.exports =
class CilksanParser

  # This is the main function in the parser for cilksan results.
  # External classes should only call this function, and not any others.
  @processViolations: (text, callback, remoteDir, localDir) ->
    violations = CilksanParser.parseCilksanOutput(text, remoteDir, localDir)
    CilksanParser.getViolationLineCode(violations, callback)

  # Cilksan-related functions
  # TODO: could replace this with smart regex
  @parseCilksanOutput: (text, remoteDir, localDir) ->
    console.log("[cilksan-parser] remote dir: #{remoteDir} | local dir: #{localDir}")
    text = text.split('\n')
    violations = []
    currentViolation = null

    # Run through it line by line to figure out what the race conditions are
    for line in text
      if line.indexOf("Race detected at address ") isnt -1
        # We have found the first line in a violation
        currentViolation = {stacktrace: {}, memoryLocation: line}
        currentStacktrace = []
        continue

      if currentViolation isnt null
        if line.indexOf("access at") isnt -1
          splitLine = line.trim().split(' ')
          accessType = splitLine[0]
          # console.log(splitLine)
          sourceCodeLine = splitLine[4].slice(1, -1)
          # console.log(sourceCodeLine)
          # There will be 5 elements if the line has a source code annotation.
          if splitLine.length is 5
            # console.log(sourceCodeLine)
            splitIndex = sourceCodeLine.lastIndexOf(':')
            sourceCodeFile = sourceCodeLine.substr(0, splitIndex)
            sourceCodeLine = +sourceCodeLine.substr(splitIndex + 1)
            # Sometimes there's no information given from cilksan, specified by (??:0)
            if sourceCodeFile is '??'
              sourceCodeFile = null
            else if remoteDir and localDir
              relativePath = path.relative(remoteDir, sourceCodeFile)
              sourceCodeFile = path.join(localDir, relativePath)
            if sourceCodeLine is 0
              sourceCodeLine = null

          lineData = {
            accessType: accessType,
            filename: sourceCodeFile,
            line: sourceCodeLine,
            rawText: line
          }

          console.log("[cilksan-parser] Line data")
          console.log(lineData)

          if currentViolation.line1
            currentViolation.line2 = lineData
            lineId = lineData.filename + ":" + lineData.line
            currentViolation.stacktrace[lineId] = []
          else
            currentViolation.line1 = lineData
            lineId = lineData.filename + ":" + lineData.line
            currentViolation.stacktrace[lineId] = []
        # else if line.indexOf("called by") isnt -1
        #   # console.log(currentViolation)
        #   currentStacktrace.push(line)
        else
          lineId = currentViolation.line2.filename + ":" + currentViolation.line2.line
          currentViolation.stacktrace[lineId].push(currentStacktrace)
          violations.push(currentViolation)
          currentViolation = null

    mergeStacktraces = (entry, item) ->
      lineId = item.line2.filename + ":" + item.line2.line
      entry.stacktrace[lineId].push(item.stacktrace[lineId][0])

    # TODO: yes, fill this out
    isEqual = (obj1, obj2) ->
      isFileEqual = (file1, file2) ->
        return file1.filename is file2.filename and file1.line is file2.line

      return (isFileEqual(obj1.line1, obj2.line1) and isFileEqual(obj1.line2, obj2.line2)) or
        (isFileEqual(obj1.line2, obj2.line1) and isFileEqual(obj1.line1, obj2.line2))

    violationSet = new CustomSet(isEqual)
    violationSet.add(violations, mergeStacktraces)
    violations = violationSet.getContents()

    console.log("[cilksan-parser] Pruned violations...")
    console.log(violations)
    return violations

  @getViolationLineCode: (violations, next) ->
    # This determines how many lines will be fetched for context.
    HALF_CONTEXT = 2

    readRequestArray = []
    violations.forEach((item) =>
      if item.line1.filename
        if item.line1.line
          readRequestArray.push([
            item.line1.filename,
            [item.line1.line - HALF_CONTEXT, item.line1.line + HALF_CONTEXT]
          ])
        else
          item.line1.text = "No source code available for this access."
          item.line1.lineRange = [0,0]
      if item.line2.filename
        if item.line2.line
          readRequestArray.push([
            item.line2.filename,
            [item.line2.line - HALF_CONTEXT, item.line2.line + HALF_CONTEXT]
          ])
        else
          item.line2.text = "No source code available for this access."
          item.line2.lineRange = [0,0]
    )

    FileLineReader.readLineNumBatch(readRequestArray, (texts) =>
      CilksanParser.groupCodeWithViolations(violations, texts)
      next(violations)
    )

  @groupCodeWithViolations: (violations, texts) ->
    for violation in violations
      codeSnippetsFound = 0
      # console.log(violation)
      for text in texts
        # console.log(text)
        if codeSnippetsFound is 2
          break
        if violation.line1.filename is text.filename and violation.line1.line - 2 is text.lineRange[0]
          violation.line1.text = text.text
          violation.line1.lineRange = text.lineRange
          codeSnippetsFound++
        if violation.line2.filename is text.filename and violation.line2.line - 2 is text.lineRange[0]
          violation.line2.text = text.text
          violation.line2.lineRange = text.lineRange
          codeSnippetsFound++
      if codeSnippetsFound < 2 and violation.line1.filename isnt null and violation.line2.filename isnt null
        console.log("[cilksan-parser] groupCodeWithViolations: too few snippets found for a violation")
    console.log("[cilksan-parser] Finished groupCodeWithViolations")
    console.log(violations)
