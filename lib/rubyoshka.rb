# frozen_string_literal: true

require 'escape_utils'

require_relative 'rubyoshka/renderer'
require_relative 'rubyoshka/compiler'

# A Rubyoshka is a template representing a piece of HTML
class Rubyoshka
  module Encoding
    def __html_encode__(text)
      EscapeUtils.escape_html(text.to_s)
    end

    def __uri_encode__(text)
      EscapeUtils.escape_uri(text.to_s)
    end
  end  
  
  attr_reader :block

  # Initializes a Rubyoshka with the given block
  # @param ctx [Hash] local context
  # @param block [Proc] nested HTML block
  # @param [void]
  def initialize(mode: :html, **ctx, &block)
    @mode = mode
    @block = ctx.empty? ? block : proc { with(**ctx, &block) }
  end

  H_EMPTY = {}.freeze

  # Renders the associated block and returns the string result
  # @param context [Hash] context
  # @return [String]
  def render(context = H_EMPTY)
    renderer_class.new(context, &block).to_s
  end

  def renderer_class
    case @mode
    when :html
      HTMLRenderer
    when :xml
      XMLRenderer
    else
      raise "Invalid mode #{@mode.inspect}"
    end
  end

  def compile
    Rubyoshka::Compiler.new.compile(self)
  end

  @@cache = {}

  def self.cache
    @@cache
  end

  def self.component(&block)
    proc { |*args| new { instance_exec(*args, &block) } }
  end

  def self.xml(**ctx, &block)
    new(mode: :xml, **ctx, &block)
  end
end
::H = Rubyoshka

# Kernel extensions
module ::Kernel
  # Convenience method for creating a new Rubyoshka
  # @param ctx [Hash] local context
  # @param block [Proc] nested block
  # @return [Rubyoshka] Rubyoshka template
  def H(**ctx, &block)
    Rubyoshka.new(**ctx, &block)
  end
end

# Object extensions
class Object
  include Rubyoshka::Encoding
end
