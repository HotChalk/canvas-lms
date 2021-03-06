define([
  'react',
  'i18n!help_dialog',
  './CreateTicketForm',
  './TeacherFeedbackForm',
  './HelpLinks'
], (React, I18n, CreateTicketForm, TeacherFeedbackForm, HelpLinks) => {

  const HelpDialog = React.createClass({
    propTypes: {
      links: React.PropTypes.array,
      onFormSubmit: React.PropTypes.func
    },
    getDefaultProps() {
      return {
        links: [],
        onFormSubmit: function () {}
      };
    },
    getInitialState () {
      return {
        view: 'links'
      }
    },
    handleLinkClick (url) {
      this.setState({view: url});
    },
    handleCancelClick () {
      this.setState({view: 'links'});
    },
    render() {
      switch (this.state.view) {
        case '#create_ticket':
          return (
            <CreateTicketForm
              onCancel={this.handleCancelClick}
              onSubmit={this.props.onFormSubmit}
            />
          );
        case '#teacher_feedback':
          return (
            <TeacherFeedbackForm
              onCancel={this.handleCancelClick}
              onSubmit={this.props.onFormSubmit}
            />
          );
        default:
          return (
            <HelpLinks links={this.props.links} onClick={this.handleLinkClick} />
          );
      }
    }
  });

  return HelpDialog;
});
