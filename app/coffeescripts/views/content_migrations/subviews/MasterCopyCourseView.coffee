define [
  'Backbone'
  'underscore'
  'jst/content_migrations/CopyCourse'
  'compiled/views/content_migrations/MigrationView'
],(Backbone, _, template, MigrationView) -> 
  class MasterCopyCourseView extends MigrationView
    template: template

    @child 'courseFindSelect', '.courseFindSelect'

    initialize: ->
      super
      @courseFindSelect.on 'course_changed', (course) =>
        @dateShift.updateNewDates(course)
