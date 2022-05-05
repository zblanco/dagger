# Notes

## Runnable Protocol

The purpose of the runnable protocol is to allow compositions of work to be given inputs and be decomposed until the atomic tuple of {work_func, raw_input} is reached.

The protocol allows for a polymorphism of how different datastructures compose work functions and follow a lazy execution path where no actual execution of work
is completed until an atomic is reached.

The runnable protocol idea is somewhat at odds with the state monad where all executions are wrapped in state transformations of some entity (Rete/Workflow struct). 

It's possible the runnable protocol is something we can use to not depend on a `Workflow` datastructure a lone, but support basic step-wise pipelines, lists of work,
streams, etc.

Not 100% sure where this path is going, but the idea potentially connects with "continuations" and non-terminating/delegated evaluation at runtime where a step
    instead of returning the fact immediately returns more work to do which is contracted to eventually return the original runnable's fact obligation.

## The Workflow Agenda

The Agenda is a list or priority queue of Runnables.

Each element in the agenda can be run via the Runnable protocol.

It's the `Runner`'s job to handle the execution context of the Runnable.

## Basics

* Dataflow Graph (DAG) expressing relations between functions wrapped in decorated nodes
* Construction & Evaluation separation
* Lazy evaluation (work to do is returned and executed in a chosen context by the Runner rather than executed eagerly)