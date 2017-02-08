###
Parser that uses regex to process the Cilkprof output. Gets the total
work, span, and parallelism and runs the CSV parser.
###

CSVParser = require('../utils/csv-reader')
Debug = require('../utils/debug')

# These should be synced with those in main.coffee. These are used to identify
# exactly where the Cilkprof CSV starts and ends, so we can look for these tags
# to figure out where we should start parsing.
CILKPROF_START = "cilkpride:cilkprof_start"
CILKPROF_END = "cilkpride:cilkprof_end"

module.exports =
class CilkprofParser

  # Should be updated if the Cilkprof expected output ever changes.
  workRegex = /work ([0-9]*\.[0-9]*) Gcycles, span ([0-9]*\.[0-9]*) Gcycles, parallelism ([0-9]*\.[0-9]*)/

  # This is the main function in the parser for Cilkprof results.
  # External classes should only call this function, and not any others.
  @parseResults: (cilkprofOutput) ->
    Debug.info("[cilkprof-parser] parsing...")
    Debug.log(cilkprofOutput)
    cilkprofArray = cilkprofOutput.split('\n')
    info = cilkprofOutput.match(workRegex)
    if not info or cilkprofOutput.indexOf(CILKPROF_START) is -1 or cilkprofOutput.indexOf(CILKPROF_END) is -1
      return null

    cilkprofOutput = cilkprofOutput.substring(cilkprofOutput.indexOf(CILKPROF_START) + CILKPROF_START.length, cilkprofOutput.indexOf(CILKPROF_END))
    Debug.log(info)
    return {
      work: Math.round(parseFloat(info[1]) * 1000000000),
      span: Math.round(parseFloat(info[2]) * 1000000000),
      parallelism: parseFloat(info[3]),
      csv: CSVParser.parseCSV(cilkprofOutput, true)
    }
