require "open3"

require "progressbar"

class RedmineTextFormatConverter
  def self.run
    new.run
  end

  def self.check_texts
    new.check_texts
  end

  def self.fix_invalid_texts
    new.fix_invalid_texts
  end

  def run
    check_pandoc
    ActiveRecord::Base.transaction do
      convert_setting_welcome_text
      TEXT_ATTRIBUTES.each do |klass, text_attribute_name|
        convert_text_attribute(klass, text_attribute_name)
      end
    end
  end

  def check_texts
    invalid_attributes = []
    TEXT_ATTRIBUTES.each do |klass, text_attribute_name|
      text_getter_name = text_attribute_name
      relation = klass.where("#{text_attribute_name} != ''")
      n = relation.count
      puts("#{klass.name}##{text_attribute_name} #{n} rows:")
      progress = ProgressBar.new("checking", n)
      relation.order(:id).each_with_index do |o, i|
        l.debug { "checking: i=<#{i}> id=<#{o.id}>" }
        original_text = o.send(text_getter_name)
        invalid_attribute = check_text(o, text_attribute_name, original_text)
        invalid_attributes << invalid_attribute if invalid_attribute
        progress.inc
      end
      progress.finish
    end
    if invalid_attributes.length <= 0
      puts("Yay! No invalid attributes.")
    else
      puts("#{invalid_attributes.length} invalid attributes are found.")
      File.write("invalid_attributes.yml", <<EOS.chomp)
# This file is generated by "redmine:check_texts" task.

#{invalid_attributes.to_yaml}
EOS
    end
  end

  def fix_invalid_texts
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

  TEXT_ATTRIBUTES = [
    [Comment, :comments],
    [Document, :description],
    [Issue, :description],
    [Journal, :notes],
    [Message, :content],
    [News, :description],
    [Project, :description],
    [WikiContent, :text],
  ]

  REQUIRED_PANDOC_VERSION = Gem::Version.create("1.13.0")

  PANDOC_PATH = "pandoc"

  PANDOC_COMMAND = "#{PANDOC_PATH} -f textile" +
    " -t markdown+fenced_code_blocks+lists_without_preceding_blankline" +
    " --atx-header"

  EDITOR_COMMENT_END_MARK =
    "# =============== The text is started under here ==============="

  def l
    return ActiveRecord::Base.logger
  end

  def disable_record_timestamps(record)
    record.record_timestamps = false
    if record.respond_to?(:force_updated_on_change, true) # for Issue model
      def record.force_updated_on_change
        # do not change updated_on
      end
    end
  end

  def capture2(*command, **options)
    stdout, status = *Open3.capture2(*command, options)
    if !status.success?
      raise "failed to run Pandoc."
    end
    return stdout
  end

  def check_pandoc
    stdout = capture2("#{PANDOC_PATH} --version")
    pandoc_version = Gem::Version.create(stdout.split(/\s/)[1])
    if pandoc_version < REQUIRED_PANDOC_VERSION
      raise "required Pandoc version: >= #{REQUIRED_PANDOC_VERSION}"
    end
  end

  def pandoc(source)
    return capture2(PANDOC_COMMAND, stdin_data: source)
  end

  def convert_text_attribute(klass, text_attribute_name)
    text_getter_name = text_attribute_name
    text_setter_name = "#{text_getter_name}=".to_sym
    relation = klass.where("#{text_attribute_name} != ''")
    n = relation.count
    puts("#{klass.name}##{text_attribute_name} #{n} rows:")
    progress = ProgressBar.new("converting", n)
    relation.order(:id).each_with_index do |o, i|
      l.debug { "processing: i=<#{i}> id=<#{o.id}>" }
      original_text = o.send(text_getter_name)
      converted_text = pandoc(original_text)
      o.send(text_setter_name, converted_text)
      disable_record_timestamps(o)
      o.save!
      progress.inc
    end
    progress.finish
  end

  def convert_setting_welcome_text
    Setting.find_all_by_name("welcome_text").each do |setting|
      original_text = setting.value
      converted_text = pandoc(original_text)
      setting.value = converted_text
      disable_record_timestamps(setting)
      setting.save!
    end
  end

  def check_text(record, text_attribute_name, text)
    invalid_attribute = nil
    n_pre_begin_tags = text.each_line.lazy.grep(/<pre>/).count
    n_pre_end_tags = text.each_line.lazy.grep(%r|</pre>|).count
    if n_pre_begin_tags != n_pre_end_tags
      reason = "mismatch number of <pre>(#{n_pre_begin_tags})" +
        " and </pre>(#{n_pre_end_tags})"
      invalid_attribute = {
        klass: record.class.name,
        text_attribute_name: text_attribute_name.to_s,
        id: record.id,
        reason: reason,
      }
      l.warn {
        "#{create_location_string(invalid_attribute)}: #{reason}"
      }
    end
    return invalid_attribute
  end

  def create_location_string(d)
    return "#{d[:klass]}(#{d[:id]})##{d[:text_attribute_name]}"
  end

  def search_editor
    return ENV["EDITOR"] || `which editor vi`[/.*(?=\n)/]
  end
end
