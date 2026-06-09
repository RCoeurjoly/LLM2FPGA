# Yosys

```text
Yosys Open SYnthesis Suite
Usage:
  /nix/store/4hp2jpjzz9vi4mw6b5v5dj0ys8g06z9b-yosys-0.62/bin/yosys [OPTION...] [<infile> [..]]

 operation options:
  -b, --backend <backend>       use <backend> for the output file specified on the command line
  -f, --frontend <frontend>     use <frontend> for the input files on the command line
  -s, --scriptfile <scriptfile>
                                execute the commands in <scriptfile>
  -c, --tcl-scriptfile <tcl_scriptfile>
                                execute the commands in the TCL <tcl_scriptfile> (see 'help tcl' for details)
  -C, --tcl-interactive         enters TCL interactive shell mode
  -y, --py-scriptfile <script>  execute the Python <script>
  -p, --commands <commands>     execute <commands> (to chain commands, separate them with semicolon + whitespace: 'cmd1; cmd2')
  -r, --top <top>               elaborate the specified HDL <top> module
  -m, --plugin <plugin>         load the specified <plugin> module
  -D, --define <define>[=<value>]
                                set the specified Verilog define to <value> if supplied via command "read -define"
  -S, --synth                   shortcut for calling the "synth" command, a default script for transforming the Verilog input to a gate-level netlist. For example: yosys -o output.blif -S input.v For more complex synthesis jobs it is recommended to use the read_* and write_* commands in a script file instead of specifying input and output files on the command line.
  -H                            print the command list
  -h, --help [<command>]        print this help message. If given, print help for <command>.
  -V, --version                 print version information and exit
      --git-hash                print git commit hash and exit

 logging options:
  -Q                            suppress printing of banner (copyright, disclaimer, version)
  -T                            suppress printing of footer (log hash, version, timing statistics)
      --no-version              suppress writing out Yosys version anywhere excluding -V, --version
  -q, --quiet                   quiet operation. Only write warnings and error messages to console. Use this option twice to also quiet warning messages
  -v, --verbose <level>         print log headers up to <level> to the console. Implies -q for everything except the 'End of script.' message.
  -t, --timestamp               annotate all log messages with a time stamp
  -d, --detailed-timing         print more detailed timing stats at exit
  -l, --logfile <logfile>       write log messages to <logfile>
  -L, --line-buffered-logfile <logfile>
                                like -l but open <logfile> in line buffered mode
  -o, --outfile <outfile>       write the design to <outfile> on exit
  -P, --dump-design <header_id>[:<filename>]
                                dump the design when printing the specified log header to a file. yosys_dump_<header_id>.il is used as filename if none is specified. Use 'ALL' as <header_id> to dump at every header.
  -W, --warning-as-warning <regex>
                                print a warning for all log messages matching <regex>
  -w, --warning-as-message <regex>
                                if a warning message matches <regex>, it is printed as regular message instead
  -e, --warning-as-error <regex>
                                if a warning message matches <regex>, it is printed as error message instead
  -E, --deps-file <depsfile>    write a Makefile dependencies file <depsfile> with input and output file names

 developer options:
  -X, --trace                   enable tracing of core data structure changes. for debugging
  -M, --randomize-pointers      will slightly randomize allocated pointer addresses. for debugging
      --autoidx <idx>           start counting autoidx up from <seed>, similar effect to --hash-seed
      --hash-seed <seed>        mix up hashing values with <seed>, for extreme optimization and testing
  -A, --abort                   will call abort() at the end of the script. for debugging
  -x, --experimental <feature>  do not print warnings for the experimental <feature>
  -g, --debug                   globally enable debug log messages
      --perffile <perffile>     write a JSON performance log to <perffile>

```

# nextpnr-xilinx

```text
"nextpnr-xilinx" -- Next Generation Place and Route (Version 72d8217)

General options:
  -h [ --help ]             show help
  -v [ --verbose ]          verbose output
  -q [ --quiet ]            quiet mode, only errors and warnings displayed
  -l [ --log ] arg          log file, all log messages are written to this file
                            regardless of -q
  --debug                   debug output
  -f [ --force ]            keep running after errors
  --run arg                 python file to execute instead of default flow
  --pre-pack arg            python file to run before packing
  --pre-place arg           python file to run before placement
  --pre-route arg           python file to run before routing
  --post-route arg          python file to run after routing
  --json arg                JSON design file to ingest
  --write arg               JSON design file to write
  --seed arg                seed value for random number generator
  -r [ --randomize-seed ]   randomize seed value for random number generator
  --placer arg              placer algorithm to use; available: sa, heap; 
                            default: heap
  --router arg              router algorithm to use; available: router1, 
                            router2; default: router2
  --slack_redist_iter arg   number of iterations between slack redistribution
  --cstrweight arg          placer weighting for relative constraint 
                            satisfaction
  --starttemp arg           placer SA start temperature
  --placer-budgets          use budget rather than criticality in placer timing
                            weights
  --pack-only               pack design only without placement or routing
  --no-route                process design without routing
  --no-place                process design without placement
  --no-pack                 process design without packing
  --ignore-loops            ignore combinational loops in timing analysis
  -V [ --version ]          show version
  --test                    check architecture database integrity
  --freq arg                set target frequency for design in MHz
  --timing-allow-fail       allow timing to fail in design
  --no-tmdriv               disable timing-driven placement
  --sdf arg                 SDF delay back-annotation file to write
  --sdf-cvc                 enable tweaks for SDF file compatibility with the 
                            CVC simulator

Architecture specific options:
  --chipdb arg              name of chip database binary
  --xdc arg                 XDC-style constraints file
  --fasm arg                fasm bitstream file to write

```

# fasm2frames

```text
usage: fasm2frames [-h] --db-root DB_ROOT --part PART [--sparse] [--roi ROI]
                   [--emit_pudc_b_pullup] [--debug]
                   fn_in [fn_out]

Convert FPGA configuration description ("FPGA assembly") into binary frame
equivalent

positional arguments:
  fn_in                 Input FPGA assembly (.fasm) file
  fn_out                Output FPGA frame (.frm) file

options:
  -h, --help            show this help message and exit
  --db-root DB_ROOT     Database root.
  --part PART           Part name. When not given defaults to XRAY_PART env.
                        var.
  --sparse              Don't zero fill all frames
  --roi ROI             ROI design.json file defining which tiles are within
                        the ROI.
  --emit_pudc_b_pullup  Emit an IBUF and PULLUP on the PUDC_B pin if unused
  --debug               Print debug dump
```

# xc7frames2bit

```text
xc7frames2bit: /nix/store/9img7k11vlgg1i0nl7lqqljjzvjvvgbp-prjxray-bdbc665852b82f589ff775a8f6498542dbec0a07/bin/xc7frames2bit

  Flags from /build/source/third_party/gflags/src/gflags.cc:
    -flagfile (load flags from file) type: string default: ""
    -fromenv (set flags from the environment [use 'export FLAGS_flag1=value'])
      type: string default: ""
    -tryfromenv (set flags from the environment if present) type: string
      default: ""
    -undefok (comma-separated list of flag names that it is okay to specify on
      the command line even if the program does not define a flag with that
      name.  IMPORTANT: flags in this list that have arguments MUST use the
      flag=value format) type: string default: ""

  Flags from /build/source/third_party/gflags/src/gflags_completions.cc:
    -tab_completion_columns (Number of columns to use in output for tab
      completion) type: int32 default: 80
    -tab_completion_word (If non-empty, HandleCommandLineCompletions() will
      hijack the process and attempt to do bash-style command line flag
      completion on this value.) type: string default: ""

  Flags from /build/source/third_party/gflags/src/gflags_reporting.cc:
    -help (show help on all flags [tip: all flags can have two dashes])
      type: bool default: false currently: true
    -helpfull (show help on all flags -- same as -help) type: bool
      default: false
    -helpmatch (show help on modules whose name contains the specified substr)
      type: string default: ""
    -helpon (show help on the modules named by this flag value) type: string
      default: ""
    -helppackage (show help on all modules in the main package) type: bool
      default: false
    -helpshort (show help on only the main module for this program) type: bool
      default: false
    -helpxml (produce an xml version of help) type: bool default: false
    -version (show version and build info and exit) type: bool default: false



  Flags from /build/source/tools/xc7frames2bit.cc:
    -architecture (Architecture of the provided bitstream) type: string
      default: "Series7"
    -frm_file (File containing a list of frame deltas to be applied to the base
      bitstream.  Each line in the file is of the form: <frame_address>
      <word1>,...,<word101>.) type: string default: ""
    -output_file (Write bitstream to file) type: string default: ""
    -part_file (Definition file for target 7-series part) type: string
      default: ""
    -part_name (Name of the 7-series part) type: string default: ""
```
