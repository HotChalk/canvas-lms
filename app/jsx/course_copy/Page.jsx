define([
  'react' 
], (React) => {

  var Page = React.createClass({    
    propTypes: {
      isHidden:   React.PropTypes.bool,
      isActive:   React.PropTypes.bool,
      isDisabled: React.PropTypes.bool,
      className:  React.PropTypes.string,
      onClick:    React.PropTypes.func
    },
    render(){
      if (this.props.isHidden) return null;

      const baseCss = this.props.className ? `${this.props.className} ` : '';
      const fullCss = `${baseCss}${this.props.isActive ? ' active' : ''}${this.props.isDisabled ? ' disabled' : ''}`;

      return(
        <li key={this.props.index} className={fullCss}>
          <a onClick={this.props.onClick}>{this.props.children}</a>
        </li>
      )
    }          
  })

  return Page
});