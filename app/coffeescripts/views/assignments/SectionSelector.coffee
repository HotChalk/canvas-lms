define [
  'Backbone'
  'underscore'
  'jquery'
  'jst/assignments/SectionSelector'
], (Backbone, _, $, template) ->

  class SectionSelector extends Backbone.View

    template: template

    @optionProperty 'parentModel'
    @optionProperty 'sections'
    @optionProperty 'showSectionDropdown'
    @optionProperty 'sectionListIsEmpty'

    initialize: (options) ->
      super