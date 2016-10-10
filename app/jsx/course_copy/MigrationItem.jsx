define([
  'react',  
  "./ProgressList",
  'jquery'
], (React, ProgressList, $) => {
  var MigrationItem = React.createClass({          
    getStatus: function(workflow_state){
        var result = "";
        switch(workflow_state){
          case "exporting":
            result = "Queued for processing"
          break;
          case "imported":
            result = "Completed"
          break;

          default:
          break;
        }
        return result;
    },
    render(){   
      var created_at = $.dateString(this.props.migration.content_migration.created_at, {format: 'medium'})
      // var created_at = moment(this.props.migration.content_migration.created_at).format("MMMM Do YYYY, h:mm:ss a");               
      var finished_at = $.dateString(this.props.migration.content_migration.finished_at, {format: 'medium'})
      // var finished_at = (this.props.migration.content_migration.finished_at)? moment(this.props.migration.content_migration.finished_at).format("MMMM Do YYYY, h:mm:ss a") : '';               
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
                      Migration Details ...</p>
                  <span className="pull-right clickable"><i className={icon}></i></span>
              </div>
              <div className="panel-body" style={{display:display_style}}>
                  <div className="_col col-xs-7">          
                    <div className="_row">
                        <span className="subtitle">Created at: </span>{created_at}                                                 
                    </div>
                    <div className="_row">
                        <span className="subtitle">Finished at: </span>{finished_at}                         
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