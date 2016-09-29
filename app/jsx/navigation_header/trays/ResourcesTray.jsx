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
          <li className="ic-NavMenu-list-item ic-NavMenu-list-item--loading-message">
            {I18n.t('Loading')} &hellip;
          </li>
        );
      }
      var resources = this.props.resources.map((resource) => {
        return (
          <li className='ic-NavMenu-list-item'>
            <a target="_blank" href={resource.url} className='ic-NavMenu-list-item__link'>{resource.name}</a>
          </li>
        );
      });
      
      return resources;
    },

    render() {
      return (
        <div>
          <div className="ic-NavMenu__header">
            <h1 className="ic-NavMenu__headline">{I18n.t('Resources')}</h1>
            <button className="Button Button--icon-action ic-NavMenu__closeButton" type="button" onClick={this.props.closeTray}>
              <i className="icon-x"></i>
              <span className="screenreader-only">{I18n.t('Close')}</span>
            </button>
          </div>
          <ul className="ic-NavMenu__link-list">
            {this.renderResources()}
          </ul>
        </div>
      );
    }
  });

  return ResourcesTray;

});
