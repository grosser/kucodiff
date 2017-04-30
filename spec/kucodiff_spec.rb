require "spec_helper"

SingleCov.covered!

describe Kucodiff do
  def in_temp_dir(&block)
    Dir.mktmpdir('kucodiff') { |dir| Dir.chdir dir, &block }
  end

  let(:template) do
    {
      "metadata" => {"name" => "console", "namespace" => "bar"},
      "spec" => {
        "template" => {
          "metadata" => {"labels" => {}},
          "spec" => {
            "containers" => [
              {
                "resources" => {"limits" => {"cpu" => "1.0"}},
                "env" => [
                  {"name" => "PORT", "value" => 1234},
                  {"name" => "FOO", "valueFrom" => "BAR"}
                ]
              }
            ]
          }
        }
      }
    }
  end

  around do |test|
    in_temp_dir do
      Dir.mkdir "kubernetes"
      File.write('kubernetes/console.yml', YAML.dump(template))

      template = YAML.load(YAML.dump(template()))
      template['metadata']['name'] = 'server'
      template['spec']['template']['spec']['containers'][0]['resources']['limits']['cpu'] = '2.3' # ignored
      template['spec']['template']['spec']['containers'][0]['env'].shift # remove PORT
      template['spec']['template']['metadata']['labels']['proxy'] = 'foo'
      File.write('kubernetes/server.yml', YAML.dump(template))

      template = YAML.load(YAML.dump(template()))
      template['metadata']['name'] = 'worker'
      template['spec']['template']['spec']['containers'][0]['resources']['limits']['memory'] = '23' # ignored
      template['spec']['template']['spec']['containers'][0]['env'] << {'name' => 'QUEUE', 'value' => '*'}
      File.write('kubernetes/worker.yml', YAML.dump(template))

      test.call
    end
  end

  it "has a VERSION" do
    expect(Kucodiff::VERSION).to match(/^[\.\da-z]+$/)
  end

  describe ".diff" do
    it "raises on too few files" do
      expect { Kucodiff.diff(['xxxx']) }.to raise_error(ArgumentError, "Need 2+ files")
    end

    it "raises on unknown format" do
      expect { Kucodiff.diff(['a.json', 'b.json']) }.to raise_error(ArgumentError, "unknown file format in a.json")
    end

    it "shows where parse errors are" do
      in_temp_dir do
        File.write("a.yml", {"foo" => 1}.to_yaml)
        File.write("b.yml", "[mysqld]\nstuff")
        expect { Kucodiff.diff(['a.yml', 'b.yml']) }.to raise_error(/\(b.yml\): did not find/)
      end
    end

    it "reads the first object when multiple exist" do
      in_temp_dir do
        File.write("a.yml", {"foo" => 1}.to_yaml + {"bar" => 1}.to_yaml)
        File.write("b.yml", {"foo" => 2}.to_yaml)
        expect(Kucodiff.diff(['a.yml', 'b.yml'])).to eq({"a.yml-b.yml" => ["foo"]})
      end
    end

    it "can ignore" do
      in_temp_dir do
        File.write("a.yml", {"spec" => {"template" => {"spec" => {"containers" => [{"command" => ["a", "b"]}]}}}}.to_yaml)
        File.write("b.yml", {"spec" => {"template" => {"spec" => {"containers" => [{"command" => ["c", "d"]}]}}}}.to_yaml)
        expect(Kucodiff.diff(['a.yml', 'b.yml'], ignore: /\.command\./)).to eq({"a.yml-b.yml" => []})
      end
    end

    it "removes things that are expected" do
      in_temp_dir do
        File.write("a.yml", {"a" => 1}.to_yaml)
        File.write("b.yml", {"a" => 1, "b" => 2}.to_yaml)
        expect(Kucodiff.diff(['a.yml', 'b.yml'], expected: {"a.yml-b.yml" => ["b"]})).to eq({})
      end
    end

    it "adds things that are unexpected" do
      in_temp_dir do
        File.write("a.yml", {"a" => 1}.to_yaml)
        File.write("b.yml", {"a" => 1, "b" => 2}.to_yaml)
        expect(Kucodiff.diff(['a.yml', 'b.yml'], expected: {"a.yml-b.yml" => ["c"], "a.yml-z.yml" => ["a"]})).to eq(
          "a.yml-b.yml" => ["b", "c"], "a.yml-z.yml" => ["a"]
        )
      end
    end

    it "converts required_env to an array" do
      in_temp_dir do
        File.write("a.yml", {"spec" => {"template" => {"metadata" => {"annotations" => {"samson/required_env" => "  a\nb,c d  "}}}}}.to_yaml)
        File.write("b.yml", {"spec" => {"template" => {"metadata" => {"annotations" => {"samson/required_env" => "f\nb,e d"}}}}}.to_yaml)
        expect(Kucodiff.diff(['a.yml', 'b.yml'])).to eq("a.yml-b.yml" => [
          "spec.template.metadata.annotations.samson/required_env.a",
          "spec.template.metadata.annotations.samson/required_env.c",
          "spec.template.metadata.annotations.samson/required_env.e",
          "spec.template.metadata.annotations.samson/required_env.f",
        ])
      end
    end

    describe "with indent_pod" do
      it "produces full diff when comparing non-pods" do
        in_temp_dir do
          template = {"metadata" => {"annotations" => {"foo" => "bar"}}}
          File.write("a.yml", {"spec" => {"template" => template, "other" => "ignores"}}.to_yaml)
          File.write("b.yml", template.to_yaml)
          expect(Kucodiff.diff(['a.yml', 'b.yml'], indent_pod: true)).to eq("a.yml-b.yml" => [
            "metadata.annotations.foo",
            "spec.other",
            "spec.template.metadata.annotations.foo"
          ])
        end
      end

      it "produces little diff when comparing a pod with a deployment" do
        in_temp_dir do
          template = {"metadata" => {"annotations" => {"foo" => "bar"}}}
          File.write("a.yml", {"spec" => {"template" => template, "other" => "ignores"}}.to_yaml)
          File.write("b.yml", template.merge("kind" => "Pod").to_yaml)
          expect(Kucodiff.diff(['a.yml', 'b.yml'], indent_pod: true)).to eq("a.yml-b.yml" => [
            "spec.template.kind",
          ])
        end
      end

      it "creates full diff when comparing a pod with a pod" do
        in_temp_dir do
          template = {"metadata" => {"annotations" => {"foo" => "bar"}}, "kind" => "Pod"}
          File.write("a.yml", template.to_yaml)
          File.write("b.yml", template.merge("foo" => "bar").to_yaml)
          expect(Kucodiff.diff(['a.yml', 'b.yml'], indent_pod: true)).to eq("a.yml-b.yml" => [
            "spec.template.foo",
          ])
        end
      end
    end
  end

  describe "readme example" do
    eval(File.read('Readme.md')[/describe .*^end$/m])
  end

  describe ".flat_hash" do
    it "flattens an empty hash" do
      expect(Kucodiff.send(:flat_hash, {})).to eq({})
    end

    it "flattens a simple hash" do
      expect(Kucodiff.send(:flat_hash, "foo" => "bar")).to eq("foo" => "bar")
    end

    it "flattens a nested hash" do
      expect(Kucodiff.send(:flat_hash, "foo" => {"bar" => {"baz" => "boing"}})).to eq("foo.bar.baz" => "boing")
    end

    it "flattens an array" do
      expect(Kucodiff.send(:flat_hash, "foo" => [{"bar" => "baz"}, {"baz" => "boing"}])).to eq(
        "foo.0.bar" => "baz", "foo.1.baz" => "boing"
      )
    end
  end

  describe ".hashify_container_env!" do
    it "leaves non containers alone" do
      input = {}
      Kucodiff.send(:hashify_container_env!, input)
      expect(input).to eq({})
    end

    it "converts container env to a hash for readable diffs" do
      input = {"spec" => {"template" => {"spec" => {"containers" => [
        {"env" => [{"name" => "a", "value" => "b"}]},
        {"env" => [{"name" => "c", "valueFrom" => "d"}]},
      ]}}}}
      Kucodiff.send(:hashify_container_env!, input)
      expect(input).to eq(
        "spec" => {"template" => {"spec" => {"containers" => [
          {"env" => {"a" => "b"}},
          {"env" => {"c" => "d"}},
        ]}}}
      )
    end
  end
end
