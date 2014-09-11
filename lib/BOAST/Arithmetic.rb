module BOAST
  module Arithmetic

    def ===(x)
      return Expression::new(Affectation,self,x)
    end

    def !
      return Expression::new(Not,nil,self)
    end

    def ==(x)
      return Expression::new("==",self,x)
    end

    def !=(x)
      return Expression::new(Different,self,x)
    end

    def >(x)
      return Expression::new(">",self,x)
    end
 
    def <(x)
      return Expression::new("<",self,x)
    end
 
    def >=(x)
      return Expression::new(">=",self,x)
    end
 
    def <=(x)
      return Expression::new("<=",self,x)
    end
 
    def +(x)
      return Expression::new(Addition,self,x)
    end

    def -(x)
      return Expression::new(Substraction,self,x)
    end
 
    def *(x)
      return Expression::new(Multiplication,self,x)
    end

    def /(x)
      return Expression::new(Division,self,x)
    end
 
    def -@
      return Expression::new(Minus,nil,self)
    end

    def address
      return Expression::new("&",nil,self)
    end
   
    def dereference
      return Expression::new("*",nil,self)
    end

  end
end
