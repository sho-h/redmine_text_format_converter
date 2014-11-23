require "open3"

require "redmine_text_format_converter/base"

module RedmineTextFormatConverter
  class Fixer < Base
    def run
      path = Pathname("invalid_attributes.yml")
      if !path.exist?
        puts(<<EOS)
No #{path}.

First, run redmine:check_texts task. And, retry.

    $ bundle exec rake redmine:check_texts redmine:fix_invalid_texts
EOS
        return
      end

      editor = search_editor
      if !editor
        puts("No editor.")
        return
      end

      invalid_attributes = YAML.load_file(path)
      invalid_attributes.each_with_index do |d, i|
        klass = d[:klass].constantize
        record = klass.find(d[:id])
        text = record.send(d[:text_attribute_name])
        Tempfile.open("text_format_converter_") do |f|
          s = <<EOS.gsub(/\r?\n/, "\r\n")
# Number: #{i + 1}/#{invalid_attributes.length}
# Location: #{create_location_string(d)}
# Reason: #{d[:reason]}
# URI: #{uri_for(record) || "URI for this type is not supported yet. Pull-request welcome!"}
# Console: record = #{d[:klass]}.find(#{d[:id]}); puts(record.#{d[:text_attribute_name]})
#
# If you want to abort fixing, set empty text.
#
#{EDITOR_COMMENT_END_MARK}
EOS
          f.write(s)
          f.write(text)
          f.close
          if !system("#{editor} #{f.path}")
            puts("Aborted. Some editor problem is occurred.")
            return
          end
          f.open
          text = f.read
          f.close(true)
        end
        if text.empty?
          puts("Aborted by user.")
          return
        end
        text.sub!(/.*?#{EDITOR_COMMENT_END_MARK}\r\n/m, "")
        text.sub!(/\s+\z/, "")
        record.send(d[:text_attribute_name] + "=", text)
        disable_record_timestamps(record)
        record.save!
      end
    end

    private

    EDITOR_COMMENT_END_MARK =
      "# =============== The text is started under here ==============="

    def search_editor
      return ENV["EDITOR"] || `which editor vi`[/.*(?=\n)/]
    end

    def uri_for(record)
      prefix = "#{Setting.protocol}://#{Setting.host_name}"
      case record
      when Issue
        return URI("#{prefix}/issues/#{record.id}")
      when Journal
        issue = record.issue
        note_number = issue.journals.find_index(record) + 1
        return URI("#{prefix}/issues/#{issue.id}#note-#{note_number}")
      when WikiContent
        project_identifier = record.page.project.identifier
        title = record.page.title
        return URI("#{prefix}/projects/#{project_identifier}/wiki/#{title}")
      else
        return nil
      end
    end
  end
end
