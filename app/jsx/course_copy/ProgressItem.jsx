define([
  'react',
  "./ProgressItemState",
  'i18n!course_copy_tool'
], (React, ProgressItemState, I18n) => {
  var ProgressItem = React.createClass({    
    getUrl: function(isMaster){
      var url = (isMaster)? this.props.progress.master_url : this.props.progress.target_url;      
      return url;
    },   
    render(){            
      var created_at = $.dateString(this.props.progress.created_at, {format: 'medium'}) + " " + $.timeString(this.props.progress.created_at);
      var updated_at = $.dateString(this.props.progress.updated_at, {format: 'medium'}) + " " + $.timeString(this.props.progress.updated_at);
      
      return(        
        <div className="_row well">
          <div className="_col col-xs-7">          
              <div className="_row">
                <span className="subtitle">{I18n.t('Target')}: </span> <a href={this.getUrl(false)} target="_blank">{this.props.progress.target_id}</a>
              </div>
              <div className="_row">
                <div className="_col"><span className="subtitle">{I18n.t('Name')}: </span>{this.props.progress.target_name} </div>                
              </div>
              <div className="_row">
                <div className="_col"><span className="subtitle">{I18n.t('Code')}: </span> {this.props.progress.target_code_id} </div> 
                <div className="_col"><span className="subtitle">{I18n.t('Section')}: </span> {this.props.progress.target_section_name} </div>
              </div>
              <div className="_row">
                <span className="subtitle">{I18n.t('Master')}: </span> <a href={this.getUrl(true)} target="_blank">{this.props.progress.master_id}</a>
              </div>
              <div className="_row">
                <div className="_col"><span className="subtitle">{I18n.t('Name')}: </span>{this.props.progress.master_name} </div>                
              </div>
              <div className="_row">                
                <div className="_col"><span className="subtitle">{I18n.t('Code')}: </span> {this.props.progress.master_code_id} </div>                 
                <div className="_col"><span className="subtitle">{I18n.t('Section')}: </span> {this.props.progress.master_section_name} </div>
              </div>              
          </div>  
          <div className="_col col-xs-2">  
            <div className="_row">
                <span className="date">{created_at}</span>
            </div>
            <div className="_row">
                <span className="date">{updated_at}</span>
            </div>
          </div>  
          <div className="_col col-xs-1">               
            <ProgressItemState workflow_state={this.props.progress.workflow_state} completion={this.props.progress.completion} error="" />            
          </div>          
        </div>        
      )
    }
  })

  return ProgressItem  
});