define([
  'react',
  "./ProgressItemState",
  'i18n!course_copy_tool'
], (React, ProgressItemState, I18n) => {
  var ProgressItemError = React.createClass({        
    render(){                
      return(        
        <div className="_row well">
          <div className="_col col-xs-7">          
              <div className="_row">
                <span className="subtitle">{I18n.t('Target')}: </span> <span>{this.props.progress.target_id}</span>
              </div>
              <div className="_row">
                <span className="subtitle">{I18n.t('Master')}: </span> <span>{this.props.progress.master_id}</span>
              </div>              
              <div className="_row">
                <div className="_col"><span className="subtitle">{I18n.t('Message')}: </span>{this.props.progress.error_msg} </div>                
              </div>
          </div>            
          <div className="_col col-xs-1">               
            <ProgressItemState workflow_state={this.props.progress.workflow_state} completion={0} error={this.props.progress.data.error} />            
          </div>          
        </div>        
      )
    }
  })

  return ProgressItemError  
});