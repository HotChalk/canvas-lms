define([
  'react',  
  "./ProgressList",
  "jquery",  
  'i18n!course_copy_tool',
  "./Pager"  
], (React, ProgressList, $, I18n, Pager) => {
  var MigrationItem = React.createClass({          
    self: this,

    getInitialState: function() {      
      return {
        total: 0,
        current: 0,
        visiblePage: 4,
        items_count: 15,
        start_items: 0,
        end_items: 15
      };
    },

    componentWillMount () {      
      this.setState({total: Math.floor(this.props.migration.content_migration.migration_settings.results.length / this.state.items_count) + 1});      
    },

    getStatus: function(workflow_state){
        var result = "";
        switch(workflow_state){          
          case "created":
          case "pre_processing":
            result = I18n.t('state_queued_processing', "Queued for processing")
          break;
          case "exporting":
            result = I18n.t('state_exporting', "Exporting")
          break;
          case "exported":
          case "imported":
            result = I18n.t('state_completed', 'Completed')
          break;
          case "failed":
            result = I18n.t('state_failed', 'Failed')
          break;

          default:
          break;
        }
        return result;
    },
    
    
    handlePageChanged(change_state=false, newPage) {      
      if (change_state !== false){
        this.setState({ current : newPage });
        var start = newPage * this.state.items_count;
        var end = start + this.state.items_count;        
        if (end > this.props.migration.content_migration.migration_settings.results.length){
          end = this.props.migration.content_migration.migration_settings.results.length;
        }
        this.setState({ start_items : start });
        this.setState({ end_items : end });        
      }      
    },
    
    renderPagination: function(){
      return (this.props.migration.content_migration.migration_settings.results.length > this.state.items_count) ? <Pager total={this.state.total} current={this.state.current} visiblePages={this.state.visiblePage} onPageChanged={this.handlePageChanged} start_items={this.state.start_items+1} end_items={this.state.end_items} total_items={this.props.migration.content_migration.migration_settings.results.length} /> : '';      
    },
    
    setItems: function(){
      var start = this.state.start_items;
      var end = this.state.end_items;
      
      return this.props.migration.content_migration.migration_settings.results.slice(start, end);
    },

    render(){         
      var items = this.setItems();    
      var created_at = $.dateString(this.props.migration.content_migration.created_at, {format: 'medium'}) + " " + $.timeString(this.props.migration.content_migration.created_at,{format: 'Long'});
      var finished_at = $.dateString(this.props.migration.content_migration.finished_at, {format: 'medium'}) + " " + $.timeString(this.props.migration.content_migration.finished_at,{format: 'Long'});      
      var number_processed = this.props.migration.content_migration.migration_settings.number_processed || 0;
      var total_copy = this.props.migration.content_migration.migration_settings.total_copy || 0;      
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
                    <div className="_row">
                        <span className="subtitle">Courses processed: {number_processed} of {total_copy} </span>                         
                    </div>
                    <br/>
                  </div>                    
                  <ProgressList progresses={items} />
                  {this.renderPagination()}                  
              </div>
          </div>   
       </div>   
      )
    }
  })

  return MigrationItem  
});