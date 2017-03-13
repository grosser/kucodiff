Smart diff for kubernetes configs to ensure symmetric configuration.

Projects that deploy very similar components like a worker and server,
often should only have a very small diff, Kucodiff ensures that no accidental diff is introduced.

Install
=======

```Bash
gem install kucodiff
```

Usage
=====

```Ruby
require 'kucodiff'
require 'minitest/autorun'

describe "kubernetes configs" do
  it "has a small diff" do
    expect(
      Kucodiff.diff(
        Dir["kubernetes/**/*.{yml,json}"], 
        ignore: /\.(command|limits|requests)\./, 
        expected: {
          "kubernetes/console.yml-kubernetes/server.yml" => %w[
            metadata.name
            spec.template.metadata.labels.proxy
            spec.template.spec.containers.0.env.PORT
          ],
          "kubernetes/console.yml-kubernetes/worker.yml" => %w[
            metadata.name
            spec.template.spec.containers.0.env.QUEUE
          ]
        }
      )
    ).to eq({})
  end
end
```

TODO
====
 - pick first Job/Deployment/DaemonSet to diff and not just first element

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/kucodiff.png)](https://travis-ci.org/grosser/kucodiff)
