# {CompositeDisposable} = require 'atom'
# {$, View} = require 'atom-space-pen-views'
# {addLeftTile} = require 'status-bar'
#
# PlatformIOTerminalView = require './view'
# StatusIcon = require './status-icon'
#
# os = require 'os'
# path = require 'path'
# _ = require 'underscore'
#
# module.exports =
# class StatusBar extends View
#
#   @content: ->
#     @div class: 'python-debugger-view status-bar', tabindex: 0, =>
#       @i class: "icon icon-bug", click: 'toggle', outlet: 'plusBtnSayn'
#
#   initialize: ->
#     @subscriptions = new CompositeDisposable()
#     @subscriptions.add atom.commands.add 'atom-workspace',
#       'python-debugger:toggle': => @toggle()
#     @subscriptions.add atom.tooltips.add @plusBtnSayn, title: 'SAYN Debug'
#     addLeftTile(item: 'plusBtnSayn', priority: 0)
#
#   toggle: ->
#     @toggle()
