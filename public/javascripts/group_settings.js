/**
 * Copyright (C) 2011 Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
define([
  'INST' /* INST */,
  'jquery' /* $ */,
  'underscore',
  'jquery.ajaxJSON' /* ajaxJSON */,
  'jquery.instructure_forms' /* formSubmit, fillFormData, getFormData, formErrors */,
  'jqueryui/dialog',
  'compiled/jquery/fixDialogButtons' /* fix dialog formatting */,
  'jquery.instructure_misc_helpers' /* scrollSidebar */,
  'jquery.instructure_misc_plugins' /* confirmDelete, fragmentChange, showIf */,
  'jquery.keycodes' /* keycodes */,
  'jquery.loadingImg' /* loadingImage */,
  'compiled/jquery.rails_flash_notifications',
  'jqueryui/autocomplete' /* /\.autocomplete/ */,
  'jqueryui/sortable' /* /\.sortable/ */,
], function(INST,$, _) {

  $(document).ready(function() {
    $("#nav_form").submit(function(){
      tab_id_regex = /(\d+)$/;
      function tab_id_from_el(el) {
        var tab_id_str = $(el).attr("id");
        if (tab_id_str) {
          var tab_id = tab_id_str.replace(/^nav_edit_tab_id_/, '');
          if (tab_id.length > 0) {
            if(!tab_id.match(/context/)) {
              tab_id = parseInt(tab_id, 10);
            }
            return tab_id;
          }
        }
        return null;
      }

      var tabs = [];
      $("#nav_enabled_list li").each(function() {
        var tab_id = tab_id_from_el(this);
        if (tab_id !== null) { tabs.push({ id: tab_id }); }
      });
      $("#nav_disabled_list li").each(function() {
        var tab_id = tab_id_from_el(this);
        if (tab_id !== null) { tabs.push({ id: tab_id, hidden: true }); }
      });

      $("#tabs_json").val(JSON.stringify(tabs));

      function dynamic_tab_id_from_el(el) {
        return $(el).attr("id").replace(/^nav_dynamic_tab_id_/, '');
      }
      var dynamic_tabs = [];
      $("#nav_dynamic_list li").each(function() {
        var tab_id = dynamic_tab_id_from_el(this);
        var tab_id_arr = tab_id.split('_');
        if (tab_id !== null) { dynamic_tabs.push({ context_id: parseInt(tab_id_arr.pop()), context_type: tab_id_arr.join('_'), label: $($(this).contents()[0]).text().trim() }); }
      });
      $("#dynamic_tabs_json").val(JSON.stringify(dynamic_tabs));
      return true;
    });

    $(".edit_nav_link").click(function(event) {
      event.preventDefault();
      $("#nav_form").dialog({
        modal: true,
        resizable: false,
        width: 400
      });
    });

    $("#nav_enabled_list, #nav_disabled_list").sortable({
      items: 'li.enabled',
      connectWith: '.connectedSortable',
      axis: 'y'
    }).disableSelection();

    $(".add_page_link").live('click', function(event) {
      event.preventDefault();
      if(INST && INST.linkContentDialog) {
        var options = {
          submit: function(item_data) {
            var id = item_data['item[id]'];
            var type = item_data['item[type]'];
            var title = item_data['item[title]'];
            var li = $('<li>').attr({
              'class': 'navitem enabled links',
              id: 'nav_dynamic_tab_id_' + type + '_' + id,
              tabindex: '0'
            });
            li.data('context_type', type);
            li.data('context_id', id);
            li.append(title).append($("<div class='links'><a class='no-hover delete_page_link' title='Delete Page Link'><i class='icon-end standalone-icon'></i><span class='screen-reader-text'>Delete</span></a></div>"));
            $("#nav_dynamic_list").append(li);
          }
        };
        INST.linkContentDialog(options);
      }
    });
    $("a.delete_page_link").live('click', function(event) {
      event.preventDefault();
      $(this).parents('li').remove();
    });
    $.scrollSidebar();
  });
});
