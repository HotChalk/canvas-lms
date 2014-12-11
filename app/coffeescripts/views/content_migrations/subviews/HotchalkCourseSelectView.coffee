define [
  'jquery'
  'Backbone'
  'underscore'
  'jst/content_migrations/subviews/HotchalkCourseSelect'
  'jquery.ajaxJSON'
  'jquery.disableWhileLoading'
], ($, Backbone, _, template) -> 
  class HotchalkCourseSelectView extends Backbone.View
    template: template

    els: 
      '#courseSearchField'   : '$courseSearchField'
      '#courseSelect'        : '$courseSelect'

    events: 
      'change #courseSelect' : 'updateSearch'

    @optionProperty 'rootAccountId'

    render: ->
      super
      dfd = @getAvailableCourses()
      @$el.disableWhileLoading dfd
      dfd.done (data) =>
        @courses = data
        super

    afterRender: ->
      @$courseSearchField.autocomplete 
        source: @availableCourseUrl()
        select: @updateSelect

    toJSON: -> 
      json = super
      json.packages = @courses
      json

    # Grab a list of courses from the server via the availableCourseUrl. Disable
    # this view and re-render.
    # @api private

    getAvailableCourses: ->
      dfd = $.ajaxJSON @availableCourseUrl(), 'GET', {}, {}, {}, {}
      @$el.disableWhileLoading dfd
      dfd

    # Generate a url that is used to find available course packages

    availableCourseUrl: ->
      "/hotchalk/packages/" + @rootAccountId

    # Build a list of courses that our template and autocomplete can use
    # objects look like
    #   {label: 'Plant Science', value: 'Plant Science', id: 42}
    # @api private

    autocompleteCourses: ->
      _.map @courses, (course) -> 
        {label: course.name, id: course.id, value: course.name}

    # After finding a course by searching via autocomplete, update the 
    # select menu to keep both input fields in sync. Also sets the 
    # source course id
    # @input (jqueryEvent, uiObj)
    # @api private

    updateSelect: (event, ui) => 
      @setSourceCourseId ui.item.id
      @$courseSelect.val ui.item.id

    # After selecting a course via the dropdown menu, update the search
    # field to keep the inputs in sync. Also set the source course id
    # @input jqueryEvent
    # @api private

    updateSearch: (event) => 
      value = parseInt(event.target.value, 10)
      @setSourceCourseId value

      courses = @autocompleteCourses()
      courseObj = _.find courses, (course) => course.id == value
      @$courseSearchField.val courseObj?.value

    # Given an id, set the source_course_id on the backbone model.
    # @input int
    # @api private

    setSourceCourseId: (id) ->
      @model.set('settings', {source_course_id: id})
      if course = _.find(@courses, (c) -> c.id == id)
        @trigger 'course_changed', course

    # Validates this form element. This validates method is a convention used 
    # for all sub views.
    # ie:
    #   error_object = {fieldName:[{type:'required', message: 'This is wrong'}]}
    # -----------------------------------------------------------------------
    # @expects void
    # @returns void | object (error)
    # @api private

    validations: -> 
      errors = {}
      settings = @model.get('settings')

      unless settings?.source_course_id
        errors.courseSearchField = [
          type: "required"
          message: "You must select a package to copy content from"
        ]

      errors
