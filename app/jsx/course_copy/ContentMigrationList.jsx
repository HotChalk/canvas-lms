define([
  'react',  
  "./MigrationItem"
], (React, MigrationItem) => {

  var ContentMigrationList = React.createClass({    
    render(){
      var self = this;
      var renderItems = function(migration, index){
        return <MigrationItem key={index} migration={migration} showCollapsed={self.props.showCollapsed} />
      };

      return(
        <div>          
          {this.props.migrations.map(renderItems)}
        </div>
      )
    }          
  })

  return ContentMigrationList
});