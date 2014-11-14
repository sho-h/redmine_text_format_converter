namespace :redmine do
  desc "Converts text format from Textile to Markdown."
  task :convert_text_format => :environment do
    RedmineTextFormatConverter.run
  end

  desc "Check Textile texts."
  task :check_textile_texts => :environment do
    RedmineTextFormatConverter.check_texts
  end
end
