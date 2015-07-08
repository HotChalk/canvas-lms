define [
  'underscore'
  'i18n!discussions'
  'jquery'
  'compiled/views/DialogFormView'
  'jst/EmptyDialogFormWrapper'
  'compiled/models/DiscussionsSettings'
  'compiled/models/UserSettings'
  'jst/DiscussionTopics/DiscussionsSettingsView'
], (_, I18n, $, DialogFormView, wrapperTemplate, DiscussionsSettings, UserSettings, template) ->

  class DiscussionsSettingsView extends DialogFormView

    defaults:
      title: I18n.t "edit_settings", "Edit Discussions Settings"
      fixDialogButtons: false

    events: _.extend {},
      DialogFormView::events
      'click .dialog_closer': 'close'

    template: template
    wrapperTemplate: wrapperTemplate

    initialize: ->
      super
      @model      or= new DiscussionsSettings
      @userSettings = new UserSettings

    openAgain: () ->
      super
      @fetch()

    render: () ->
      super(arguments)
      @$el
        .find('#manual_mark_as_read')
        .prop('checked', @userSettings.get('manual_mark_as_read'))

    submit: (event) ->
      super(event)
      @userSettings.set('manual_mark_as_read', @$el.find('#manual_mark_as_read').prop('checked'))
      @userSettings.save()

    fetch: ->
      isComplete = $.Deferred()
      $.when(@model.fetch(), @userSettings.fetch()).then =>
        isComplete.resolve()
        @render()
      @$el.disableWhileLoading(isComplete)

