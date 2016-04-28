# GraphAnno

GraphAnno is a browser-based and command line-operated tool for creating, editing and querying graph-based linguistic annotations.

GraphAnno needs: Ruby (optional on Windows) and a Browser.

## Installation

In order to run GraphAnno you need:

1. Ruby (you can do without on Windows)
  * (http://www.ruby-lang.org/; GraphAnno has been developed with version 2.0; but 1.9 should work, too)

    install needed Rubygems with bundler (if necessary, run `gem install bundler` before):
    1. navigate to the GraphAnno main directory
    2. run `bundle install`

  * For Windows there is a compiled version of the program for which you don't need Ruby.

2. A browser (GraphAnno has been developed with Firefox, but Chrome should work, too)

(A note: you don’t need Graphviz anymore – it is now included in GraphAnno as a Javascript version.)


## Getting started

### Starting the program

1. start `main.rb` in GraphAnno main directory (`bundle exec ruby main.rb`), or `main.exe` on Windows

2. navigate to the following address in your browser: `http://localhost:4567/`

You now see the GraphAnno user interface: the (at first empty) graph panel, and the commandline with dropdowns for layer and sentence on the bottom.

(To stop the program, press ctrl + C in the console where it is running)

### Entering and annotating data

You start with an empty working space, so the first thing to do is to create a sentence. Type the "new sentence" command `ns` with the name of your first sentence, e.g.
```
ns example_1
```
The sentence is created and you have moved to it, which you see by looking at the sentence dropdown.

Now enter the sentence you want to annotate with the command `t` for tokenize:
```
t I deleted it .
```
The words are split at the spaces and appear as numbered tokens on the screen. Let's assume we have forgotten a word – we can still insert it with the `ta` command. It takes as arguments the token after which to insert and the word(s) to insert (the corresponding command for inserting *before* the given token is `tb`):
```
ta t0 quickly
```
This results in the sentence "I quickly deleted it." If you want to append words at the end of the sentence, just use `t` again.

You can annotate the tokens (as well as other nodes and edges) using the command `a` followed by a mixture of identifiers (t0, t1 ...) and key-value pairs. Annotate the two pronouns in our example with their part of speech tag like this:
```
a t0 t2 pos:PNP
```
Annotations can be removed by giving the key without value, i.e., for undoing the above command, you may type:
```
a t0 t2 pos:
```

### Building structure

Now let's build some structure. The command `p` creates a parent node for the nodes given as arguments. Annotations for the new node can be given as well (the "cat" attribute is privileged insofar as it is displayed on top of all other annotations, without the key):
```
p t2 t3 cat:VP
```
If you want to specify series of consecutively numbered elements, you may use two dots like this:
```
p t1..t3
```
The last node obviously makes no sense, so we delete it using the command `d`:
```
d n1
```

You may also create free nodes with `n`, e.g.:
```
n cat:S
```
And single edges with `e`, specifying start and end node (and, of course, optionally some annotation):
```
e n1 t0 role:subj
```
GraphAnno is not confined to trees, so you could add a child node (command `c`) to the S and VP nodes of our graph (just for the purpose of demonstration, in this case):
```
c n1 n0
```



### Further reading

For more information, please see the documentation located in the `doc` directory (complete version up to now only available in German; English version is work in progress).
