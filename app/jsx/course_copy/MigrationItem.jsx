define([
  'react',  
  "./ProgressList",
  'jquery',
  'i18n!course_copy_tool'
], (React, ProgressList, $, I18n) => {
  var MigrationItem = React.createClass({          
    getStatus: function(workflow_state){
        var result = "";
        switch(workflow_state){
          case "exporting":
            result = I18n.t('queued_processing', "Queued for processing")
          break;
          case "imported":
            result = I18n.t('completed', 'Completed')
          break;
          case "failed":
            result = I18n.t('failed', 'Failed')
          break;

          default:
          break;
        }
        return result;
    },
    render(){   
      var created_at = $.dateString(this.props.migration.content_migration.created_at, {format: 'medium'}) + " " + $.timeString(this.props.migration.content_migration.created_at);
      var finished_at = $.dateString(this.props.migration.content_migration.finished_at, {format: 'medium'}) + " " + $.timeString(this.props.migration.content_migration.finished_at);
      var items = this.props.migration.content_migration.migration_settings.results || [];    
      var icon = "icon-minimize";
      var display_style = "block";
      var class_style = "panel-heading clickable";

      if (this.props.showCollapsed){        
        icon = "icon-plus";
        display_style = "none";
        class_style = class_style + " panel-collapsed";
      }      

      return(        
        <div className="" >
          <div className="panel panel-info">
              <div className={class_style}>
                  <p className="panel-title">                  
                    {I18n.t("Migration started at")}: {created_at}</p>
                  <span className="pull-right clickable"><i className={icon}></i></span>
              </div>
              <div className="panel-body" style={{display:display_style}}>
                  <div className="_col col-xs-7">          
                    <div className="_row">
                        <span className="subtitle">{I18n.t("Created at")}: </span>{created_at}                                                 
                    </div>
                    <div className="_row">
                        <span className="subtitle">{I18n.t("Finished at")}: </span>{finished_at}                         
                    </div>
                    <div className="_row">
                        <span className="subtitle">Status: </span>{this.getStatus(this.props.migration.content_migration.workflow_state)}                         
                    </div>
                    <br/>
                  </div>  

                  <ProgressList progresses={items} />
              </div>
          </div>   
       </div>   
      )
    }
  })

  return MigrationItem  
});