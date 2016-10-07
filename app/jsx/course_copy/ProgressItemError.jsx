define([
  'react',
  "./ProgressItemState"
], (React, ProgressItemState) => {
  var ProgressItemError = React.createClass({        
    render(){                
      return(        
        <div className="_row well">
          <div className="_col col-xs-7">          
              <div className="_row">
                <span className="subtitle">Master: </span> <a href="#" target="_blank">{this.props.progress.master_id}</a>
              </div>
              <div className="_row">
                <span className="subtitle">Target: </span> <a href="#" target="_blank">{this.props.progress.target_id}</a>
              </div>
              <div className="_row">
                <div className="_col"><span className="subtitle">Message: </span>{this.props.progress.message} </div>                
              </div>
          </div>            
          <div className="_col col-xs-1">               
            <ProgressItemState workflow_state={this.props.progress.workflow_state} completion={this.props.progress.completion} error={this.props.progress.error} />            
          </div>          
        </div>        
      )
    }
  })

  return ProgressItemError  
});