define([
  'i18n!new_nav',
  'react',
  'jsx/shared/SVGWrapper'
], (I18n, React, SVGWrapper) => {

  var ResourcesTray = React.createClass({
    propTypes: {
      resources: React.PropTypes.array.isRequired,
      closeTray: React.PropTypes.func.isRequired,
      hasLoaded: React.PropTypes.bool.isRequired
    },

    getDefaultProps() {
      return {
        resources: []
      };
    },

    renderResources() {
      if (!this.props.hasLoaded) {
        return (
          <li className="ReactTray-list-item ReactTray-list-item--loading-message">
            {I18n.t('Loading')} &hellip;
          </li>
        );
      }
      var resources = this.props.resources.map((resource) => {
        return (
          <li className='ReactTray-list-item'>            
            <a target="_blank" href={resource.url} className='ReactTray-list-item__link'>{resource.name}</a>
          </li>
        );
      });
      
      return resources;
    },

    render() {
      return (
        <div>
          <div className="ReactTray__header">
            <h1 className="ReactTray__headline">{I18n.t('Resources')}</h1>
            <button className="Button Button--icon-action ReactTray__closeBtn" type="button" onClick={this.props.closeTray}>
              <i className="icon-x"></i>
              <span className="screenreader-only">{I18n.t('Close')}</span>
            </button>
          </div>
          <ul className="ReactTray__link-list">
            {this.renderResources()}
          </ul>
        </div>
      );
    }
  });

  return ResourcesTray;

});
