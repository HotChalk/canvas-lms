define([
  'react',
  "./ProgressItemState"
], (React, ProgressItemState) => {
  var ProgressItem = React.createClass({        
    render(){            
      return(        
        <div className="_row well">
          <div className="_col col-xs-7">          
              <div className="_row">
                <span className="subtitle">Target: </span> <a href="#" target="_blank">{this.props.progress.target_id}</a>
              </div>
              <div className="_row">
                <div className="_col"><span className="subtitle">Name: </span>{this.props.progress.target_name} </div>
                <div className="_col"><span className="subtitle">Code: </span> {this.props.progress.target_code_id} </div> 
                <div className="_col"><span className="subtitle">Section: </span> {this.props.progress.target_section_name} </div>
              </div>
              <div className="_row">
                <span className="subtitle">Master: </span> <a href="#" target="_blank">{this.props.progress.master_id}</a>
              </div>
              <div className="_row">
                <div className="_col"><span className="subtitle">Name: </span>{this.props.progress.master_name} </div>
                <div className="_col"><span className="subtitle">Code: </span> {this.props.progress.master_code_id} </div> 
                <div className="_col"><span className="subtitle">Section: </span> {this.props.progress.master_section_name} </div>
              </div>
          </div>  
          <div className="_col col-xs-2">  
            <div className="_row">
                <span className="date">{this.props.progress.created_at}</span>
            </div>
            <div className="_row">
                <span className="date">{this.props.progress.updated_at}</span>
            </div>
          </div>  
          <div className="_col col-xs-1">               
            <ProgressItemState workflow_state={this.props.progress.workflow_state} completion={this.props.progress.completion} error={this.props.progress.error} />            
          </div>          
        </div>        
      )
    }
  })

  return ProgressItem  
});