module BOAST

  class OperatorError < Error
  end

  class Operator
    extend PrivateStateAccessor
    extend Intrinsics

    DISCARD_OPTIONS = { :const => nil, :constant => nil, :direction => nil, :dir => nil, :align => nil }

    def Operator.inspect
      return "#{name}"
    end

    def Operator.convert(arg, type)
      return "convert_#{type.decl}( #{arg} )" if lang == CL

      path = get_conversion_path(type, arg.type)
      s = "#{arg}"
      if path.length > 1 then
        path.each_cons(2) { |slice|
          instruction = intrinsics_by_vector_name(:CVT, slice[1], slice[0])
          s = "#{instruction}( #{s} )"
        }
      end
      return s
    end

  end

  class BasicBinaryOperator < Operator

    def BasicBinaryOperator.string(arg1, arg2, return_type)
      if lang == C and (arg1.class == Variable and arg2.class == Variable) and (arg1.type.vector_length > 1 or arg2.type.vector_length > 1) then
        instruction = intrinsics(intr_symbol, return_type.type)
        a1 = convert(arg1, return_type.type)
        a2 = convert(arg2, return_type.type)
        return "#{instruction}( #{a1}, #{a2} )"
      else
        return basic_usage( arg1, arg2 )
      end
    end

  end

  class Different < Operator

    def Different.string(arg1, arg2, return_type)
      return basic_usage(arg1, arg2)
    end

    def Different.basic_usage(arg1, arg2)
      return "#{arg1} /= #{arg2}" if lang == FORTRAN
      return "#{arg1} != #{arg2}"
    end

  end

  class And < Operator

    def And.string(arg1, arg2, return_type)
      return basic_usage(arg1, arg2)
    end

    def And.basic_usage(arg1, arg2)
      return "(#{arg1}) .and. (#{arg2})" if lang == FORTRAN
      return "(#{arg1}) && (#{arg2})"
    end

  end

  class Or < Operator

    def Or.string(arg1, arg2, return_type)
      return basic_usage(arg1, arg2)
    end

    def Or.basic_usage(arg1, arg2)
      return "(#{arg1}) .or. (#{arg2})" if lang == FORTRAN
      return "(#{arg1}) || (#{arg2})"
    end

  end

  class Affectation < Operator

    def Affectation.string(arg1, arg2, return_type)
      if arg1.class == Variable and arg1.type.vector_length > 1 then
        return "#{arg1} = #{Load(arg2, arg1)}"
      elsif arg2.class == Variable and arg2.type.vector_length > 1 then
        return "#{Store(arg1, arg2, return_type)}"
      end
      return basic_usage(arg1, arg2)
    end

    def Affectation.basic_usage(arg1, arg2)
      return "#{arg1} = #{arg2}"
    end

  end

  class Multiplication < BasicBinaryOperator

    class << self

      def symbol
        return "*"
      end

      def intr_symbol
        return :MUL
      end

      def basic_usage(arg1, arg2)
        return "(#{arg1}) * (#{arg2})" 
      end
  
    end

  end

  class Addition < BasicBinaryOperator

    class << self

      def symbol
        return "+"
      end

      def intr_symbol
        return :ADD
      end
  
      def basic_usage(arg1, arg2)
        return "#{arg1} + #{arg2}" 
      end
  
    end

  end

  class Substraction < BasicBinaryOperator

    class << self

      def symbol
        return "-"
      end

      def intr_symbol
        return :SUB
      end
  
      def basic_usage(arg1, arg2)
        return "#{arg1} - (#{arg2})" 
      end
  
    end

  end

  class Division < BasicBinaryOperator

    class << self

      def symbol
        return "/"
      end

      def intr_symbol
        return :DIV
      end
  
      def basic_usage(arg1, arg2)
        return "(#{arg1}) / (#{arg2})" 
      end
  
    end

  end

  class Minus < Operator

    def Minus.string(arg1, arg2, return_type)
      return " -(#{arg2})"
    end

  end

  class Plus < Operator

    def Plus.string(arg1, arg2, return_type)
      return " +#{arg2}"
    end

  end

  class Not < Operator

    def Not.string(arg1, arg2, return_type)
      return " .not. (#{arg2})" if lang == FORTRAN
      return " !(#{arg2})"
    end

  end

  class Set < Operator
    extend Functor
    include Intrinsics
    include Arithmetic
    include Inspectable
    include PrivateStateAccessor

    attr_reader :source
    attr_reader :return_type

    def initialize(source, return_type)
      @source = source
      @return_type = return_type
    end

    def type
      return @return_type.type
    end

    def to_var
      if lang == C or lang == CL and @return_type.type.vector_length > 1 then
        if @source.kind_of?( Array ) then
          raise OperatorError,  "Invalid array length!" unless @source.length == @return_type.type.vector_length
          return @return_type.copy("(#{@return_type.type.decl})( #{@source.join(", ")} )", DISCARD_OPTIONS) if lang == CL

          begin
            instruction = intrinsics(:SET, @return_type.type)
            return @return_type.copy("#{instruction}( #{@source.join(", ")} )",  DISCARD_OPTIONS)
          rescue IntrinsicsError
            instruction = intrinsics(:SET_LANE, @return_type.type)
            s = Set(0, @return_type).to_s
            @source.each_with_index { |v,i|
              s = "#{instruction}(#{v}, #{s}, #{i})"
            }
            return @return_type.copy(s, DISCARD_OPTIONS)
          end
        elsif @source.class != Variable or @source.type.vector_length == 1 then
          return @return_type.copy("(#{@return_type.type.decl})( #{@source} )", DISCARD_OPTIONS) if lang == CL

          instruction = intrinsics(:SET1, @return_type.type)
          return @return_type.copy("#{instruction}( #{@source} )", DISCARD_OPTIONS)
        elsif @return_type.type != @source.type
          return @return_type.copy("#{Operator.convert(@source, @return_type.type)}", DISCARD_OPTIONS)
        end
      end
      return @return_type.copy("#{@source}", DISCARD_OPTIONS)
    end

    def to_s
      return to_var.to_s
    end

    def pr
      s=""
      s += indent
      s += to_s
      s += ";" if [C, CL, CUDA].include?( lang )
      output.puts s
      return self
    end

  end

  class Load < Operator
    extend Functor
    include Intrinsics
    include Arithmetic
    include Inspectable
    include PrivateStateAccessor

    attr_reader :source
    attr_reader :return_type

    def initialize(source, return_type)
      @source = source
      @return_type = return_type
    end

    def type
      return @return_type.type
    end

    def to_var
      if lang == C or lang == CL then
        if @source.kind_of?(Array) then
          return Set(@source, @return_type).to_var
        elsif @source.class == Variable or @source.respond_to?(:to_var) then
          if @source.to_var.type == @return_type.type
            return @source.to_var
          elsif @source.to_var.type.vector_length == 1 then
            a2 = "#{@source}"
            if a2[0] != "*" then
              a2 = "&" + a2
            else
              a2 = a2[1..-1]
            end
            return @return_type.copy("vload#{@return_type.type.vector_length}(0, #{a2})", DISCARD_OPTIONS) if lang == CL
            return @return_type.copy("_m_from_int64( *((int64_t * ) #{a2} ) )", DISCARD_OPTIONS) if get_architecture == X86 and @return_type.type.total_size*8 == 64
            if @source.alignment == @return_type.type.total_size then
              instruction = intrinsics(:LOADA, @return_type.type)
            else
              instruction = intrinsics(:LOAD, @return_type.type)
            end
            return @return_type.copy("#{instruction}( #{a2} )", DISCARD_OPTIONS)
          else
            return @return_type.copy("#{Operator.convert(@source, @return_type.type)}", DISCARD_OPTIONS)
          end
        end
      end
      return @return_type.copy("#{@source}", DISCARD_OPTIONS)
    end

    def to_s
      return to_var.to_s
    end

    def pr
      s=""
      s += indent
      s += to_s
      s += ";" if [C, CL, CUDA].include?( lang )
      output.puts s
      return self
    end

  end

  class MaskLoad < Operator
    extend Functor
    include Intrinsics
    include Arithmetic
    include Inspectable
    include PrivateStateAccessor

    attr_reader :source
    attr_reader :mask
    attr_reader :return_type

    def initialize(source, mask, return_type)
      @source = source
      @mask = mask
      @return_type = return_type
    end

    def get_mask
      raise OperatorError,  "Mask size is wrong: #{@mask.length} for #{@return_type.type.vector_length}!" if @mask.length != @return_type.type.vector_length
      return Load(@mask.collect { |m| ( m and m != 0 )  ? -1 : 0 }, Int("mask", :size => @return_type.type.size, :vector_length => @return_type.type.vector_length ) )
    end

    private :get_mask

    def type
      return @return_type.type
    end

    def to_var
      raise OperatorError,  "Cannot load unknown type!" unless @return_type
      raise LanguageError,  "Unsupported language!" unless lang == C
      instruction = intrinsics(:MASKLOAD, @return_type.type)
      s = ""
      src = "#{@source}"
      if src[0] != "*" then
        src = "&" + src
      else
        src = src[1..-1]
      end
      p_type = @return_type.type.copy(:vector_length => 1)
      s += "#{instruction}((#{p_type.decl} * )#{src}, #{get_mask})"
      return @return_type.copy( s, DISCARD_OPTIONS)
    end

    def to_s
      return to_var.to_s
    end

    def pr
      s=""
      s += indent
      s += to_s
      s += ";" if [C, CL, CUDA].include?( lang )
      output.puts s
      return self
    end

  end

  class Store < Operator
    extend Functor
    include Intrinsics
    include Arithmetic
    include Inspectable
    include PrivateStateAccessor

    attr_reader :dest
    attr_reader :source
    attr_reader :store_type

    def initialize(dest, source, mask, store_type = nil)
      @dest = dest
      @source = source
      @store_type = store_type
      @store_type = source unless @store_type
    end

    def to_s
      if lang == C or lang == CL then
        dst = "#{@dest}"
        if dst[0] != "*" then
          dst = "&" + dst
        else
          dst = dst[1..-1]
        end

        return "vstore#{@source.type.vector_length}(#{@source}, 0, #{dst})" if lang == CL
        return "*((int64_t * ) #{dst}) = _m_to_int64( #{@source} )" if get_architecture == X86 and @source.type.total_size*8 == 64

        if @dest.alignment == @source.type.total_size then
          instruction = intrinsics(:STOREA, @source.type)
        else
          instruction = intrinsics(:STORE, @source.type)
        end
        p_type = @source.type.copy(:vector_length => 1)
        p_type = @source.type if get_architecture == X86 and @source.type.kind_of?(Int)
        return "#{instruction}( (#{p_type.decl} * ) #{dst}, #{@source} )"
      end
      return Affectation.basic_usage(@dest, @source)
    end

    def pr
      s=""
      s += indent
      s += to_s
      s += ";" if [C, CL, CUDA].include?( lang )
      output.puts s
      return self
    end

  end

  class MaskStore < Operator
    extend Functor
    include Intrinsics
    include Arithmetic
    include Inspectable
    include PrivateStateAccessor

    attr_reader :dest
    attr_reader :source
    attr_reader :mask
    attr_reader :store_type

    def initialize(dest, source, mask, store_type = nil)
      @dest = dest
      @source = source
      @mask = mask
      @store_type = store_type
      @store_type = source unless @store_type
    end

    def get_mask
      raise OperatorError,  "Mask size is wrong: #{@mask.length} for #{@store_type.type.vector_length}!" if @mask.length != @store_type.type.vector_length
      return Load.to_s(@mask.collect { |m| ( m and m != 0 )  ? -1 : 0 }, Int("mask", :size => @store_type.type.size, :vector_length => @store_type.type.vector_length ) )
    end

    private :get_mask

    def to_s
      raise OperatorError,  "Cannot store unknown type!" unless @store_type
      raise LanguageError,  "Unsupported language!" unless lang == C
      instruction = intrinsics(:MASKSTORE, @store_type.type)
      s = ""
      dst = "#{@dest}"
      if dst[0] != "*" then
        dst = "&" + dst
      else
        dst = dst[1..-1]
      end
      p_type = @store_type.type.copy(:vector_length => 1)
      return s += "#{instruction}((#{p_type.decl} * )#{dst}, #{get_mask}, #{Operator.convert(@source, @store_type.type)})"
    end

    def pr
      s=""
      s += indent
      s += to_s
      s += ";" if [C, CL, CUDA].include?( lang )
      output.puts s
      return self
    end

  end

  class FMA < Operator
    extend Functor
    include Intrinsics
    include Arithmetic
    include Inspectable
    include PrivateStateAccessor

    attr_reader :operand1
    attr_reader :operand2
    attr_reader :operand3
    attr_reader :return_type

    def initialize(a,b,c)
      @operand1 = a
      @operand2 = b
      @operand3 = c
      @return_type = nil
      @return_type = @operand3.to_var unless @return_type
    end

    def convert_operand(op)
      return  "#{Operator.convert(op, @return_type.type)}"
    end

    private :convert_operand

    def type
      return @return_type.type
    end

    def to_var
      instruction = nil
      begin
        instruction = intrinsics(:FMADD,@return_type.type)
      rescue
      end
      return (@operand3 + @operand1 * @operand2).to_var unless lang != FORTRAN and @return_type and ( instruction or ( [CL, CUDA].include?(lang) ) )
      op1 = convert_operand(@operand1)
      op2 = convert_operand(@operand2)
      op3 = convert_operand(@operand3)
      if [CL, CUDA].include?(lang)
        ret_name = "fma(#{op1},#{op2},#{op3})"
      else
        case architecture
        when X86
          ret_name = "#{instruction}(#{op1},#{op2},#{op3})"
        when ARM
          ret_name = "#{instruction}(#{op2},#{op3},#{op1})"
        else
          return (@operand1 * @operand2 + @operand3).to_var
        end
      end
      return @return_type.copy( ret_name, DISCARD_OPTIONS)
    end

    def to_s
      return to_var.to_s
    end

    def pr
      s=""
      s += indent
      s += to_s
      s += ";" if [C, CL, CUDA].include?( lang )
      output.puts s
      return self
    end

  end

  class Ternary
    extend Functor
    include Arithmetic
    include Inspectable
    include PrivateStateAccessor

    attr_reader :operand1
    attr_reader :operand2
    attr_reader :operand3
    
    def initialize(x,y,z)
      @operand1 = x
      @operand2 = y
      @operand3 = z
    end

    def to_s
      raise LanguageError,  "Ternary operator unsupported in FORTRAN!" if lang == FORTRAN
      return to_s_c if [C, CL, CUDA].include?( lang )
    end

    def to_s_c
      s = ""
      s += "(#{@operand1} ? #{@operand2} : #{@operand3})"
    end

    def pr
      s=""
      s += indent
      s += to_s
      s += ";" if [C, CL, CUDA].include?( lang )
      output.puts s
      return self
    end

  end

end
