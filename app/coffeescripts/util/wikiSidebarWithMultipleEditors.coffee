define [
  'jquery'
  'wikiSidebar'
  'redactor.editor_box'
], ($, wikiSidebar) ->

  $.subscribe 'editorBox/focus', ($editor) ->
    wikiSidebar.init() unless wikiSidebar.inited
    wikiSidebar.show()
    wikiSidebar.attachToEditor($editor)

  $.subscribe 'editorBox/removeAll', ->
    wikiSidebar.hide()