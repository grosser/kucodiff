require 'yaml'

module Kucodiff
  class << self
    def diff(files, ignore_command: false)
      raise ArgumentError, "Need 2+ files" if files.size < 2

      base = files.shift
      base_template = read(base)
      files.each_with_object({}) do |other, all|
        result = different_keys(base_template, read(other))
        result.reject! { |k| k.include?('.command.') } if ignore_command
        all["#{base}-#{other}"] = result
      end
    end

    private

    def read(file)
      content = if file.end_with?('.yml', '.yaml')
        YAML.load_stream(File.read(file)) # TODO: test need for stream
      else raise ArgumentError, "unknown file format in #{file}"
      end.first

      hashify_container_env(content)
      flat_hash(content)
    end

    # make env compareable
    def hashify_container_env(content)
      containers = content.fetch('spec', {}).fetch('template', {}).fetch('spec', {}).fetch('containers', [])
      containers.each do |container|
        next unless container['env']
        container['env'] = container['env'].each_with_object({}) do |v, h|
          value_key = (v.keys - ['name']).first
          h[v.fetch('name')] = v.fetch(value_key)
        end
      end
    end

    def different_keys(a, b)
      (a.keys + b.keys).uniq.select { |k| a[k] != b[k] }
    end

    # http://stackoverflow.com/questions/9647997/converting-a-nested-hash-into-a-flat-hash
    def flat_hash(input, base = nil, all = {})
      if input.is_a?(Array)
        input = input.each_with_index.to_a.each(&:reverse!)
      end

      if input.is_a?(Hash) || input.is_a?(Array)
        input.each do |k, v|
          flat_hash(v, base ? "#{base}.#{k}" : k, all)
        end
      else
        all[base] = input
      end

      all
    end
  end
end
