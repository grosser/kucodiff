require 'yaml'

module Kucodiff
  class << self
    def diff(files, ignore: false, indent_pod: false, expected: {})
      raise ArgumentError, "Need 2+ files" if files.size < 2

      base = files.shift
      base_template = read(base)

      diff = files.each_with_object({}) do |other, all|
        other_template = read(other)
        result =
          if indent_pod
            different_keys_pod_indented(base_template, other_template)
          else
            different_keys(base_template, other_template)
          end
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
        args = (defined?(Syck) ? [File.read(file)] : [File.read(file), file])
        YAML.load_stream(*args)
      else raise ArgumentError, "unknown file format in #{file}"
      end.first

      hashify_container_env!(content)
      hashify_required_env!(content)

      flat_hash(content)
    end

    # make env comparable
    def hashify_container_env!(content)
      containers = template(content).fetch('spec', {}).fetch('containers', [])
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
      annotations = template(content).fetch('metadata', {}).fetch('annotations', {})
      annotations[key] = Hash[annotations[key].strip.split(/[\s,]/).map { |k| [k, true] }] if annotations[key]
    end

    def different_keys_pod_indented(*templates)
      ignore_unindented = false
      prefix = "spec.template."

      templates.map! do |template|
        if template["kind"] == "Pod"
          ignore_unindented = true
          Hash[template.map { |k,v| [prefix + k, v] }]
        else
          template
        end
      end

      diff = different_keys(*templates)
      diff.select! { |k| k.start_with?(prefix) } if ignore_unindented
      diff
    end

    def different_keys(a, b)
      (a.keys + b.keys).uniq.select { |k| a[k] != b[k] }
    end

    def xor(a, b)
      a + b - (a & b)
    end

    def template(content)
      content['kind'] == "Pod" ? content : content.fetch('spec', {}).fetch('template', {})
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
