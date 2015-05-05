define [
  'ember'
  'ic-tabs'
], (Ember) ->

  ScreenreaderGradebookView = Ember.View.extend

    didInsertElement: ->
      #horrible hack to get disabled instead of disabled="disabled" on buttons
      this.$('button:disabled').prop('disabled', true)
      return

    updateSection: (->
      self = this
      if self.get('controller.uniqueSection') != null
        self.$('.section_select').val(self.get('controller.uniqueSection')).attr 'disabled', 'disabled'
      return
    ).observes('controller.uniqueSection')
