# Dagger
  
Dagger is a tool for modeling your workflows as data that can be composed together at runtime.

Dagger constructs can be integrated into a Dagger.Workflow and evaluated lazily in concurrent contexts.

Dagger Workflows are a decorated dataflow graph (a DAG - "directed acyclic graph") of your code that can model your rules, pipelines, and state machines.

Basic data flow dependencies such as in a pipeline are modeled as %Step{} structs (nodes/vertices) in the graph with directed edges (arrows) between steps.

Steps can be thought of as a simple input -> output lambda function.

As Facts are fed through a workflow, various steps are traversed to as needed and activated producing more Facts.

Beyond steps, Dagger has support for Rules and Accumulators for conditional and stateful evaluation.

Together this enables Dagger to express complex decision trees, finite state machines, data pipelines, and more.

The Dagger.Flowable protocol is what allows for extension of Dagger and composability of structures like Workflows, Steps, Rules, and Accumulators by allowing user defined structures to be integrated into a `Dagger.Workflow`.


## Example Text Processing Pipeline

```elixir
require Dagger

text_processing_pipeline =
  Dagger.workflow(
    name: "basic text processing example",
    steps: [
      {Dagger.step(name: "tokenize", work: &TextProcessing.tokenize/1),
       [
         {Dagger.step(name: "count words", work: &TextProcessing.count_words/1),
          [
            Dagger.step(name: "count unique words", work: &TextProcessing.count_uniques/1)
          ]},
         Dagger.step(name: "first word", work: &TextProcessing.first_word/1),
         Dagger.step(name: "last word", work: &TextProcessing.last_word/1)
       ]}
    ]
  )
```

The text processing workflow above builds a graph that looks like this
![text-pipeline.svg](https://raw.githubusercontent.com/zblanco/dagger/1c911238aa4f0e6ad3a71bf54e722ce153b603d9/text-processing-pipeline.svg)

The way we can run this is by starting at the top, the root, and following the arrows down to identify the next step(s) to run with some input. The data flows down the graph following the arrows until it reaches the end satisfying all steps for the data input.

Dagger also supports rules. Rules are ways of constraining when to execute a step.

## Rules

```elixir
when_42_rule =
  Dagger.rule(
    fn item when is_integer(item) and item > 41 and item < 43 ->
      Enum.random(1..10)
    end,
    name: "when 42 random"
  )
```

The rule above is then tranformed into a workflow that looks like this

![when_42_rule.svg](https://raw.githubusercontent.com/zblanco/dagger/26763fc0e88cc17e3fe0912eec8b634afbb0913a/when_42_rule.svg)

This graph representation of the rule above is now composable with other rules or pipelines to be executed together
as concurrently or lazily as desired.

So we can build another workflow with both this rule and another.

```elixir
composed_workflow =
  Dagger.workflow(
    name: "composition of rules example",
    rules: [
      Dagger.rule(
        fn
          :potato -> "potato!"
        end,
        name: "is it a potato?"
      ),
      Dagger.rule(
        fn item when is_integer(item) and item > 41 and item < 43 ->
          Enum.random(1..10)
        end,
        name: "when 42 random"
      )
    ]
  )
```

Our `composed_workflow` of those two rules now looks like this

![composed_workflow.svg](https://raw.githubusercontent.com/zblanco/dagger/8f302e6c62c7f69519c13d9c434533b59449598e/composed_workflow.svg)

You'll notice on the left side of the image we have our workflow with three conditions joined by conjunctions (AND) with an additional branch containing our potato rule.

Now we can provide an input to our workflow such as `:potato` or `43` and see how the workflow reacts.

<!-- livebook:{"force_markdown":true} -->

```elixir
composed_workflow
|> Workflow.plan_eagerly(:potato)
|> Workflow.next_runnables()

# result
[
  {%Dagger.Workflow.Step{
     hash: 1036416829,
     name: "name-1036416829",
     work: #Function<44.40011524/1 in :erl_eval.expr/5>
   },
   %Dagger.Workflow.Fact{ancestry: nil, hash: 125216943, runnable: nil, type: nil, value: :potato}}
]
```

Here we asked the workflow to plan i.e. 'find out' if there's any work to do, since our potato rule
matches on `:potato`, our input, it responded by saying that we can execute a step to return the left hand
side of the rule: `"potato!"`.

So now lets execute the workflow all the way through.

<!-- livebook:{"force_markdown":true} -->

```elixir
composed_workflow
|> Workflow.plan_eagerly(:potato) # identify the work to do by checking conditions closer to the root
|> Workflow.react() # execute a phase of runnables found by planning
|> Workflow.reactions() # list the facts produced from the phase of reactions

# result
[
  %Dagger.Workflow.Fact{
    ancestry: {1036416829, 125216943},
    hash: 3112435556,
    runnable: {%Dagger.Workflow.Step{
       hash: 1036416829,
       name: "name-1036416829",
       work: #Function<44.40011524/1 in :erl_eval.expr/5>
     },
     %Dagger.Workflow.Fact{ancestry: nil, hash: 125216943, runnable: nil, type: nil, value: :potato}},
    value: "potato!"
  }
]

```

<!-- livebook:{"break_markdown":true} -->

Two things to note here:

1. We can see the runnable and the ancestry of the `(work, input)` pair that produced the fact.

2. We see the intended result value of our potato rule: `"potato!"`

### Disclaimers

Dagger is in early/active development and the apis are not stable. Use Dagger in production at your own risk.

Dagger is a high level abstraction that brings your business logic expression into runtime modification. That means you don't get the same compile-time
guarantees and it adds a layer of complexity. I don't recommend using Dagger when you can write compiled code to the same effect. 

**Do Not** allow users to write and execute arbitrary Elixir code on a machine running Dagger, or using the `Code` modules in Elixir. Instead wrap and hide 
these sorts of capabilities behind an interface such as a DSL, or a gui.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dagger` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dagger, github: "zblanco/dagger", branch: "master"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/dagger](https://hexdocs.pm/dagger).

