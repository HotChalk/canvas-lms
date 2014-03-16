// Redactor-jQuery EditorBox plugin
// Called on a jQuery selector (should be a single object only)
// to initialize a Redactor editor box in the place of the
// selected textarea: $("#edit").editorBox().  The textarea
// must have a unique id in order to function properly.
// editorBox():
// Initializes the object.  All other methods should
// only be called on an already-initialized box.
// editorBox('focus', [keepTrying])
//   Passes focus to the selected editor box.  Returns
//   true/false depending on whether the focus attempt was
//   successful.  If the editor box has not completely initialized
//   yet, then the focus will fail.  If keepTrying
//   is defined and true, the method will keep trying until
//   the focus attempt succeeds.
// editorBox('destroy')
//   Removes the Redactor instance from the textarea.
// editorBox('toggle')
//   Toggles the Redactor instance.  Switches back and forth between
//   the textarea and the Redactor WYSIWYG.
// editorBox('get_code')
//   Returns the plaintext code contained in the textarea or WYSIGWYG.
// editorBox('set_code', code)
//   Sets the plaintext code content for the editor box.  Replaces ALL
//   content with the string value of code.
// editorBox('insert_code', code)
//   Inserts the string value of code at the current selection point.
// editorBox('create_link', options)
//   Creates an anchor link at the current selection point.  If anything
//   is selected, makes the selection a link, otherwise creates a link.
//   options.url is used for the href of the link, and options.title
//   will be the body of the link if no text is currently selected.

define([
  'INST',
  'i18nObj',
  'jquery',
  'compiled/editor/editorAccessibility', /* editorAccessibility */
  'jqueryui/draggable' /* /\.draggable/ */,
  'jquery.instructure_misc_plugins' /* /\.indicate/ */,
  'vendor/jquery.scrollTo' /* /\.scrollTo/ */,
  'vendor/jquery.ba-tinypubsub',
  'vendor/scribd.view' /* scribd */,
  'compiled/bundles/redactor'
], function(INST, I18nObj, $) {

  var TRANSLATIONS = {
    embed_from_external_tool: I18nObj.t('embed_from_external_tool', '"Embed content from External Tool"'),
    more_external_tools: INST.htmlEscape(I18nObj.t('more_external_tools', "More External Tools"))
  };

  var enableBookmarking = $("body").hasClass('ie');
  $(document).ready(function() {
    enableBookmarking = $("body").hasClass('ie');
  });

  function EditorBoxList() {
    this._textareas = {};
    this._editor_boxes = {};
  }

  $.extend(EditorBoxList.prototype, {
    _addEditorBox: function(id, box) {
      $.publish('editorBox/add', id, box);
      var textArea = $("textarea#" + id);
      this._editor_boxes[id] = box;
      this._textareas[id] = textArea;
    },
    _removeEditorBox: function(id) {
      delete this._editor_boxes[id];
      delete this._textareas[id];
      $.publish('editorBox/remove', id);
      if ($.isEmptyObject(this._editor_boxes)) $.publish('editorBox/removeAll');
    },
    _getTextArea: function(id) {
      return this._textareas[id];
    },
    _getEditor: function(id) {
      var textArea = this._getTextArea(id);
      return textArea ? textArea.redactor('getObject') : null;
    },
    _getEditorBox: function(id) {
      return this._editor_boxes[id];
    }
  });

  var $instructureEditorBoxList = new EditorBoxList();

  var $dialog = null;

  var _externalToolCallback = function(toolId, toolTitle, toolWidth, toolHeight) {
    var frameHeight = Math.max(Math.min($(window).height() - 100, 550), 100);
    if(!$dialog) {
      $dialog = $('<div id="external_tool_button_dialog" style="padding: 0; overflow-y: hidden;"/>')
        .hide()
        .html("<div class='teaser' style='width: 800px; margin-bottom: 10px; display: none;'></div>" +
              "<iframe id='external_tool_button_frame' style='width: 800px; height: " + frameHeight +"px; border: 0;' src='/images/ajax-loader-medium-444.gif' borderstyle='0'/>")
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
        .bind('selection', function(event, data) {
          var editor = $dialog.data('editor') || $(this);
          if(data.return_type == 'lti_launch_url') {
            if($("#external_tool_retrieve_url").attr('href')) {
              var external_url = $.replaceTags($("#external_tool_retrieve_url").attr('href'), 'url', data.url);
              editor.editorBox('create_link', {
                url: external_url,
                title: data.title,
                text: data.text
              });
            } else {
              console.log("cannot embed basic lti links in this context");
            }
          } else if(data.return_type == 'image_url') {
            var html = $("<div/>").append($("<img/>", {
              src: data.url,
              alt: data.alt
            }).css({
              width: data.width,
              height: data.height
            })).html();
            editor.editorBox('insert_code', html);
          } else if(data.return_type == 'url') {
            editor.editorBox('create_link', {
              url: data.url,
              title: data.title,
              text: data.text,
              target: data.target == '_blank' ? '_blank' : null
            });
          } else if(data.return_type == 'file') {
            editor.editorBox('create_link', {
              url: data.url,
              title: data.filename,
              text: data.filename
            });
          } else if(data.return_type == 'iframe') {
            var html = $("<div/>").append($("<iframe/>", {
              src: data.url,
              title: data.title
            }).css({
              width: data.width,
              height: data.height
            })).html();
            editor.editorBox('insert_code', html);
          } else if(data.return_type == 'rich_content') {
            editor.editorBox('insert_code', data.html);
          } else if(data.return_type == 'error' && data.message) {
            alert(data.message);
          } else {
            console.log("unrecognized embed type: " + data.return_type);
          }
          $("#external_tool_button_dialog iframe").attr('src', 'about:blank');
          $("#external_tool_button_dialog").dialog('close');
        });
    }
    $dialog.dialog('option', 'title', 'Embed content from ' + toolTitle);
    $dialog.dialog('close')
      .dialog('option', 'width', toolWidth || 800)
      .dialog('option', 'height', toolHeight || frameHeight || 400)
      .dialog('open');
    $dialog.triggerHandler('dialogresize');
    $dialog.data('editor', this.$element);
    var url = $.replaceTags($("#context_external_tool_resource_selection_url").attr('href'), 'id', toolId);
    if (url === null || typeof url === 'undefined') {
      // if we don't have a url on the page, build one using the current context.
      // url should look like: /courses/2/external_tools/15/resoruce_selection?editor=1
      var asset = ENV.context_asset_string.split('_');
      url = '/' + asset[0] + 's/' + asset[1] + '/external_tools/' + toolId + '/resource_selection?editor=1'
    }
    $dialog.find("iframe").attr('src', url);
  };

  function EditorBox(id, search_url, submit_url, content_url, options) {
    options = $.extend({}, options);
    var $textarea = $("#" + id);
    $textarea.data('enable_bookmarking', enableBookmarking);
    this._id = id;
    this._searchURL = search_url;
    this._submitURL = submit_url;
    this._contentURL = content_url;

    // Add custom image button
    var pluginsList = ['image'];
    if (typeof RedactorPlugins === 'undefined') {
      RedactorPlugins = {};
      RedactorPlugins.image = {
        init: function() {
          this.buttonAddBefore('video', 'image', 'Insert Image', this.imageCallback);
        },
        imageCallback: function(buttonName, buttonDOM, buttonObj, e) {
          var editor = this;
          var selectedNode = this.getCurrent();
          require(['compiled/views/redactor/InsertUpdateImageView'], function(InsertUpdateImageView){
            new InsertUpdateImageView(editor, selectedNode);
          });
        }
      };
    }

    var redactorOptions = $.extend({
      autoresize: false,
      iframe: true,
      css: '/assets/redactor-iframe.css',
      buttons: ['html', '|', 'formatting', '|',
          'bold', 'italic', 'underline', 'deleted', '|',
          'alignleft', 'aligncenter', 'alignright', '|',
          'unorderedlist', 'orderedlist', 'outdent', 'indent', '|',
          'video', 'file', 'table', 'link', '|',
          'horizontalrule'],
      formattingTags: ['p', 'blockquote', 'pre', 'h2', 'h3', 'h4'],
      plugins: pluginsList,
      minHeight: 150
    }, options.redactorOptions || {});

    // Add custom editor buttons
    if (INST && INST.editorButtons) {
      redactorOptions.buttons.push('|');
      for (var btnIndex = 0; btnIndex < INST.editorButtons.length; btnIndex++) {
        var btn = INST.editorButtons[btnIndex];
        var btnId = 'extbtn' + btn.id;
        RedactorPlugins[btnId] = {
          init: function() {
            this.buttonAdd(btnId, btn.name, this.invoke);
          },
          invoke: function(buttonName, buttonDOM, buttonObject, e) {
            _externalToolCallback(btn.id, btn.name, btn.width, btn.height)
          }
        };
        pluginsList.push(btnId);
      }
    }

    $textarea.redactor(redactorOptions);
    $instructureEditorBoxList._addEditorBox(id, this);
    $textarea.bind('blur change', function() {
      if($instructureEditorBoxList._getEditor(id)) {
        $(this).editorBox('set_code', $instructureEditorBoxList._getTextArea(id).val());
      }
    });

    // Create CSS styling for custom buttons
    if (INST && INST.editorButtons && INST.editorButtons.length) {
      var cssContent = '';
      for (btnIndex = 0; btnIndex < INST.editorButtons.length; btnIndex++) {
        btn = INST.editorButtons[btnIndex];
        var className = '.redactor_toolbar li a.re-extbtn' + btn.id;
        cssContent += className + " {\
          background: url('" + btn.icon_url + "');\
          background-position: center;\
          background-repeat: no-repeat;\
        } " + className + ":hover {\
          outline: none;\
          background-color: #1f78d8;\
        }";
      }
      $("<style>").prop("type", "text/css").html(cssContent).appendTo("head");
    }
  }

  var fieldSelection = {

    getSelection: function() {

      var e = this.jquery ? this[0] : this;

      return (

        /* mozilla / dom 3.0 */
        ('selectionStart' in e && function() {
          var l = e.selectionEnd - e.selectionStart;
          return { start: e.selectionStart, end: e.selectionEnd, length: l, text: e.value.substr(e.selectionStart, l) };
        }) ||

        /* exploder */
        (document.selection && function() {

          e.focus();

          var r = document.selection.createRange();
          if (r == null) {
            return { start: 0, end: e.value.length, length: 0 };
          }

          var re = e.createTextRange();
          var rc = re.duplicate();
          re.moveToBookmark(r.getBookmark());
          rc.setEndPoint('EndToStart', re);

          return { start: rc.text.length, end: rc.text.length + r.text.length, length: r.text.length, text: r.text };
        }) ||

        /* browser not supported */
        function() {
          return { start: 0, end: e.value.length, length: 0 };
        }

      )();

    },

    replaceSelection: function() {

      var e = this.jquery ? this[0] : this;
      var text = arguments[0] || '';

      return (

        /* mozilla / dom 3.0 */
        ('selectionStart' in e && function() {
          e.value = e.value.substr(0, e.selectionStart) + text + e.value.substr(e.selectionEnd, e.value.length);
          return this;
        }) ||

        /* exploder */
        (document.selection && function() {
          e.focus();
          document.selection.createRange().text = text;
          return this;
        }) ||

        /* browser not supported */
        function() {
          e.value += text;
          return this;
        }

      )();

    }

  };

  $.extend($.fn, fieldSelection);

// --------------------------------------------------------------------

  var editorBoxIdCounter = 1;

  $.fn.editorBox = function(options, more_options) {
    var args = arguments;
    if(this.length > 1) {
      return this.each(function() {
        var $this = $(this);
        $this.editorBox.apply($this, args);
      });
    }

    var id = this.attr('id');
    if(typeof(options) == "string" && options != "create") {
      if(options == "get_code") {
        return this._getContentCode(more_options);
      } else if(options == "set_code") {
        this._setContentCode(more_options);
      } else if(options == "insert_code") {
        this._insertHTML(more_options);
      } else if(options == "selection_offset") {
        return this._getSelectionOffset();
      } else if(options == "selection_link") {
        return this._getSelectionLink();
      } else if(options == "create_link") {
        this._linkSelection(more_options);
      } else if(options == "focus") {
        return this._editorFocus(more_options);
      } else if(options == "toggle") {
        this._toggleView();
      } else if(options == "execute") {
        var arr = [];
        for(var idx = 1; idx < arguments.length; idx++) {
          arr.push(arguments[idx]);
        }
        return $.fn._execCommand.apply(this, arr);
      } else if(options == "destroy") {
        this._removeEditor(more_options);
      } else if(options == "is_dirty") {
        return $instructureEditorBoxList._getEditor(id).isDirty();
      }
      return this;
    }
    this.data('rich_text', true);
    if(!id) {
      id = 'editor_box_unique_id_' + editorBoxIdCounter++;
      this.attr('id', id);
    }
    if($instructureEditorBoxList._getEditor(id)) {
      this._setContentCode(this.val());
      return this;
    }
    var search_url = "";
    if(options && options.search_url) {
      search_url = options.search_url;
    }
    var box = new EditorBox(id, search_url, "", "", options);
    return this;
  };

  $.fn._execCommand = function() {
    var id = $(this).attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if(editor && editor.execCommand) {
      editor.execCommand.apply(editor, arguments);
    }
    return this;
  };

  $.fn._justGetCode = function() {
    var id = this.attr('id') || '';
    var content = '';
    try {
      if(!$instructureEditorBoxList._getEditor(id)) {
        content = $("textarea#" + id).val();
      } else {
        content = $instructureEditorBoxList._getEditor(id).get();
      }
    } catch(e) {
      content = this.val() || '';
    }
    return content;
  };

  $.fn._getContentCode = function(update) {
    if(update == true) {
      var content = this._justGetCode(); //""
      this._setContentCode(content);
    }
    return this._justGetCode();
  };

  $.fn._getSearchURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._searchURL;
  };

  $.fn._getSubmitURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._submitURL;
  };

  $.fn._getContentURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._contentURL;
  };

    // NEED TO TEST
  $.fn._getSelectionOffset = function() {
    var id = this.attr('id');
    var box = $instructureEditorBoxList._getEditor(id).$box;
    var boxOffset = $(box).find('iframe').offset();
    var node = $instructureEditorBoxList._getEditor(id).selection.getNode();
    var nodeOffset = $(node).offset();
    var scrollTop = $(box).scrollTop();
    var offset = {
      left: boxOffset.left + nodeOffset.left + 10,
      top: boxOffset.top + nodeOffset.top + 10 - scrollTop
    };
    return offset;
  };

    // NEED TO TEST
  $.fn._getSelectionNode = function() {
    var id = this.attr('id');
    var node = $instructureEditorBoxList._getEditor(id).getNodes();
    return node;
  };

    // NEED TO TEST
  $.fn._getSelectionLink = function() {
    var id = this.attr('id');
    var node = $instructureEditorBoxList._getEditor(id).getNodes();
    while(node.nodeName != 'A' && node.nodeName != 'BODY' && node.parentNode) {
      node = node.parentNode;
    }
    if(node.nodeName == 'A') {
      var href = $(node).attr('href');
      var title = $(node).attr('title');
      if(!title || title == '') {
        title = href;
      }
      var result = {
        url: href,
        title: title
      };
      return result;
    }
    return null;
  };

  $.fn._toggleView = function() {
    var id = this.attr('id');
    this._setContentCode(this._getContentCode());
    if ($instructureEditorBoxList._getEditor(id)) {
      $instructureEditorBoxList._getEditor(id).toggle();
    }
  };

  $.fn._removeEditor = function() {
    var id = this.attr('id');
    this.data('rich_text', false);
    if ($instructureEditorBoxList._getEditor(id)) {
      $instructureEditorBoxList._getEditor(id).destroy();
      $instructureEditorBoxList._removeEditorBox(id);
    }
  };

  $.fn._setContentCode = function(val) {
    var id = this.attr('id');
    if ($instructureEditorBoxList._getEditor(id)) {
      $instructureEditorBoxList._getEditor(id).set(val);
    }
  };

  $.fn._insertHTML = function(html) {
    var id = this.attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if(!editor) {
      this.replaceSelection(html);
    } else {
      editor.insertHtml(html);
    }
  };

  $.fn._editorFocus = function(keepTrying) {
    var $element = this,
        id = $element.attr('id'),
        editor = $instructureEditorBoxList._getEditor(id);
    if (keepTrying && (!editor || !editor.document.hasFocus())) {
      setTimeout(function(){
        $element.editorBox('focus', true);
      }, 50);
    }
    if(!editor ) {
      return false;
    }
    if(!$instructureEditorBoxList._getEditor(id)) {
      $("textarea#" + id).focus().select();
    } else {
      $instructureEditorBoxList._getEditor(id).focus();
      $.publish('editorBox/focus', $element);
    }
    return true;
  };

  $.fn._linkSelection = function(options) {
    if(typeof(options) == "string") {
      options = {url: options};
    }
    var title = options.title;
    var url = options.url || "";
    if(url.match(/@/) && !url.match(/\//) && !url.match(/^mailto:/)) {
      url = "mailto:" + url;
    } else if(!url.match(/^\w+:\/\//) && !url.match(/^mailto:/) && !url.match(/^\//)) {
      url = "http://" + url;
    }
    var classes = options.classes || "";
    var defaultText = options.text || options.title || "Link";
    var target = options.target || null;
    var id = $(this).attr('id');
    if(url.indexOf("@") != -1) {
      options.file = false;
      options.image = false;
      if(url.indexOf("mailto:") != 0) {
        url = "mailto:" + url;
      }
    } else if (url.indexOf("/") == -1) {
      title = url;
      url = url.replace(/\s/g, "");
      url = location.href + url;
    }
    if(options.file) {
      classes += "instructure_file_link ";
    }
    if(options.scribdable) {
      classes += "instructure_scribd_file ";
    }
    var link_id = '';
    if(options.kaltura_entry_id && options.kaltura_media_type) {
      link_id = "media_comment_" + options.kaltura_entry_id;
      if(options.kaltura_media_type == 'video') {
        classes += "instructure_video_link ";
      } else {
        classes += "instructure_audio_link ";
      }
    }
    if(options.image) {
      classes += "instructure_image_thumbnail ";
    }
    classes = $.unique(classes.split(/\s+/)).join(" ");
    var selectionText = "";
    var editor = $instructureEditorBoxList._getEditor(id);
    if(enableBookmarking && this.data('last_bookmark')) {
      tinyMCE.get(id).selection.moveToBookmark(this.data('last_bookmark'));
    }
    var anchor = editor.getCurrent();
    while(anchor.nodeName != 'A' && anchor.nodeName != 'BODY' && anchor.parentNode) {
      anchor = anchor.parentNode;
    }
    if(anchor.nodeName != 'A') { anchor = null; }

    var selectedContent = editor.getSelectionText();
    if(!$instructureEditorBoxList._getEditor(id)) {
      selectionText = defaultText;
      var $div = $("<div><a/></div>");
      $div.find("a")
        [link_id ? 'attr' : 'removeAttr']('id', link_id).attr({
          title: title,
          href: url,
          target: target
        })
        [classes ? 'attr' : 'removeAttr']('class', classes)
        .text(selectionText);
      var link_html = $div.html();
      $(this).replaceSelection(link_html);
    } else if(!selectedContent || selectedContent == "") {
      if(anchor) {
        $(anchor).attr({
          href: url,
          '_mce_href': url,
          title: title || '',
          id: link_id,
          'class': classes,
          target: target
        });
      } else {
        selectionText = defaultText;
        var $div = $("<div/>");
        $div.append($("<a/>", {id: link_id, target: target, title: title, href: url, 'class': classes}).text(selectionText));
        $instructureEditorBoxList._getEditor(id).insertHtml($div.html());
      }
    } else {
      var $a = $("<a/>", {target: (target || ''), title: (title || ''), href: url, 'class': classes, 'id': link_id});
      $instructureEditorBoxList._getEditor(id).insertNode($a);
    }

    var ed = $instructureEditorBoxList._getEditor(id);
    var e = ed.getNodes();
    if(e.nodeName != 'A') {
      e = $(e).children("a:last")[0];
    }
    if(e) {
      var nodeOffset = {top: e.offsetTop, left: e.offsetLeft};
      var n = e;
      // There's a weird bug here that I can't figure out.  If the editor box is scrolled
      // down and the parent window is scrolled down, it gives different value for the offset
      // (nodeOffset) than if only the editor window is scrolled down.  You scroll down
      // one pixel and it changes the offset by like 60.
      // This is the fix.
      while((n = n.offsetParent) && n.tagName != 'BODY') {
        nodeOffset.top = nodeOffset.top + n.offsetTop || 0;
        nodeOffset.left = nodeOffset.left + n.offsetLeft || 0;
      }
      var box = ed.getContainer();
      var boxOffset = $(box).find('iframe').offset();
      var frameTop = $(ed.dom.doc).find("html").scrollTop() || $(ed.dom.doc).find("body").scrollTop();
      var offset = {
        left: boxOffset.left + nodeOffset.left,
        top: boxOffset.top + nodeOffset.top - frameTop
      };
      $(e).indicate({offset: offset, singleFlash: true, scroll: true, container: $(box).find('iframe')});
    }
  };

});
