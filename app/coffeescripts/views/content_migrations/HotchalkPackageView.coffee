define [
  'Backbone'
  'jst/content_migrations/HotchalkPackage'
  'compiled/views/content_migrations/MigrationView'
], (Backbone, template, MigrationView) ->
  class HotchalkPackageView extends MigrationView
    template: template

    @child 'hotchalkCourseSelect', '.hotchalkCourseSelect'
