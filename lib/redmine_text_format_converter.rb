require "open3"

class RedmineTextFormatConverter
  def self.run
    new.run
  end

  def run
    check_pandoc
    ActiveRecord::Base.transaction do
      convert_setting_welcome_text
      [
        [Comment, :comments],
        [Document, :description],
        [Issue, :description],
        [Journal, :notes],
        [Message, :content],
        [News, :description],
        [Project, :description],
        [WikiContent, :text],
        [WikiContent::Version, :text],
      ].each do |klass, text_attribute_name|
        convert_text_attribute(klass, text_attribute_name)
      end
    end
  end

  private

  REQUIRED_PANDOC_VERSION = Gem::Version.create("1.13.0")

  PANDOC_PATH = "pandoc"

  PANDOC_COMMAND = "#{PANDOC_PATH} -f textile" +
    " -t markdown+fenced_code_blocks+lists_without_preceding_blankline" +
    " --atx-header"

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
    klass.all.each do |o|
      original_text = o.send(text_getter_name)
      converted_text = pandoc(original_text)
      o.send(text_setter_name, converted_text)
      o.save!
    end
  end

  def convert_setting_welcome_text
    Setting.find_all_by_name("welcome_text").each do |setting|
      original_text = setting.value
      converted_text = pandoc(original_text)
      setting.value = converted_text
      setting.save!
    end
  end
end
