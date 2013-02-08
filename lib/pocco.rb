#!/usr/bin/env ruby

require 'rubygems'
require 'rocco'

# Reopen rocco and put in some Puppet specific hacks.
class Rocco
  def split(sections)
    docs_blocks, code_blocks = [], []
    sections.each do |docs,code|
      header = []
      params = []
      usages = []
      process = false

      code_blocks << code.map do |line|
        container, name = parse_header(line)
        if container
          process = true
          header << ["### #{container.capitalize}: #{name}", ""]
          usages = test_file
        else
          param = parse_params(line)
          if process and param
            default = "(default: #{param[:default]})" if param[:default]
            params.push " * [*#{param[:name]}*]: #{param[:comment]} #{default}"
            line = param[:line]
          else
            process = false
          end
        end
        tabs = line.match(/^(\t+)/)
        tabs ? line.sub(/^\t+/, '  ' * tabs.captures[0].length) : line
      end.join("\n")
      params =  ["### Parameters:", ""] + params + [""] unless params.empty?
      docs = header + docs + params + usages
      docs_blocks << docs.join("\n")
    end
    [docs_blocks, code_blocks]
  end

  def test_file
    usages = []
    test_file = @file.gsub(/manifests\//, 'tests/')
    if File.exists? test_file
      usages = File.read(test_file).split("\n")
      usages = usages.collect{|line| "    #{line}"}
      usages = ["### Usage:", ""] + usages + [""]
    end
    usages
  end

  def parse_header(line)
    [ $1, $2 ] if line =~ /^\s*(class|define)\s+([\S]+?)\s*[\{\(]/
  end

  def parse_params(line)
    if line =~ /^\s*\$(\w+)/
      line, comment = line.split('#:')
      line =~ /^\s*\$(\S+)\s*[=]?\s*(\S+)?\s*/

      { :name    => $1.chomp(','),
        :default => ($2 || '').chomp(','),
        :comment => comment,
        :line    => line,
      }
    end
  end

end

class Rocco::Layout < Mustache

  def sources
    currentpath = Pathname.new( File.dirname( @doc.file ) )
    @doc.sources.sort.map do |source|
      htmlpath = Pathname.new( source.sub( Regexp.new( "#{File.extname(source)}$"), ".html" ) )
      {
        :path       => source,
        :basename   => File.basename(source),
        :url        => htmlpath.relative_path_from( currentpath )
      }
    end
  end

end

class Pocco
  def initialize(module_path, options={})
    if module_path[-1, 1] != '/'
      module_path += '/'
    end
    puts module_path
    @sources = Dir.glob(File.join(module_path, '**/*.pp'))
    # puts "Found files... #{@sources.collect { |source| source = source.split('/')[-1] }.join(', ') }\n"
    @options = options
    @module_path = module_path
  end

  def generate
    # Destination is @module_path/docs
    dest_dir = File.expand_path(@module_path + "docs")
    FileUtils.mkdir_p(dest_dir) unless File.directory? dest_dir

    @sources.each do |source_file|

      # maintain directory structure copying parent directory
      type_dir = File.dirname(source_file).split(@module_path)[-1]

      # default file path is the destination directory
      file_path = dest_dir.clone

      # Create directory for this type
      if type_dir != dest_dir.split('/')[-1]
        file_path += "/" + type_dir
        FileUtils.mkdir_p(file_path) unless File.directory? file_path
      end

      # Generate destination file path and name
      dest_file = file_path + "/" + File.basename(source_file).sub(Regexp.new("#{File.extname(source_file)}$"), ".html")

      # run the source file through modified Rocco
      rocco = Rocco.new(source_file, @sources.to_a, @options)
      # save documents to file system
      File.open(dest_file, 'wb') { |fd| fd.write(rocco.to_html) }
    end

    return dest_dir

  end
end
