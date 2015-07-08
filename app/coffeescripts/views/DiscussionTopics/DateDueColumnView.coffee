define [
  'i18n!discussions'
  'Backbone'
  'jst/DiscussionTopics/DateDueColumnView'
  'jquery'
  'compiled/behaviors/tooltip'
], (I18n, Backbone, template, $) ->

  class DateDueColumnView extends Backbone.View
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
      data = assignment.toView()
      data.selector  = assignment.get("id") + "_due"
      data.linkHref  = assignment.htmlUrl()
      data.allDates  = assignment.allDates()
      data
