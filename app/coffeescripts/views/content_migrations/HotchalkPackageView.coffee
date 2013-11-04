define [
  'Backbone'
  'underscore'
  'jst/content_migrations/HotchalkPackage'
  'compiled/views/content_migrations/MigrationView'
],(Backbone, _, template, MigrationView) ->
  class HotchalkPackageView extends MigrationView
    template: template

    @child 'hotchalkCourseSelect', '.hotchalkCourseSelect'
