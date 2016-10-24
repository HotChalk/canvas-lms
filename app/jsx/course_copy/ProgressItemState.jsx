define([
  'react',
  'i18n!course_copy_tool'
], (React, I18n) => {
  var ProgressItemState = React.createClass({
      getClassName: function(){
        var class_name = '';
        switch (this.props.workflow_state) {
              case "Error":   
              case "failed":
                class_name =  "label-important";
              break;
              case "Completed": 
              case "imported": 
                class_name =  "label-success";
              break;
              case "Processing":  
                class_name =  "label-warning";
              break;
              default:      
                class_name =  "label-default";
              break;
        }
        return class_name + " label pull-right"
      },
      getDisplaText: function(){        
        var text = "";
        switch(this.props.workflow_state){
          case "Processing":
            text = this.props.workflow_state + " | " + this.props.completion;
          break;
          case "Error":
          case "failed":
            text = I18n.t('error', 'Error') + this.props.error;
          break;
          default:
            text = this.props.workflow_state;
          break;
        }
        return text;
      },
      render(){
        return(
          <span className={this.getClassName()}>{this.getDisplaText()}</span>           
        )
      }      
  });

  return ProgressItemState  
});