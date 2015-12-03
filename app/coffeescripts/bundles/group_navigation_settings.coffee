require [
  'jquery'
  'underscore'
  'Backbone'
  'compiled/views/group_settings/NavigationView'
  'group_settings'
  'vendor/jquery.cookie'
], ($, _, Backbone, NavigationView) ->
  
  nav_view = new NavigationView
    el: $('#tab-navigation')

  $ ->
    nav_view.render()

