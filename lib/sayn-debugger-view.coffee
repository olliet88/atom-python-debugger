{Point, Disposable, CompositeDisposable, BufferedProcess} = require "atom"
{$, $$, View, TextEditorView} = require "atom-space-pen-views"
Breakpoint = require "./breakpoint"
BreakpointStore = require "./breakpoint-store"

spawn = require("child_process").spawn
path = require "path"
fs = require "fs"

module.exports =
class SaynDebuggerView extends View
  debuggedFileName: null
  debuggedFileArgs: []
  backendDebuggerPath: null
  backendDebuggerName: "atom_pdb.py"
  saynDebugMode: false
  autoUpdatePipDependencies: false
  pipProcess = null

  getCurrentFilePath: ->
    return "" unless editor = atom.workspace.getActivePaneItem()
    return "" unless buffer = editor.buffer
    return buffer.file?.path

  getDebuggerPath: ->
    pkgs = atom.packages.getPackageDirPaths()[0]
    console.log(pkgs)
    debuggerPath = path.join(pkgs, "sayn-debugger", "resources")
    return debuggerPath

  @content: ->
    @div class: "saynDebuggerView", =>
      @div outlet: 'toolbar', class: 'btn-toolbar-top', =>
        @div class: 'btn-group right', =>
          @button outlet: 'closeBtn', class: 'btn icon icon-x', click: 'destroy'
        @div class: 'btn-group left', =>
          @button outlet: "runBtn", click: "runSayn", class: "btn", =>
            @span "Run"
          @button outlet: "compileBtn", click: "compileSayn", class: "btn", =>
            @span "Compile"
          @button outlet: "stopBtn", click: "stopApp", class: "btn", =>
            @span "Stop"


      @div class: 'debug-inputs', =>
        @subview "tasksEntryView", new TextEditorView
          mini: true,
          placeholderText: "Optional: Enter Tasks Here"


      @div class: "toggles", =>
        @div class: 'btn-toolbar-bottom', =>
          @div class: 'btn-group left', =>
            @button click: "toggleSaynDebugMode", class: "btn", =>
              @span "Toggle Debug Mode"
            @button click: "togglePipAutoInstall", class: "btn", =>
              @span "Toggle Auto Pip"


      @div class: "panel-body", outlet: "outputContainer", =>
        @pre class: "command-output", outlet: "output"

      @div class: 'debug-inputs', =>
        @div class: 'btn-toolbar-bottom', =>
          @div class: 'btn-group left', =>
            @button outlet: "breakpointBtn", click: "toggleBreakpoint", class: "btn", =>
              @span "Add Breakpoint"
            @button outlet: "stepOverBtn", click: "stepOverBtnPressed", class: "btn", =>
              @span "Next"
            @button outlet: "stepInBtn", click: "stepInBtnPressed", class: "btn", =>
              @span "Step"
            @button outlet: "varBtn", click: "varBtnPressed", class: "btn", =>
              @span "Variables"
            @button outlet: "returnBtn", click: "returnBtnPressed", class: "btn", =>
              @span "Return"
            @button outlet: "continueBtn", click: "continueBtnPressed", class: "btn", =>
              @span "Continue"
            @button outlet: "clearBtn", click: "clearOutput", class: "btn", =>
              @span "Clear"
        @subview "commandEntryView", new TextEditorView
          mini: true,
          placeholderText: "Debugger Commands"

  toggleBreakpoint: ->
    editor = atom.workspace.getActiveTextEditor()
    filename = @getCurrentFilePath()
    lineNumber = editor.getCursorBufferPosition().row + 1
    # add to or remove breakpoint from internal list
    cmd = @breakpointStore.toggle(new Breakpoint(filename, lineNumber))
    debuggerCmd = cmd + "\n"
    @backendDebugger.stdin.write(debuggerCmd) if @backendDebugger
    @output.append(debuggerCmd)

  toggleSaynDebugMode: ->
    @saynDebugMode = !@saynDebugMode
    if @saynDebugMode
      @addOutput("Sayn Debug Mode Enabled.")
    else
      @addOutput("Sayn Debug Mode Disabled.")

  togglePipAutoInstall: ->
    @autoUpdatePipDependencies = !@autoUpdatePipDependencies
    if @autoUpdatePipDependencies
      @addOutput("Pip Dependencies AutoUpdate Enabled.")
    else
      @addOutput("Pip Dependencies AutoUpdate Disabled.")

  stepOverBtnPressed: ->
    @backendDebugger?.stdin.write("n\n")

  stepInBtnPressed: ->
    @backendDebugger?.stdin.write("s\n")

  continueBtnPressed: ->
    @backendDebugger?.stdin.write("c\n")

  returnBtnPressed: ->
    @backendDebugger?.stdin.write("r\n")

  loopOverBreakpoints: () ->
    n = @breakpointStore.breakpoints.length
    for i in [0..n-1]
      # always yield first element; it will be spliced out
      yield @breakpointStore.breakpoints[0]

  clearBreakpoints: () ->
    return unless @breakpointStore.breakpoints.length > 0
    # The naive `@toggle breakpoint for breakpoint in @breakpoints`
    # gives indexing errors because of the async loop.
    # Clear breakpoints sequentially.

    # for ... from will be supported in a future version of Atom
    # for breakpoint from @loopOverBreakpoints()
    #   cmd = @toggle breakpoint
    #   debuggerCmd = cmd + "\n"
    #   @backendDebugger.stdin.write(debuggerCmd) if @backendDebugger
    #   @output.append(debuggerCmd)
    `
    for (let breakpoint of this.loopOverBreakpoints()) {
      cmd = this.breakpointStore.toggle(breakpoint)
      debuggerCmd = cmd + "\n"
     if (this.backendDebugger) {
        this.backendDebugger.stdin.write(debuggerCmd)
        this.output.append(debuggerCmd)
      }
    }
    `
    return

  workspacePath: ->
    editor = atom.workspace.getActiveTextEditor()
    activePath = editor.getPath()
    relative = atom.project.relativizePath(activePath)
    pathToWorkspace = relative[0] || (path.dirname(activePath) if activePath?)
    pathToWorkspace

  pythonEnvPath: ->
    # If there's a .venv_path file, use it.
    venvFilePath = path.join(@workspacePath(), ".venv")
    if fs.existsSync(venvFilePath)
      venv_path = fs.readFileSync(venvFilePath, 'utf8').trim()
      return venv_path
    else
      return atom.config.get "sayn-debugger.pythonEnv"

  runSayn: ->
    @stopApp() if @backendDebugger
    @debuggedFileArgs = @getInputArguments()
    console.log @debuggedFileArgs
    if @autoUpdatePipDependencies
      @runDebuggerWithPip("run")
    else
      @runBackendDebugger("run")

  compileSayn: ->
    @stopApp() if @backendDebugger
    @debuggedFileArgs = @getInputArguments()
    console.log @debuggedFileArgs
    if @autoUpdatePipDependencies
      @runDebuggerWithPip("compile")
    else
      @runBackendDebugger("compile")

  varBtnPressed: ->
    @backendDebugger?.stdin.write("for (__k, __v) in [(__k, __v) for __k, __v in globals().items() if not __k.startswith('__')]: print __k, '=', __v\n")
    @backendDebugger?.stdin.write("print '-------------'\n")
    @backendDebugger?.stdin.write("for (__k, __v) in [(__k, __v) for __k, __v in locals().items() if __k != 'self' and not __k.startswith('__')]: print __k, '=', __v\n")
    @backendDebugger?.stdin.write("for (__k, __v) in [(__k, __v) for __k, __v in (self.__dict__ if 'self' in locals().keys() else {}).items()]: print 'self.{0}'.format(__k), '=', __v\n")

  # Extract the file name and line number output by the debugger.
  processDebuggerOutput: (data) ->
    data_str = data.toString().trim()
    lineNumber = null
    fileName = null

    [data_str, tail] = data_str.split("line:: ")
    if tail
      [lineNumber, tail] = tail.split("\n")
      data_str = data_str + tail if tail

    [data_str, tail] = data_str.split("file:: ")
    if tail
      [fileName, tail] = tail.split("\n")
      data_str = data_str + tail if tail
      fileName = fileName.trim() if fileName
      fileName = null if fileName == "<string>"

    @highlightLineInEditor fileName, lineNumber
    @addOutput(data_str.trim())

  highlightLineInEditor: (fileName, lineNumber) ->
    return unless fileName && lineNumber
    lineNumber = parseInt(lineNumber)
    focusOnCmd = atom.config.get "sayn-debugger.focusOnCmd"
    options = {
      searchAllPanes: true,
      activateItem: true,
      activatePane: focusOnCmd,
    }
    atom.workspace.open(fileName, options).then (editor) ->
      position = Point(lineNumber - 1, 0)
      editor.setCursorBufferPosition(position)
      editor.unfoldBufferRow(lineNumber)
      editor.scrollToBufferPosition(position)
      # TODO: add decoration to current line?

  runDebuggerWithPip: (command) ->
    console.log("Running pip first...")
    pythonEnv = @pythonEnvPath()
    pip = path.join(pythonEnv, "bin/pip3")
    console.log(pip)
    requirementsFile = atom.config.get "sayn-debugger.requirementsFile"
    args = ['install', '-r', requirementsFile]
    options = {
      cwd: @workspacePath()
    }
    @pipProcess = spawn(pip, args, options=options)

    @pipProcess.stdout.on "data", (data) =>
      @addOutput(data)
    @pipProcess.stderr.on "data", (data) =>
      @addOutput(data)
    @pipProcess.on "exit", (code) =>
      @checkPipExitStatusAndRunDebugger(code, command)

  checkPipExitStatusAndRunDebugger: (code, command) ->
    if code != 0
      @addOutput("Pip: Exit Code " + code + ". Not Debugging.")
    else
      @runBackendDebugger(command)

  runBackendDebugger: (command) ->
    args = [path.join(@backendDebuggerPath, @backendDebuggerName)]
    pythonEnv = @pythonEnvPath()
    # console.log("sayn-debugger: using python " + pythonEnv)
    python = path.join(pythonEnv, "bin/python3")
    sayn = path.join(pythonEnv, "bin/sayn")
    args.push(sayn)
    args.push(command)
    for task in @debuggedFileArgs
      args.push("-t")
      args.push(task)
    if @saynDebugMode
      args.push("-d")
    console.log("sayn-debugger: using python installation at ", python)
    options = {
      cwd: @workspacePath()
    }
    @backendDebugger = spawn(python, args, options=options)

    for breakpoint in @breakpointStore.breakpoints
      @backendDebugger.stdin.write(breakpoint.addCommand() + "\n")

    # Move to first breakpoint or run program if there are none.
    @backendDebugger.stdin.write("c\n")

    @backendDebugger.stdout.on "data", (data) =>
      @processDebuggerOutput(data)
    @backendDebugger.stderr.on "data", (data) =>
      @processDebuggerOutput(data)
    @backendDebugger.on "exit", (code) =>
      @addOutput("debugger exits with code: " + code.toString().trim()) if code?

  stopApp: ->
    console.log "backendDebugger is ", @backendDebugger
    @backendDebugger?.stdin.write("\nexit()\n")
    @backendDebugger = null
    @debuggedFileName = null
    @debuggedFileArgs = []
    console.log "debugger stopped"

  clearOutput: ->
    @output.empty()

  createOutputNode: (text) ->
    node = $("<span />").text(text)
    parent = $("<span />").append(node)

  addOutput: (data) ->
    atBottom = @atBottomOfOutput()
    node = @createOutputNode(data)
    @output.append(node)
    @output.append("\n")
    if atBottom
      @scrollToBottomOfOutput()

  noArgs: ->
    args = @tasksEntryView.getModel().getText()
    return @stringIsBlank(args)

  initialize: (breakpointStore) ->
    @subscriptions = new CompositeDisposable
    @breakpointStore = breakpointStore
    @debuggedFileName = @getCurrentFilePath()
    @backendDebuggerPath = @getDebuggerPath()
    @addOutput("Welcome to SAYN Debugger for Atom!")

    @subscriptions.add atom.tooltips.add @closeBtn,
      title: 'Close'
    @subscriptions.add atom.commands.add @element,
      "core:confirm": (event) =>
        if @parseAndSetPaths()
          @clearInputText()
        else
          @confirmBackendDebuggerCommand()
        event.stopPropagation()
      "core:cancel": (event) =>
        @cancelBackendDebuggerCommand()
        event.stopPropagation()

  parseAndSetPaths:() ->
    command = @getCommand()
    return false if !command
    if /e=(.*)/.test command
      match = /e=(.*)/.exec command
      # TODO: check that file exists
      if fs.existsSync match[1]
        @debuggedFileName = match[1]
        return true
      else
        @addOutput("File #{match[1]} does not appear to exist")
    return false

  stringIsBlank: (str) ->
    !str or /^\s*$/.test str

  escapeString: (str) ->
    !str or str.replace(/[\\"']/g, '\\$&').replace(/\u0000/g, '\\0')

  getInputArguments: ->
    args = @tasksEntryView.getModel().getText()
    return if !@stringIsBlank(args) then args.split(" ") else []

  getCommand: ->
    command = @commandEntryView.getModel().getText()
    command if !@stringIsBlank(command)

  cancelBackendDebuggerCommand: ->
    @commandEntryView.getModel().setText("")

  confirmBackendDebuggerCommand: ->
    if !@backendDebugger
      @addOutput("Program not running")
      return
    command = @getCommand()
    if command
      @backendDebugger.stdin.write(command + "\n")
      @clearInputText()

  clearInputText: ->
    @commandEntryView.getModel().setText("")

  serialize: ->
    attached: @panel?.isVisible()

  destroy: ->
    @detach()

  toggle: ->
    if @panel?.isVisible()
      @detach()
    else
      @attach()

  atBottomOfOutput: ->
    @output[0].scrollHeight <= @output.scrollTop() + @output.outerHeight()

  scrollToBottomOfOutput: ->
    @output.scrollToBottom()

  attach: ->
    console.log "attached"
    @panel = atom.workspace.addBottomPanel(item: this)
    @panel.show()
    @scrollToBottomOfOutput()

  detach: ->
    console.log "detached"
    @panel.destroy()
    @panel = null
