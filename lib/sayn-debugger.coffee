{CompositeDisposable} = require "atom"
path = require "path"
Breakpoint = require "./breakpoint"
BreakpointStore = require "./breakpoint-store"

module.exports = SaynDebugger =
  pythonDebuggerView: null
  subscriptions: null

  config:
    pythonEnv:
      title: "Path to Python environment to use while debugging."
      type: "string"
      default: "$VIRTUAL_ENV"
    requirementsFile:
      title: "Path to pip requirements file for dependency management"
      type: "string"
      default: "requirements.txt"
    focusOnCmd:
      title: "Focus editor on current line change"
      type: "boolean"
      default: false

  createDebuggerView: (backendDebugger) ->
    unless @saynDebuggerView?
      SaynDebuggerView = require "./sayn-debugger-view"
      @saynDebuggerView = new SaynDebuggerView(@breakpointStore)
    @saynDebuggerView

  activate: ({attached}={}) ->

    @subscriptions = new CompositeDisposable
    @breakpointStore = new BreakpointStore()
    @createDebuggerView().toggle() if attached

    @subscriptions.add atom.commands.add "atom-workspace",
      "sayn-debugger:toggle": => @createDebuggerView().toggle()
      "sayn-debugger:breakpoint": => @saynDebuggerView?.toggleBreakpoint()
      "sayn-debugger:clear-all-breakpoints": => @saynDebuggerView?.clearBreakpoints()

  deactivate: ->
    @backendDebuggerInputView.destroy()
    @subscriptions.dispose()
    @saynDebuggerView.destroy()

  serialize: ->
    saynDebuggerViewState: @saynDebuggerView?.serialize()

    activePath = editor?.getPath()
    relative = atom.project.relativizePath(activePath)
    themPaths = relative[0] || (path.dirname(activePath) if activePath?)
