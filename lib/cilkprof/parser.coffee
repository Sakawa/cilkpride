CSVParser = require('../utils/csv-reader')

module.exports =
class CilkprofParser

  workRegex = /work ([0-9]*\.[0-9]*) Gcycles, span ([0-9]*\.[0-9]*) Gcycles, parallelism ([0-9]*\.[0-9]*)/

  # This is the main function in the parser for cilkscreen results.
  # External classes should only call this function, and not any others.
  # TODO: filter out the stuff we aren't using
  @parseResults: (cilkprofOutput) ->
    # Cut out the first line (which is the command)
    cilkprofOutput = cilkprofOutput.split('\n')
    workSpan = cilkprofOutput[1]
    info = workSpan.match(workRegex)
    cilkprofOutput.splice(0,2)
    cilkprofOutput = cilkprofOutput.join('\n')
    console.log(info)
    return {
      work: Math.round(parseFloat(info[1]) * 1000000000),
      span: Math.round(parseFloat(info[2]) * 1000000000),
      parallelism: parseFloat(info[3]),
      csv: CSVParser.parseCSV(cilkprofOutput, true)
    }
