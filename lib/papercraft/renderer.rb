# frozen_string_literal: true

require_relative './html'

module Papercraft
  
  # A Renderer renders a Papercraft component into a string
  class Renderer
  
    class << self

      # Verifies that the given template proc can be called with the given
      # arguments and named arguments. If the proc demands named argument keys
      # that do not exist in `named_args`, `Papercraft::Error` is raised.
      #
      # @param template [Proc] proc to verify
      # @param args [Array<any>] arguments passed to proc
      # @param named_args [Hash] named arguments passed to proc
      def verify_proc_parameters(template, args, named_args)
        param_count = 0
        template.parameters.each do |(type, name)|
          case type
          when :req
            param_count += 1
          when :keyreq
            if !named_args.has_key?(name)
              raise Papercraft::Error, "Missing template parameter #{name.inspect}"
            end
          end
        end
        if param_count > args.size
          raise Papercraft::Error, "Missing template parameters"
        end
      end  
    end

    # Initializes the renderer and evaulates the given template in the
    # renderer's scope.
    #
    # @param &template [Proc] template block
    def initialize(&template)
      @buffer = +''
      instance_eval(&template)
    end

    # Returns the rendered template.
    #
    # @return [String]
    def to_s
      @buffer
    end

    S_TAG_METHOD_LINE = __LINE__ + 1
    S_TAG_METHOD = <<~EOF
      S_TAG_%<TAG>s_PRE = '<%<tag>s'.tr('_', '-')
      S_TAG_%<TAG>s_CLOSE = '</%<tag>s>'.tr('_', '-')

      def %<tag>s(text = nil, **props, &block)
        @buffer << S_TAG_%<TAG>s_PRE
        emit_props(props) unless props.empty?

        if block
          @buffer << S_GT
          instance_eval(&block)
          @buffer << S_TAG_%<TAG>s_CLOSE
        elsif Proc === text
          @buffer << S_GT
          emit(text)
          @buffer << S_TAG_%<TAG>s_CLOSE
        elsif text
          @buffer << S_GT << escape_text(text.to_s) << S_TAG_%<TAG>s_CLOSE
        else
          @buffer << S_SLASH_GT
        end
      end
    EOF

    # Catches undefined tag method call and handles it by defining the method.
    #
    # @param sym [Symbol] HTML tag or component identifier
    # @param args [Array] method arguments
    # @param opts [Hash] named method arguments
    # @param &block [Proc] block passed to method
    # @return [void]
    def method_missing(sym, *args, **opts, &block)
      value = @local && @local[sym]
      return value if value

      tag = sym.to_s
      code = S_TAG_METHOD % { tag: tag, TAG: tag.upcase }
      self.class.class_eval(code, __FILE__, S_TAG_METHOD_LINE)
      send(sym, *args, **opts, &block)
    end

    # Emits the given object into the rendering buffer. If the given object is a
    # proc or a component, `emit` will passes any additional arguments and named
    # arguments to the object when rendering it. If the given object is nil,
    # nothing is emitted. Otherwise, the object is converted into a string using
    # `#to_s` which is then added to the rendering buffer, without any escaping.
    #
    #   greeter = proc { |name| h1 "Hello, #{name}!" }
    #   H { emit(greeter, 'world') }.render #=> "<h1>Hello, world!</h1>"
    #   
    #   H { emit 'hi&<bye>' }.render #=> "hi&<bye>"
    #   
    #   H { emit nil }.render #=> ""
    #
    # @param o [Proc, Papercraft::Component, String] emitted object
    # @param *a [Array<any>] arguments to pass to a proc
    # @param **b [Hash] named arguments to pass to a proc
    # @return [void]
    def emit(o, *a, **b)
      case o
      when ::Proc
        Renderer.verify_proc_parameters(o, a, b)
        instance_exec(*a, **b, &o)
      when nil
      else
        @buffer << o.to_s
      end
    end
    alias_method :e, :emit

    # Emits a block supplied using `Component#apply` or `Component#render`.
    #
    #   div_wrap = H { |*args| div { emit_yield(*args) } }
    #   greeter = div_wrap.apply { |name| h1 "Hello, #{name}!" }
    #   greeter.render('world') #=> "<div><h1>Hello, world!</h1></div>"
    #
    # @param *a [Array<any>] arguments to pass to a proc
    # @param **b [Hash] named arguments to pass to a proc
    # @return [void]
    def emit_yield(*a, **b)
      raise Papercraft::Error, "No block given" unless @inner_block
      
      instance_exec(*a, **b, &@inner_block)
    end
    
    S_LT              = '<'
    S_GT              = '>'
    S_LT_SLASH        = '</'
    S_SPACE_LT_SLASH  = ' </'
    S_SLASH_GT        = '/>'
    S_SPACE           = ' '
    S_EQUAL_QUOTE     = '="'
    S_QUOTE           = '"'

    # Emits text into the rendering buffer, escaping any special characters to
    # the respective HTML entities.
    #
    # @param data [String] text
    # @return [void]
    def text(data)
      @buffer << escape_text(data)
    end

    private

    # Escapes text. This method must be overriden in descendant classes.
    def escape_text(text)
      raise NotImplementedError
    end

    # Sets up a block to be called with `#emit_yield`
    def with_block(block, &run_block)
      old_block = @inner_block
      @inner_block = block
      instance_eval(&run_block)
    ensure
      @inner_block = old_block
    end
  
    # Emits tag attributes into the rendering buffer
    # @param props [Hash] tag attributes
    # @return [void]
    def emit_props(props)
      props.each { |k, v|
        case k
        when :src, :href
          @buffer << S_SPACE << k.to_s << S_EQUAL_QUOTE <<
            EscapeUtils.escape_uri(v) << S_QUOTE
        else
          case v
          when true
            @buffer << S_SPACE << k.to_s.tr('_', '-')
          when false, nil
            # emit nothing
          else
            @buffer << S_SPACE << k.to_s.tr('_', '-') <<
              S_EQUAL_QUOTE << v << S_QUOTE
          end
        end
      }
    end
  end

  # Implements an HTML renderer
  class HTMLRenderer < Renderer
    include HTML

    private

    def escape_text(text)
      EscapeUtils.escape_html(text.to_s)
    end
  end

  # Implements an XML renderer
  class XMLRenderer < Renderer
    private

    def escape_text(text)
      EscapeUtils.escape_xml(text.to_s)
    end
  end
end
