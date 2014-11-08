namespace :redmine do
  desc "Converts text format from Textile to Markdown."
  task :convert_text_format => :environment do
    RedmineTextFormatConverter.run
  end
end
