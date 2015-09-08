module BOAST

  module FFIRuntime

    def target
      return library_path
    end

    def target_depends
      return [ library_object ]
    end

    def target_sources
      return [ library_source ]
    end

    def load_module
      create_ffi_module
    end

    def create_sources
      create_library_source
    end

    def create_ffi_module
      s =<<EOF
      require 'ffi'
      require 'narray_ffi'
      module #{module_name}
        extend FFI::Library
        ffi_lib "#{library_path}"
        attach_function :#{method_name}, [ #{@procedure.parameters.collect{ |p| ":"+p.decl_ffi.to_s }.join(", ")} ], :#{@procedure.properties[:return] ? @procedure.properties[:return].type.decl_ffi : "void" }
        def run(*args)
          if args.length < @procedure.parameters.length or args.length > @procedure.parameters.length + 1 then
            raise "Wrong number of arguments for \#{@procedure.name} (\#{args.length} for \#{@procedure.parameters.length})"
          else
            ev_set = nil
            if args.length == @procedure.parameters.length + 1 then
              options = args.last
              if options[:PAPI] then
                require 'PAPI'
                ev_set = PAPI::EventSet::new
                ev_set.add_named(options[:PAPI])
              end
            end
            t_args = []
            r_args = {}
            if @lang == FORTRAN then
              @procedure.parameters.each_with_index { |p, i|
                if p.decl_ffi(true) != :pointer then
                  arg_p = FFI::MemoryPointer::new(p.decl_ffi(true))
                  arg_p.send("write_\#{p.decl_ffi(true)}",args[i])
                  t_args.push(arg_p)
                  r_args[p] = arg_p if p.scalar_output?
                else
                  t_args.push( args[i] )
                end
              }
            else
              @procedure.parameters.each_with_index { |p, i|
                if p.scalar_output? then
                  arg_p = FFI::MemoryPointer::new(p.decl_ffi(true))
                  arg_p.send("write_\#{p.decl_ffi(true)}",args[i])
                  t_args.push(arg_p)
                  r_args[p] = arg_p
                else
                  t_args.push( args[i] )
                end
              }
            end
            results = {}
            counters = nil
            ev_set.start if ev_set
            begin
              start = Time::new
              ret = #{method_name}(*t_args)
              stop = Time::new
            ensure
              if ev_set then
                counters = ev_set.stop
                ev_set.cleanup
                ev_set.destroy
              end
            end
            results = { :start => start, :stop => stop, :duration => stop - start, :return => ret }
            results[:PAPI] = Hash[[options[:PAPI]].flatten.zip(counters)] if ev_set
            if r_args.length > 0 then
              ref_return = {}
              r_args.each { |p, p_arg|
                ref_return[p.name.to_sym] = p_arg.send("read_\#{p.decl_ffi(true)}")
              }
              results[:reference_return] = ref_return
            end
            return results
          end
        end
      end
EOF
      BOAST::class_eval s
    end

  end

end