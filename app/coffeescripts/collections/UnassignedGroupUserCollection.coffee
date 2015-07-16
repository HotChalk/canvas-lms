define [
  'compiled/collections/GroupUserCollection'
  'compiled/models/GroupUser'
], (GroupUserCollection, GroupUser) ->

  class UnassignedGroupUserCollection extends GroupUserCollection

    @optionProperty 'section_id'

    url: ->
      _url = "/api/v1/group_categories/#{@category.id}/users?per_page=50&include[]=sections&exclude[]=pseudonym"
      _url += "&unassigned=true" unless @category.get('allows_multiple_memberships')
      @url = _url

    initialize: (models) ->
      super
      @url()

    load: (target = 'all') ->
      if @section_id
        @loadAll = target is 'all'
        @loaded = true
        options = {section_id : @section_id, force_search : true}
        @search('', options)
        @load = ->
      else
        super

    # don't add/remove people in the "Everyone" collection (this collection)
    # if the category supports multiple memberships
    membershipsLocked: ->
      @category.get('allows_multiple_memberships')

    increment: (amount) ->
      @category.increment 'unassigned_users_count', amount

    search: (filter, options) ->
      options = options || {}
      options.reset = true

      if options.force_search || ( filter && filter.length >= 3 )
        options.url = @url + "&search_term=" + filter
        if options.section_id
          options.url = options.url + "&section_id=" + options.section_id
        @filtered = true
        return @fetch(options)
      else if @filtered
        @filtered = false
        options.url = @url
        if options.section_id
          options.url = options.url + "&section_id=" + options.section_id
        return @fetch(options)

      # do nothing
