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
      @sections ?= ENV.USER_SECTION_LIST
      @showSectionDropdown = @sections.length > 1
      @sectionListIsEmpty = @sections.length < 1
      @courseSectionId = @parentModel.courseSectionId

    toJSON: =>
      sections: @sections
      showSectionDropdown: @showSectionDropdown
      sectionListIsEmpty: @sectionListIsEmpty
      courseSectionId: @courseSectionId
