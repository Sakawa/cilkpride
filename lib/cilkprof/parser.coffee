CSVParser = require('../utils/csv-reader')

module.exports =
class CilkprofParser

  # This is the main function in the parser for cilkscreen results.
  # External classes should only call this function, and not any others.
  # TODO: filter out the stuff we aren't using
  @parseResults: (cilkprofOutput) ->
    # Cut out the first line (which is the command)
    cilkprofOutput = cilkprofOutput.split('\n')
    cilkprofOutput.splice(0,1)
    cilkprofOutput = cilkprofOutput.join('\n')
    return CSVParser.parseCSV(cilkprofOutput, true)
