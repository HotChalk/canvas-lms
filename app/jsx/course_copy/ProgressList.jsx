define([
  'react',  
  "./ProgressItem",
  "./ProgressItemError"
], (React, ProgressItem,ProgressItemError) => {

  var ProgressList = React.createClass({    
    render(){
      var renderItems = function(progress, index){
        if (!progress.status){
          return <ProgressItemError key={index} progress={progress} />  
        }
        else{
          return <ProgressItem key={index} progress={progress} />  
        }                
      };

      return(
        <div>          
          {this.props.progresses.map(renderItems)}
        </div>
      )
    }          
  })

  return ProgressList
});