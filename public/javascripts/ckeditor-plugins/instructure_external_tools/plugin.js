(function() {
  var TRANSLATIONS = {
    embed_from_external_tool: "Embed content from External Tool",
    more_external_tools: "More External Tools"
  };
  CKEDITOR.plugins.add('instructure_external_tools', {
    init: function(api, url) {
      if(!window || !window.INST || !window.INST.editorButtons || !window.INST.editorButtons.length) {
        return;
      }
      var $dialog = null;
      function buttonSelected(button) {
        var frameHeight = Math.max(Math.min($(window).height() - 100, 550), 100);
        if(!$dialog) {
          $dialog = $('<div id="external_tool_button_dialog" style="padding: 0; overflow-y: hidden;"/>')
            .hide()
            .html("<div class='teaser' style='width: 800px; margin-bottom: 10px; display: none;'></div>" +
                  "<iframe id='external_tool_button_frame' style='width: 800px; height: " + frameHeight +"px; border: 0;' src='/images/ajax-loader-medium-444.gif' borderstyle='0' tabindex='0'/>")
            .appendTo('body')
            .dialog({
              autoOpen: false,
              width: 'auto',
              resizable: true,
              close: function() {
                $dialog.find("iframe").attr('src', '/images/ajax-loader-medium-444.gif');
              },
              title: TRANSLATIONS.embed_from_external_tool
            })
            .bind('dialogresize', function() {
              $(this).find('iframe').add('.fix_for_resizing_over_iframe').height($(this).height()).width($(this).width());
            })
            .bind('dialogresizestop', function() {
              $(".fix_for_resizing_over_iframe").remove();
            })
            .bind('dialogresizestart', function() {
              $(this).find('iframe').each(function(){
                $('<div class="fix_for_resizing_over_iframe" style="background: #fff;"></div>')
                  .css({
                    width: this.offsetWidth+"px", height: this.offsetHeight+"px",
                    position: "absolute", opacity: "0.001", zIndex: 10000000
                  })
                  .css($(this).offset())
                  .appendTo("body");
              });
            })
        }
        $(window).unbind("externalContentReady");
        $(window).bind("externalContentReady", function (event, data) {
          var item = data.contentItems[0];
          var placementAdvice = item.placementAdvice;
          var presentationDocTarget = placementAdvice.presentationDocumentTarget;
          var url = item.mediaType === 'application/vnd.ims.lti.v1.launch+json' ? item.canvasURL : item.url
          if (presentationDocTarget === 'iframe') {
            var html = $("<div/>").append($("<iframe/>", {
              src: url,
              title: item.title,
              allowfullscreen: 'true',
              webkitallowfullscreen: 'true',
              mozallowfullscreen: 'true'
            }).css({
              width: placementAdvice.displayWidth,
              height: placementAdvice.displayHeight
            })).html();
            $("#" + api.element.getId()).editorBox('insert_code', html);
          } else if (presentationDocTarget === 'embed') {
            if (item.mediaType && item.mediaType.indexOf('image') == 0) {
              var html = $("<div/>").append($("<img/>", {
                src: url,
                alt: item.text
              }).css({
                width: placementAdvice.displayWidth,
                height: placementAdvice.displayHeight
              })).html();
              $("#" + api.element.getId()).editorBox('insert_code', html);
            } else {
              $("#" + api.element.getId()).editorBox('insert_code', item.text);
            }
          } else { //create a link to the content
            $("#" + api.element.getId()).editorBox('create_link', {
              url: url,
              title: item.title,
              text: item.text,
              target: placementAdvice.presentationDocumentTarget == 'window' ? '_blank' : null
            });
          }
          $dialog.find('iframe').attr('src', 'about:blank');
          $dialog.dialog('close')
        });
        $dialog.dialog('option', 'title', 'Embed content from ' + button.name);
        $dialog.dialog('close')
          .dialog('option', 'width', button.width || 800)
          .dialog('option', 'height', button.height || frameHeight || 400)
          .dialog('open');
        $dialog.triggerHandler('dialogresize')
        $dialog.data('editor', api);
        var url = $.replaceTags($("#context_external_tool_resource_selection_url").attr('href'), 'id', button.id);
        if (url === null || typeof url === 'undefined') {
          // if we don't have a url on the page, build one using the current context.
          // url should look like: /courses/2/external_tools/15/resoruce_selection?editor=1
          var asset = ENV.context_asset_string.split('_');
          url = '/' + asset[0] + 's/' + asset[1] + '/external_tools/' + button.id + '/resource_selection?editor=1';
        }
        var selection = api.getSelection().getSelectedText() || "";
        url += (url.indexOf('?') > -1 ? '&' : '?') + "selection=" + encodeURIComponent(selection)
        $dialog.find("iframe").attr('src', url);
      }
      for(var idx in INST.editorButtons) {
        var current_button = INST.editorButtons[idx];
        (function(button) {
          api.addCommand('instructureExternalButton' + button.id, {
            exec: function() {
              buttonSelected(button);
            }
          });
          api.ui.addButton('instructure_external_button_' + button.id, {
            label: button.name,
            command: 'instructureExternalButton' + button.id,
            className: 'instructure_external_tool_button'
          });
          CKEDITOR.skin.addIcon('instructure_external_button_' + button.id, button.icon_url);
        })(current_button);
      }
    }
  });
})();

