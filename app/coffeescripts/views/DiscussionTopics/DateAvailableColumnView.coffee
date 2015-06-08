define [
  'i18n!discussions'
  'Backbone'
  'jst/DiscussionTopics/DateAvailableColumnView'
  'jquery'
  'underscore'
  'compiled/behaviors/tooltip'
], (I18n, Backbone, template, $, _) ->

  class DateAvailableColumnView extends Backbone.View
    template: template

    els:
      '.vdd_tooltip_link': '$link'

    afterRender: ->
      @$link.tooltip
        position: {my: 'center bottom', at: 'center top-10', collision: 'fit fit'},
        tooltipClass: 'center bottom vertical',
        content: -> $($(@).data('tooltipSelector')).html()

    toJSON: ->
      assignment = @model.get('assignment')
      group = assignment.defaultDates()

      data = assignment.toView()
      data.defaultDates = group.toJSON()
      data.selector     = assignment.get("id") + "_lock"
      data.linkHref     = assignment.htmlUrl()
      data.allDates     = assignment.allDates()
      data
