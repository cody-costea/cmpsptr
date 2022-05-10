/*
Copyright (C) AD 2022 Claudiu-Stefan Costea

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/
module cmpsptr;
import core.stdc.stdio;
import core.stdc.stdint;
import core.stdc.stdlib : free;
import std.container.array : Array;
import std.math.algebraic : abs;
/*
If the COMPRESS_POINTERS enum is set to a non-zero value, 64bit pointers will be compressed into 32bit integers, according to the following options:
    +5 can compress addresses up to 32GB, at the expense of the 4 lower tag bits, which can no longer be used for other purporses
    +4 can compress addresses up to 16GB, at the expense of the 3 lower tag bits, which can no longer be used for other purporses
    +3 can compress addresses up to 8GB, at the expense of the 2 lower tag bits, which can no longer be used for other purporses
    +2 can compress addresses up to 4GB, at the expense of the lower tag bit, which can no longer be used for other purporses
    +1 always stores the pointer in a vector, returning its index, thus preserving its full form (including higher bits)
Attempting to compress an address higher than the mentioned limits, will lead however to increased CPU and RAM usage and cannot be shared between threads;
The following negative values can also be used, but they are not safe and will lead to crashes, when the memory limits are exceeded:
    -5 can compress addresses up to 64GB, at the expense of the 4 lower tag bits, which can no longer be used for other purporses
    -4 can compress addresses up to 32GB, at the expense of the 3 lower tag bits, which can no longer be used for other purporses
    -3 can compress addresses up to 16GB, at the expense of the 2 lower tag bits, which can no longer be used for other purporses
    -2 can compress addresses up to 8GB, at the expense of the lower tag bit, which can no longer be used for other purporses
    -1 can compress addresses up to 4GB, leaving the 3 lower tag bits to be used for other purporses
*/
enum COMPRESS_POINTERS = (void*).sizeof < 8 ? 0 : 5;

enum nil = null;
alias I8 = byte;
alias U8 = ubyte;
alias Bit = bool;
alias Vct = Array;
alias F32 = float;
alias I16 = short;
alias U16 = ushort;
alias ZNr = size_t;
alias PNr = uintptr_t;
alias Str = const(char)*;
alias DNr = ptrdiff_t;
alias F64 = double;
alias Txt = char*;
alias U64 = ulong;
alias I64 = long;
alias Chr = char;
alias U32 = uint;
alias I32 = int;
alias UNr = U32;
alias SNr = I32;
alias Dec = F32;
alias Idx = U16;
alias SBt = I8;
alias UBt = U8;
alias Nr = SNr;

static if (COMPRESS_POINTERS > 5)
{
    enum ALIGN_PTR_BYTES = 1 << (COMPRESS_POINTERS - 1);
}
else static if (COMPRESS_POINTERS < -5)
{
    enum ALIGN_PTR_BYTES = 1 << (abs(COMPRESS_POINTERS + 1));
}
else
{
    enum ALIGN_PTR_BYTES = -1;
}

static if (COMPRESS_POINTERS > 0)
{
    private Vct!(void*) _ptrList; //TODO: multiple thread shared access safety and analyze better solutions
}

struct CmpsPtr(T, const SNr own = 0, const SNr opt = 1, const SNr cmpsType = COMPRESS_POINTERS)
{
    static if (own)
    {
        pragma(inline, true)
        {
            protected
            {
                @system void clean()
                {
                    this.ptr.erase!(T, true);
                    static if (cmpsType)
                    {
                        this._ptr = 0U;
                        static if (cmpsType > 0)
                        {
                            clearList(this._ptr);
                        }
                    }
                    else
                    {
                        static if (opt > 0)
                        {
                            this.ptr = nil;
                        }
                        else
                        {
                            this._ptr = nil;
                        }
                    }
                    //GC.removeRange(ptr);
                }
            }
        }
    }
    
    //public @trusted this(T* ptr)
    public @trusted this(P)(P* ptr) if (is(P == T))
    {
        static if (cmpsType || opt < 1)
        {
            this.ptr!(P, false)(ptr);
            //this.ptr!(T, false)(ptr);
        }
        else
        {
            this.ptr = ptr;
        }
    }

    static if (opt)
    {
        public @trusted this(typeof(nil) ptr)
        {
            this(cast(T*)ptr);
        }
    }
    
    static if (own > 0)
    {
        protected CmpsPtr!(ZNr, 0, 1) count = void;

        pragma(inline, true)
        {
            public ZNr refCount() const @nogc nothrow
            {
                return *(this.count.ptr);
            }

            protected
            {
                @system void reset() //@nogc nothrow
                {
                    ZNr* countPtr = alloc!ZNr;
                    (*countPtr) = 1;
                    this.count.ptr = countPtr;
                }
                
                @system void increase() //@nogc nothrow 
                {
                    auto cntPtr = this.count.ptr;
                    if (cntPtr)
                    {
                        (*cntPtr) += 1;
                    }
                }
            }
        }

        @system protected void decrease() //@nogc nothrow
        {
            auto count = &this.count;
            auto cntPtr = count.ptr;
            if (cntPtr)
            {
                const auto cntNr = *cntPtr;
                if (cntNr == 1)
                {
                    this.clean;
                    count.ptr!ZNr = nil;//cast(ZNr*)nil;
                    cntPtr.free;
                }
                else //if (cntNr > 1)
                {
                    (*cntPtr) = cntNr - 1;
                }
            }
        }
    }
    
    static if (cmpsType == 0)
    {
        public
        {
            static if (opt > 0)
            {
                T* ptr = void;
            }
            else
            {
                private T* _ptr = void;

                @safe T* ptr() @nogc nothrow
                {
                    return this._ptr;
                }

                @safe void ptr(P, const Bit remove = true)(P* ptr) if (is(P == T) || is(P == typeof(nil)))
                {
                    static if (remove)
                    {
                        static if (opt < 1)
                        {
                            static assert(!is(P == typeof(nil)), "Null pointers are not allowed.");
                            assert(ptr, "Null pointers are not allowed.");
                        }
                    }
                    else
                    {
                        static if (!opt)
                        {
                            static assert(!is(P == typeof(nil)), "Null pointers are not allowed.");
                            assert(ptr, "Null pointers are not allowed.");
                        }
                    }
                    this._ptr = ptr;
                }
            }
            pragma(inline, true)
            {
                @safe Bit compressed() const @nogc nothrow
                {
                    return false;
                }
            }
        }
    }
    else static if (cmpsType > 0)
    {
        enum SHIFT_LEN = cmpsType - 2;
        enum ONLY_LIST = SHIFT_LEN < 0;
        private UNr _ptr = 0U;

        @system private static Bit clearList(UNr ptr)
        {
            if (ptr == 0U)
            {
                return false;
            }
            if (ONLY_LIST || (ptr & 1U) == 1U)
            {
                auto ptrList = &_ptrList;
                static if (!ONLY_LIST)
                {
                    ptr >>>= 1;
                }
                if (ptr == ptrList.length)
                {
                    ZNr ptrListLen = void;
                    do
                    {
                        ptrList.removeBack();
                    }
                    while ((ptrListLen = ptrList.length) > 0 && (--ptr) == ptrListLen && (*ptrList)[ptr - 1U] == nil);
                }
                else
                {
                    (*ptrList)[ptr - 1U] = nil;
                }
            }
            return true;
        }

        pragma(inline, true)
        {
            public
            {
                @safe Bit compressed() const @nogc nothrow
                {
                    static if (ONLY_LIST)
                    {
                        return false;
                    }
                    else
                    {
                        return (this._ptr & 1U) != 1U;
                    }
                }

                @trusted T* ptr() const @nogc nothrow
                {
                    const UNr ptr = this._ptr;
                    if (ptr == 0U)
                    {
                        return nil;
                    }
                    //PNr ptrNr = void;
                    else 
                    {
                        static if (ONLY_LIST)
                        {
                            return cast(T*)_ptrList[ptr - 1U];
                        }
                        else
                        {
                            if ((ptr & 1U) == 1U)
                            {
                                return cast(T*)_ptrList[(ptr >>> 1) - 1U];
                            }
                            else
                            {
                                //ptrNr = (cast(PNr)ptr) << SHIFT_LEN;
                                return cast(T*)((cast(PNr)ptr) << SHIFT_LEN);
                            }
                        }
                    }
                    //return cast(T*)((ptrNr & ((1UL << 48) - 1UL)) | ~((ptrNr & (1UL << 47)) - 1UL));
                }
            }
        }

        @system private void listPtr(const Bit remove = true)(T* ptr) @nogc nothrow
        {
            auto ptrList = &_ptrList;
            static if (remove)
            {
                UNr oldPtr = this._ptr;
                if (ONLY_LIST || (oldPtr & 1U) == 1U)
                {
                    static if (!ONLY_LIST)
                    {
                        oldPtr >>>= 1;
                    }
                    if (oldPtr > 0U)
                    {
                        (*ptrList)[oldPtr - 1U] = ptr;
                        return;
                    }
                }
            }
            ZNr ptrLength = ptrList.length;
            for (UNr i = 0; i < ptrLength; i += 1U)
            {
                if ((*ptrList)[i] == nil)
                {
                    (*ptrList)[i] = ptr;
                    static if (ONLY_LIST)
                    {
                        this._ptr = i;
                    }
                    else
                    {
                        this._ptr = (i << 1U) | 1U;
                    }
                    return;
                }
            }
            ptrList.insert(ptr);
            static if (ONLY_LIST)
            {
                this._ptr = cast(UNr)(ptrLength + 1);
            }
            else
            {
                this._ptr = cast(UNr)(((ptrLength + 1) << 1) | 1);
            }
        }

        //pragma(inline, true)
        @system public void ptr(P, const Bit remove = true)(P* ptr) if (is(P == T) || is(P == typeof(nil)))
        {
            static if (remove)
            {
                static if (opt < 1)
                {
                    static assert(!is(P == typeof(nil)), "Null pointers are not allowed.");
                    assert(ptr, "Null pointers are not allowed.");
                }
                static if (own == 0)
                {
                    if (this.ptr == ptr)
                    {
                        return;
                    }
                    if (ptr == nil)
                    {
                        if (clearList(this._ptr)) this._ptr = 0U;
                        return;
                    }
                }
                else
                {
                    if (ptr && ptr != this.ptr)
                    {
                        static if (own > 0)
                        {
                            this.decrease;
                            this.reset;
                        }
                        else static if (own < 0)
                        {
                            this.clean;
                        }
                    }
                    else
                    {
                        return;
                    }
                }
            }
            else
            {
                static if (!opt)
                {
                    static assert(!is(P == typeof(nil)), "Null pointers are not allowed.");
                    assert(ptr, "Null pointers are not allowed.");
                }
                static if (own > 0)
                {
                    this.reset;
                }
            }
            static if (ONLY_LIST)
            {
                this.listPtr!remove(ptr);
            }
            else
            {
                const PNr ptrNr = cast(PNr)ptr; //<< 16) >>> 16;
                if (ptrNr < (4294967295UL << SHIFT_LEN))
                {
                    static if (own < 1)
                    {
                        clearList(this._ptr);
                    }
                    this._ptr = cast(UNr)(ptrNr >>> SHIFT_LEN);
                }
                else
                {
                    this.listPtr!remove(ptr);
                }
            }
        }
        /*pragma(inline, true):
        this(this)
        {
            T* ptr = this.ptr;
            this._ptr = 0U;
            this.ptr = ptr;
        }*/
    }
    else
    {
        private UNr _ptr = void;
     
        enum SHIFT_LEN = -(cmpsType + 1);

        pragma(inline, true)
        {
            public:
            @safe Bit compressed() const @nogc nothrow
            {
                return true;
            }
            
            @trusted T* ptr() const @nogc nothrow
            {
                return cast(T*)((cast(PNr)this._ptr) << SHIFT_LEN);
            }
            
            @trusted void ptr(P, const Bit remove = true)(P* ptr) if (is(P == T) || is(P == typeof(nil)))
            {
                static if (remove)
                {
                    static if (opt < 1)
                    {
                        static assert(!is(P == typeof(nil)), "Null pointers are not allowed.");
                        assert(ptr, "Null pointers are not allowed.");
                    }
                    static if (own > 0)
                    {
                        if (ptr != this.ptr)
                        {
                            this.decrease;
                            this.reset;
                        }
                    }
                }
                else
                {
                    static if (!opt)
                    {
                        static assert(!is(P == typeof(nil)), "Null pointers are not allowed.");
                        assert(ptr, "Null pointers are not allowed.");
                    }
                }
                this._ptr = cast(UNr)((cast(PNr)ptr) >>> SHIFT_LEN);
            }
        }
    }

    public pragma(inline, true):
    static if (own < 0)
    {
        @system ~this() //@nogc nothrow
        {
            this.clean;
        }
    }
    else static if (own > 0)
    {
        @system ~this() //@nogc nothrow
        {
            this.decrease;
        }
    }
    
    alias ptr this;

    static if (own > 0)
    {
        @disable this(this);

        private @system void copy(ref return scope CmpsPtr copy) //@nogc nothrow
        {
            //this.count = nil;
            this.ptr = copy.ptr;
            static if (own > 0)
            {
                this.count = copy.count;
                this.increase;
            }
        }

        @system void opAssign(ref return scope CmpsPtr copy)
        {
            this.copy(copy);
        }

        @system this(ref return scope CmpsPtr copy) //@nogc nothrow
        {
            this.copy(copy);
        }
    }
    else static if (own < 0)
    {   
        @disable this(ref return scope CmpsPtr copy);
    }
    /*else
    {
        @system void copy(ref return scope CmpsPtr copy) //@nogc nothrow
        {
            this._ptr = copy._ptr;
        }
    }*/

    private
    {
        @trusted void copy(P = T)(P* ptr) if (is(P == T) || is(P == typeof(nil)))
        {
            static if (cmpsType || opt < 1)
            {
                auto oPtr = this.ptr;
                if (oPtr)
                {
                    this.ptr = ptr;
                }
                else
                {
                    this.ptr!(T, false) = ptr;
                }
            }
            else
            {
                this.ptr = ptr;
            }
        }
    }

    public
    {
    //static if (own == 0)
    //{

        @trusted void opAssign(P)(P* ptr) if (is(P == T))
        {
            this.copy(ptr);
        }

        static if (opt > 0)
        {
            @trusted void opAssign(typeof(nil) ptr)
            {
                this.copy!T(ptr);
            }
        }

        /*@system void opAssign(ref return scope CmpsPtr copy)
        {
            this.copy(copy);
        }

        @system this(ref return scope CmpsPtr copy) //@nogc nothrow
        {
            this.copy(copy);
        }*/
    //}

        import core.lifetime : forward;
        @trusted T* ptrOrNew(Args...)(auto ref Args args)
        {
            auto ptr = this.ptr;
            if (ptr == nil)
            {
                ptr = allocNew!T(forward!args);
                this.ptr = ptr;
            }
            return ptr;
        }

        @trusted ref T objOrNew(Args...)(auto ref Args args)
        {
            return *(this.ptrOrNew(forward!args));
        }

        import std.traits : ReturnType;        
        @trusted T* ptrOrElse(F, Args...)(F fn, auto ref Args args) if (is(ReturnType!F == T*))
        {
            auto ptr = this.ptr;
            if (ptr == nil)
            {
                ptr = fn(forward!args);
                this.ptr = ptr;
            }
            return ptr;
        }

        //import std.traits : isCallable;
        @trusted ReturnType!F runIfPtr(F, Args...)(F fn, auto ref Args args) //if (isCallable!F)
        {
            auto ptr = this.ptr;
            if (ptr)
            {
                return fn(*ptr, forward!args);
            }
        }

        @trusted ref T objOrElse(F, Args...)(F fn, auto ref Args args)
        {
            auto ptr = this.ptrOrElse(fn, forward!args);
            if (ptr == nil)
            {
                ptr = allocNew!T;
            }
            return *ptr;
        }

        @disable this();
    }
}

enum USE_GC_ALLOC = ALIGN_PTR_BYTES < -1  && COMPRESS_POINTERS > -1 && COMPRESS_POINTERS < 2;

static if (USE_GC_ALLOC)
{
    import core.memory : GC;
}
else static if (ALIGN_PTR_BYTES > -1)
{
    version (Windows)
    {
        //Source: $(PHOBOSSRC std/experimental/allocator/mallocator.d)    
        @nogc nothrow private extern(C) void* _aligned_malloc(size_t, size_t);
        @nogc nothrow private extern(C) void _aligned_free(void* memblock);
    }
}

pragma(inline, true)
{
    @trusted T* alloc(T)(const SNr qty = 1) //@nogc nothrow
    {
        static if (USE_GC_ALLOC)
        {
            return cast(T*)GC.malloc(T.sizeof * qty);
        }
        else static if (ALIGN_PTR_BYTES < 0)
        {
            import core.stdc.stdlib : malloc;
            return cast(T*)malloc(T.sizeof * qty);
        }
        else
        {
            //Source: $(PHOBOSSRC std/experimental/allocator/mallocator.d)
            version (Posix)
            {
                void* ptr;
                import core.sys.posix.stdlib : posix_memalign;
                reurn (posix_memalign(&ptr, ALIGN_PTR_BYTES, T.sizeof * qty)) ? nil : cast(T*)ptr;
            }
            else version(Windows)
            {
                return cast(T*)_aligned_malloc(ALIGN_PTR_BYTES, T.sizeof * qty);
            }
        }
    }

    @system void clear(T, const Bit check = false)(T** ptr) @nogc nothrow
    {
        static if (check)
        {
            if (ptr == nil) return;
        }
        (*ptr).erase!(T, check);
        (*ptr) = nil;
    }

    @system void clear(T, const Bit check = false)(CmpsPtr!T ptr) @nogc nothrow
    {
        ptr.erase!(T, check);
        ptr.ptr = nil;
    }

    @system void erase(T, const Bit check = false)(T* ptr)
    {
        static if (check)
        {
            if (ptr == nil) return;
        }
        (*ptr).destroy;
        static if (USE_GC_ALLOC)
        {
            GC.free(ptr);
        }
        else
        {
            //Source: $(PHOBOSSRC std/experimental/allocator/mallocator.d)
            version(Windows)
            {
                static if (ALIGN_PTR_BYTES > -1)
                {
                    ptr._aligned_free;
                }
                else
                {
                    ptr.free;
                }
            }
            else
            {
                ptr.free;
            }
        }
    }

    @system void erase(T, const Bit check = false)(CmpsPtr!T ptr) @nogc nothrow
    {
        ptr.ptr.erase!(T, check);
    }
}

@trusted T* allocNew(T, Args...)(auto ref Args args)
{
    import core.lifetime : emplace;
    T* newInstance = alloc!T(1);
    emplace!T(newInstance, args);
    return newInstance;
}

alias Ptr = CmpsPtr;

struct IdxHndl(string array, string arrayModule = "", U = Idx)
{
    static if (arrayModule.length > 0 && arrayModule != "cmpsptr")
    {
        mixin("import " ~ arrayModule ~";");
    }
    private:
    alias T = mixin("typeof(" ~ array ~ "[0])");
    @safe static U findIdx(T* ptr) @nogc nothrow
    {
        mixin("auto arr = &" ~ array ~ q{;
               import std.traits;
               static if (isArray!(typeof(*arr)))
               {
                   enum objSize = T.sizeof;
                   auto idPtr = cast(PNr)ptr;
                   auto arPtr = cast(PNr)arr.ptr;
                   if (idPtr >= arPtr && idPtr < arPtr + (arr.length * objSize))
                   {
                       return cast(U)((idPtr - arPtr) / objSize);
                   }
               }
               else
               {
                   const auto arrLn = arr.length;
                   for (U i = 0; i < arrLn; ++i)
                   {
                       if (&((*arr)[i]) == ptr)
                       {
                           return i;
                       }
                   }
               }
        });
        return cast(U)-1;
    }

    pragma(inline, true):
    static if (U.sizeof < (void*).sizeof)
    {
        U _idx = void;

        @safe void copy(T* ptr) @nogc nothrow
        {
            /*import std.traits;
            mixin("auto arr = &" ~ array ~ ";");
            static if (isStaticArray!(typeof(*arr)))
            {
                enum i = findIdx(ptr);
                this._idx = i;
            }
            else
            {*/
                this._idx = this.findIdx(ptr);
            //}
        }

        @safe void copy(U idx) @nogc nothrow
        {
            this._idx = idx;
        }
        
        /*@safe void copy(ref return scope IdxHndl copy) @nogc nothrow
        {
            this._idx = copy._idx;
        }*/

        public:
        @safe ref T obj() @nogc nothrow
        {
            mixin("return " ~ array ~ "[this._idx];");
        }

        @safe T* ptr() @nogc nothrow
        {
            mixin("return &(" ~ array ~ "[this._idx]);");
        }

        @system U index() @nogc nothrow
        {
            return this._idx;
        }
    }
    else
    {
        private:
        T* _ptr = void;
        
        @safe void copy(U idx) @nogc nothrow
        {
            mixin("this._ptr = &(" ~ array ~ "[idx]);");
        }
        
        @safe void copy(T* ptr) @nogc nothrow
        {
            this._ptr = ptr;
        }
        
        /*@safe void copy(ref return scope IdxHndl copy) @nogc nothrow
        {
            this._ptr = copy._ptr;
        }*/

        public:
        @safe ref T obj() @nogc nothrow
        {
            return *this._ptr;
        }
        
        @safe T* ptr() @nogc nothrow
        {
            return this._ptr;
        }

        @system U index() @nogc nothrow
        {
            return findIdx(this._ptr);
        }
    }

    /*void copy(ref T obj) @nogc nothrow
    {
        this.copy(&obj);
    }*/

    public:
    @safe void opAssign(U idx) @nogc nothrow
    {
        this.copy(idx);
    }

    @safe void opAssign(T* ptr) @nogc nothrow
    {
        this.copy(ptr);
    }

    /*@safe void opAssign(ref return scope IdxHndl copy) @nogc nothrow
    {
        this.copy(ptr);
    }

    @system void opAssign(ref T obj) @nogc nothrow
    {
        this.copy(obj);
    }*/

    @safe this(U idx) @nogc nothrow
    {
        this.copy(idx);
    }

    @safe this(T* ptr) @nogc nothrow
    {
        this.copy(ptr);
    }

    /*@safe this(ref return scope IdxHndl copy) @nogc nothrow
    {
        this.copy(ptr);
    }

    @system this(ref T obj) @nogc nothrow
    {
        this.copy(obj);
    }*/

    @disable this();
    
    alias obj this;
}

alias Hnl = IdxHndl;