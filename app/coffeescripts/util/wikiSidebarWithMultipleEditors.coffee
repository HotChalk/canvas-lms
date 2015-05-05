define [
  'jquery'
  'wikiSidebar'
  'ckeditor.editor_box'
  'ckeditor-all'
], ($, wikiSidebar) ->

  $.subscribe 'editorBox/focus', ($editor) ->
    wikiSidebar.init() unless wikiSidebar.inited
    wikiSidebar.show()
    wikiSidebar.attachToEditor($editor)

  $.subscribe 'editorBox/removeAll', ->
    wikiSidebar.hide()