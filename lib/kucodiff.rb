require 'yaml'

module Kucodiff
  class << self
    def diff(files, ignore: false, expected: {})
      raise ArgumentError, "Need 2+ files" if files.size < 2

      base = files.shift
      base_template = read(base)
      diff = files.each_with_object({}) do |other, all|
        result = different_keys(base_template, read(other))
        result.reject! { |k| k =~ ignore } if ignore
        all["#{base}-#{other}"] = result.sort
      end

      expected.each do |k, v|
        result = xor(diff[k] || [], v)
        result.empty? ? diff.delete(k) : diff[k] = result
      end

      diff
    end

    private

    def read(file)
      content = if file.end_with?('.yml', '.yaml')
        YAML.load_stream(File.read(file)) # TODO: test need for stream
      else raise ArgumentError, "unknown file format in #{file}"
      end.first

      hashify_container_env!(content)
      hashify_required_env!(content)

      flat_hash(content)
    end

    # make env comparable
    def hashify_container_env!(content)
      containers = content.fetch('spec', {}).fetch('template', {}).fetch('spec', {}).fetch('containers', [])
      containers.each do |container|
        next unless container['env']
        container['env'] = container['env'].each_with_object({}) do |v, h|
          value_key = (v.keys - ['name']).first
          h[v.fetch('name')] = v.fetch(value_key)
        end
      end
    end

    def hashify_required_env!(content)
      key = 'samson/required_env'
      annotations = content.fetch('spec', {}).fetch('template', {}).fetch('metadata', {}).fetch('annotations', {})
      annotations[key] = Hash[annotations[key].strip.split(/[\s,]/).map { |k| [k, true] }] if annotations[key]
    end

    def different_keys(a, b)
      (a.keys + b.keys).uniq.select { |k| a[k] != b[k] }
    end

    def xor(a, b)
      a + b - (a & b)
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
