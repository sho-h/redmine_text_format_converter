namespace :redmine do
  desc "Converts text format from Textile to Markdown."
  task :convert_text_format => :environment do
    RedmineTextFormatConverter.run
  end

  desc "Check texts."
  task :check_texts => :environment do
    RedmineTextFormatConverter.check_texts
  end

  desc "fix invalid texts."
  task :fix_invalid_texts => :environment do
    RedmineTextFormatConverter.fix_invalid_texts
  end
end
