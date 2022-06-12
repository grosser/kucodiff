require 'yaml'

module Kucodiff
  class << self
    def diff(files, ignore: false, indent_pod: true, expected: {})
      raise ArgumentError, "Need 2+ files" if files.size < 2

      base = files.shift

      diff = files.each_with_object({}) do |other, all|
        # re-read both since we modify them
        base_template = read(base)
        other_template = read(other)

        pod_indented!(base_template, other_template) if indent_pod
        result = different_keys(base_template, other_template)
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
      content =
        if file.end_with?('.yml', '.yaml')
          if RUBY_VERSION >= "2.6.0"
            YAML.load_stream(File.read(file), filename: file) # uncovered
          else
            YAML.load_stream(File.read(file), file) # uncovered
          end
        else
          raise ArgumentError, "unknown file format in #{file}"
        end.first

      template = template(content)
      template.dig("spec", "containers")&.each do |container|
        hashify_named_array!(container, "env", first: true)
        hashify_named_array!(container, "volumeMounts", first: false)
      end
      hashify_named_array!(template["spec"], "volumes", first: false)
      hashify_required_env!(content)

      flat_hash(content)
    end

    def hashify_named_array!(object, key, first:)
      return if !object || !(array = object[key])
      object[key] = array.to_h do |v|
        keep = (v.keys - ['name'])
        value =
          if first
            v.fetch(keep.first)
          else
            v.slice(*keep)
          end
        [v.fetch('name'), value]
      end
    end

    def hashify_required_env!(content)
      key = 'samson/required_env'
      annotations = template(content).fetch('metadata', {}).fetch('annotations', {})
      annotations[key] = Hash[annotations[key].strip.split(/[\s,]/).map { |k| [k, true] }] if annotations[key]
    end

    # templates are flat hashes already
    def pod_indented!(*templates)
      kinds = templates.map { |t| t["kind"] }
      return if (kinds & ["Pod", "PodTemplate"]).empty? || kinds.uniq.size == 1

      templates.each do |template|
        case template["kind"]
        when "Pod"
          # all good
        when "PodTemplate"
          template.select! { |k, _| k.start_with?("template.") }
          template.transform_keys! { |k| k.sub("template.", "") }
        else
          template.select! { |k, _| k.start_with?("spec.template.") }
          template.transform_keys! { |k| k.sub("spec.template.", "") }
        end
      end
    end

    def different_keys(a, b)
      (a.keys + b.keys).uniq.select { |k| a[k] != b[k] }
    end

    def xor(a, b)
      a + b - (a & b)
    end

    def template(content)
      case content['kind']
      when "Pod" then content
      when "PodTemplate" then content.fetch('template')
      else content.dig('spec', 'template') || {}
      end
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
