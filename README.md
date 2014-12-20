# GraphAnno

GraphAnno is a browser-based and command line-operated tool for creating, editing and querying graph-based linguistic annotations.

GraphAnno needs: Ruby (optional on Windows), Graphviz, and a Browser (Firefox).

## Installation

In order to run GraphAnno you need:

1. An installation of Graphviz (http://www.graphviz.org/)

2. **On all OSs**: Ruby (http://www.ruby-lang.org/; GraphAnno has been developed with version 2.0; but 1.9 should work, too);
  install needed Rubygems with bundler (if necessary, run `gem install bundler` before):
  1. navigate to the GraphAnno main directory
  2. run `bundle install`
  
  **For Windows** there is a compiled version of the program for which you don't need Ruby.

3. A browser (GraphAnno has been developed with Firefox, it has not been checked whether it works just as well on other browsers)


## Starting the program

1. start `main.rb` in GraphAnno main directory (`bundle exec ruby main.rb`), or `main.exe` on Windows

2. navigate to the following address in your browser: `http://localhost:4567/`


## Usage

For how to use GraphAnno, please see the documentation located in the `doc` directory (up to now only available in German).