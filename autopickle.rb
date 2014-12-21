#!/usr/bin/ruby

root_dir = File.dirname(__FILE__);

require 'json'

class GherkinFunction

	attr_accessor :pattern, :function, :params, :examples

	def initialize(pattern, params)
		backref_pattern = /(?<!\\)(\([^?][^)]+[^\\]\))/
		@pattern = pattern
		names = params.is_a?(Array) ? params : params.split(/\s*,\s*/)
		backrefs = pattern.scan(backref_pattern).to_a.flatten
		@params = backrefs.zip(names)
		@function = unescape_regex_special_chars(@pattern.gsub(/^\^|\$$/, '').gsub(backref_pattern, "%s") % names.map{|n| '{'+n+'}' })
		@examples = []
	end

	def matches(str)
		return str.match(@pattern)
	end

	def matches_function(str)
		return @function.downcase.include? str.downcase
	end

	def unescape_regex_special_chars(str)
		map = Hash.new { |hash,key| key } # simple trick to return key if there is no value in hash
		map['t'] = "\t"
		map['n'] = "\n"
		map['r'] = "\r"
		map['f'] = "\f"
		map['v'] = "\v"

		return str.gsub(/\\(.)/){ map[$1] }
	end

	def to_s
		return @function
	end

	def to_json
		return "{
  \"pattern\":\"#{@pattern.gsub(/\\([^\\])/, '\\\\\\\\\1').gsub('"', '\\"')}\",
  \"function\":\"#{@function.gsub(/\\([^\\])/, '\1').gsub('"', '\\"')}\",
  \"params\":#{JSON.dump(@params)},
  \"examples\":#{@examples}
}"
	end

	def help
		help = self.to_s
		if @params.length > 0
			help += "\n" + examples.map { |example| "\tExample: "+example }.join("\n")
		end
		return help
	end

end

class GherkinDictionary

	attr_accessor :terms

	def initialize(path_or_array)
		@terms = []
		@files = []
		@example_files = []
		if path_or_array.is_a?(Array)
			@terms = path_or_array	# Construct new dictionary from an existing array of terms
		elsif path_or_array.is_a?(String) && Dir.exists?(path_or_array)
			init_from_path(path_or_array)	# else populate by parsing a directory full of step_definition and feature files 
			load_examples_from_path(path_or_array)
			dedupe_examples
		end
	end

	def init_from_path(path)
		#files = Dir[path+"/**/errCode.rb"]
		files = Dir[path+"/**/*.rb"]
		files.each { |file| load_from_file(file) }
	end

	def load_from_file(file)
		File.open(file).each do |line|
			# When(/^I type link in "(.*?)"$/) do |arg1|
			if matches = line.match(/^(given|when|then|and|but)\s*\(\s*\/(\^?[^$]*\$?)\/\s*\)\s*(?:(?:do|{)\s*\|?([^|]*)\|?)/i)
				@terms.push(GherkinFunction.new(matches[2], matches[3])) 
			end
		end
	end

	def load_examples_from_path(path)
		#example_files = Dir[path+"/**/errCode.feature"]
		example_files = Dir[path+"/**/*.feature"]
		example_files.each { |file|
			load_examples_from_file(file)
		}
	end

	def load_examples_from_file(file)
		File.open(file).each do |line|
			if matches = line.match(/^\s*(?:given|when|then|and|but)\s*(.*)/i)
				set_example(matches[1])
			end
		end
	end

	def add(new_term)
		@terms.push(new_term)
	end

	def set_example(example)
		@terms.each do |entry|
			if example.match(entry.pattern) && example.downcase != entry.function
				entry.examples.push(example)
			end
		end
	end

	def dedupe_examples
		@terms.each { |entry| entry.examples = entry.examples.uniq }
	end

	def find_terms(str)
		return self.class.new(@terms.select { |term| term.matches_function(str) })
	end

	def [](index)
		return @terms[index]
	end

	def length
		return @terms.length
	end

	def to_s
		return @terms.map { |term| term.to_s }.join("\n")
	end

	def to_json
		return '[' + @terms.map { |term| term.to_json }.join(",\n") + ']'
	end

	def help
		return @terms.map { |term| term.help }.join("\n")
	end
end


if(ARGV[0])
	require File.join(root_dir, 'local-config')
	dictionary = GherkinDictionary.new(GHERKIN_ROOT_DIR)
	results = dictionary.find_terms(ARGV[0])
	if results.length == 0
		puts " -- No results found -- "
	elsif !ARGV[1].nil?
		if ARGV[1] == '--json'
			puts results.to_json
		elsif ARGV[1] == '--raw'
			puts results.to_s
		elsif ARGV[1] == '--help'
			puts results.help
		end
	else
		puts results.to_s
	end
end
