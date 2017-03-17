# GraphAnno

GraphAnno is a browser-based and command line-operated tool for creating, editing and querying graph-based linguistic annotations.

GraphAnno needs: Ruby (not required on Windows) and a Browser (GraphAnno has been developed with Firefox, but Chrome should work, too).


## Installation

Download the ZIP file and extract it to a directory of your choice (or clone the GraphAnno repository).

Then, depending on your system:

* On Windows: simply use the binary file `main.exe` located in GraphAnno’s main directory, or follow the following instructions if you want to use the Ruby version.

* On Linux or OS X: install the needed Rubygems:

	1. navigate to the GraphAnno main directory,

	2. run `gem install bundler` if you haven't installed Bundler already,

	3. run `bundle install` if you have installed compilation tools (this is usually the case on Linux systems) or `bundle install --without=compile` if you haven’t. (In the latter case you won’t be able to use the media playback feature.)


### Running the program

1. start `main.rb` in the GraphAnno main directory with the command `bundle exec ruby main.rb`; or on Windows `main.exe`

2. navigate to the following address in your browser: `http://localhost:4567/`

To stop the program, press ctrl + C in the console where it is running.


## Documentation

Read the [documentation](doc/GraphAnno-Documentation_en.pdf) for a full overview of GraphAnno's functionality. For a quick introduction see the following section.


## Getting started

### Entering and annotating data

When you have started GraphAnno and opened it in your browser, you see the (at first empty) graph panel and the command line with dropdowns for layer and sentence on the bottom.

You start with an empty work space, so the first thing to do is to create a sentence. Type the "new sentence" command `ns` with the name of your first sentence, e.g.
```
ns example_1
```
The sentence is created and you have moved to it, which you see by looking at the navigation window (toggle it with F9).

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
