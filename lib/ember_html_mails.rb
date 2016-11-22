module ExtendedEmailReplyParser
  class Parsers::EmberHtmlMails < Parsers::Base

    def parse
      except_in_visible_block_quotes do
        hide_everything_after ["<div class=\"gmail_extra\"", "<div class=\"gmail_quote\""]
      end
    end

  end
end
