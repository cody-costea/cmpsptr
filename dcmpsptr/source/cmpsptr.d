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
import core.lifetime : forward;
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
    -1 can compress addresses up to 4GB, leaving the 4 lower tag bits to be used for other purporses
If a value higher or lower than those mentioned is set, on Windows and Posix systems, the allocation functions defined in this module, will attempt to
request aligned memory from the operating system, so that the specified number of low bits is available for shifting. This is however not recommended.
*/
version (D_BetterC)
{
    enum COMPRESS_POINTERS = (void*).sizeof < 8 ? 0 : -5;
}
else
{
    enum COMPRESS_POINTERS = (void*).sizeof < 8 ? 0 : 5;
}

//This enum should be set to a non-zero value, only if the operating system is using the higher bits from 64bit pointers, to differentiate between processes.
enum USE_GLOBAL_MASK = 1;

enum nil = null;
alias I8 = byte;
alias U8 = ubyte;
alias Bit = bool;
alias Raw(T) = T*;
alias Vct = Array;
alias F32 = float;
alias I16 = short;
alias U16 = ushort;
alias ZNr = size_t;
alias PNr = uintptr_t;
alias Nil = typeof(nil);
alias Str = const(char)*;
alias DPt = ptrdiff_t;
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

private Vct!(void*) _ptr_list; //TODO: multiple thread shared access safety and analyze better solutions

enum Ownership : SNr
{
    movableUnique = -2,
    fixedUnique = -1,
    borrowed = 0,
    cowCounted = 1,
    sharedCounted = 2
}

enum Optionality : SNr
{
    lazyInit = -1,
    nonNull = 0,
    nullable = 1
}

alias Own = Ownership;
alias Opt = Optionality;

struct CmpsPtr(T, const Own own = Own.sharedCounted, const Opt opt = Opt.nullable, const Bit track = true,
               const Bit implicitCast = true, const SNr cmpsType = COMPRESS_POINTERS, U = UNr)
{
    enum copyable = __traits(isCopyable, T);
    enum constructible = __traits(compiles, T());
    static assert (own != Own.cowCounted || copyable, "Only copyable types can have copy-on-write pointers.");
    static assert ((cmpsType < 1 && !track) || (!(is(typeof(this) == shared) || is(T == shared))), "Compressed pointers cannot be shared.");

    @trusted static CmpsPtr makeNew(Args...)(auto ref Args args)
    {
        return (CmpsPtr(Mgr!cmpsType.allocNew!T(forward!args)));
    }

    protected pragma(inline, true)
    {
        public @safe Bit isNil() const @nogc nothrow
        {
            static if (opt)
            {
                static if (cmpsType)
                {
                    return this._ptr == 0U;
                }
                else
                {
                    return this._ptr == nil;
                }
            }
            else
            {
                return false;
            }
        }

        static if (own)
        {
            @system void clean()
            {
                Mgr!cmpsType.erase!(T, true)(this.addr);
                static if (cmpsType)
                {
                    static if (cmpsType > 0)
                    {
                        clearList(this._ptr);
                    }
                    this._ptr = 0U;
                }
                else
                {
                    this._ptr = nil;
                }
            }
        }

        static if (cmpsType)
        {
            @trusted this(U ptr) //@nogc nothrow
            {
                this._ptr = ptr;
                static if (own > 0)
                {
                    if (ptr)
                    {
                        this.reset;
                    }
                }
            }
        }
    }

    public
    {
        @trusted auto ptr() const @nogc nothrow
        {
            return cast(const T*)this.addr;
        }

        @trusted T* ptr()
        {
            static if (own == 1)
            {
                this.detach;
            }
            return this.addr;
        }
    
        @trusted this(P)(P* ptr) if (is(P == T))
        {
            this.ptr!(P, false)(ptr);
        }
    }

    static if (opt)
    {
        public @trusted this(Nil)
        {
            static if (cmpsType)
            {
                this._ptr = 0U;
            }
            else
            {
                this._ptr = nil;
            }
        }
    }
    
    static if (own > 0)
    {
        protected CmpsPtr!(ZNr, Own.borrowed, Opt.nullable, false) count = nil;//void;

        pragma(inline, true)
        {
            public 
            {
                @trusted ZNr refCount() const @nogc nothrow
                {
                    auto cPtr = this.count.ptr;
                    if (cPtr)
                    {
                        return *(cPtr);
                    }
                    else
                    {
                        return 0U;
                    }
                }
                static if (copyable)
                {
                    @trusted void detach()
                    {
                        if (this.refCount > 1)
                        {
                            this.ptr = Mgr!cmpsType.allocNew!T(*this.addr);
                        }
                    }
                }
            }

            protected
            {
                @system void reset() //@nogc nothrow
                {
                    ZNr* countPtr = Mgr!cmpsType.allocNew!ZNr(1);
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
                    count.ptr!ZNr = nil;
                    Mgr!COMPRESS_POINTERS.erase!(ZNr, false)(cntPtr);
                }
                else //if (cntNr > 1)
                {
                    (*cntPtr) = cntNr - 1;
                }
            }
        }
    }
    static if (cmpsType < 1)
    {
        protected @trusted void doCount(P, const Bit remove = true)(P* ptr) if (is(P == T) || is(P == Nil))
        {
            static if (remove)
            {
                static if (opt < 1)
                {
                    static assert(!is(P == Nil), "Null pointers are not allowed.");
                    assert(ptr, "Null pointers are not allowed.");
                }
                static if (own > 0)
                {
                    if (ptr != this.addr)
                    {
                        this.decrease;
                        this.reset;
                    }
                }
                else static if (own < -1)
                {
                    if (ptr != this.addr)
                    {
                        this.clean;
                    }
                }
            }
            else
            {
                static if (!opt)
                {
                    static assert(!is(P == Nil), "Null pointers are not allowed.");
                    assert(ptr, "Null pointers are not allowed.");
                }
            }
        }
    }
    static if (cmpsType == 0)
    {
        public
        {
            private T* _ptr = void;
            //private PNr _ptr = void;
            pragma(inline, true)
            {
                @system T* addr() const @nogc nothrow
                {
                    return cast(T*)this._ptr;
                }

                @safe void ptr(P, const Bit remove = true)(P* ptr)
                {
                    this.doCount!(P, remove)(ptr);
                    //this._ptr = cast(PNr)ptr;
                    this._ptr = ptr;
                }

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
        private U _ptr = 0U;

        @system private static Bit clearList(U ptr)
        {
            if (ptr == 0U)
            {
                return false;
            }
            if (ONLY_LIST || (ptr & 1U) == 1U)
            {
                auto ptrList = &_ptr_list;
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

                @system T* addr() const @nogc nothrow
                {
                    const auto ptr = this._ptr;
                    if (ptr == 0U)
                    {
                        return nil;
                    }
                    //PNr ptrNr = void;
                    else 
                    {
                        static if (ONLY_LIST)
                        {
                            return cast(T*)_ptr_list[ptr - 1U];
                        }
                        else
                        {
                            if ((ptr & 1U) == 1U)
                            {
                                return cast(T*)_ptr_list[(ptr >>> 1) - 1U];
                            }
                            else
                            {
                                static if (USE_GLOBAL_MASK)
                                {
                                    return cast(T*)applyGlobalMask((cast(PNr)ptr) << SHIFT_LEN);
                                }
                                else
                                {
                                    return cast(T*)((cast(PNr)ptr) << SHIFT_LEN);
                                }
                            }
                        }
                    }
                }
            }
        }

        @system private void listPtr(const Bit remove = true)(T* ptr) @nogc nothrow
        {
            auto ptrList = &_ptr_list;
            static if (remove)
            {
                auto oldPtr = this._ptr;
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
            for (UNr i = 0U; i < ptrLength; i += 1U)
            {
                if ((*ptrList)[i] == nil)
                {
                    (*ptrList)[i] = ptr;
                    static if (ONLY_LIST)
                    {
                        this._ptr = i + 1U;
                    }
                    else
                    {
                        this._ptr = ((i + 1U) << 1U) | 1U;
                    }
                    return;
                }
            }
            ptrList.insert(ptr);
            static if (ONLY_LIST)
            {
                this._ptr = cast(U)(ptrLength + 1U);
            }
            else
            {
                this._ptr = cast(U)(((ptrLength + 1U) << 1U) | 1U);
            }
        }

        @trusted public void ptr(P, const Bit remove = true)(P* ptr) if (is(P == T) || is(P == Nil))
        {
            static if (remove)
            {
                static if (opt < 1)
                {
                    static assert(!is(P == Nil), "Null pointers are not allowed.");
                    assert(ptr, "Null pointers are not allowed.");
                }
                static if (own == 0)
                {
                    if (this.addr == ptr)
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
                    if (ptr == this.addr)
                    {
                        return;
                    }
                    else
                    {
                        static if (own > 0)
                        {
                            this.decrease;
                            this.reset;
                        }
                        else static if (own < -1)
                        {
                            this.clean;
                        }
                    }
                }
            }
            else
            {
                static if (!opt)
                {
                    static assert(!is(P == Nil), "Null pointers are not allowed.");
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
                const PNr ptrNr = cast(PNr)ptr;
                static if (USE_GLOBAL_MASK)
                {
                    const bool ptrCheck = checkGlobalMask!SHIFT_LEN(ptrNr);
                }
                else
                {
                    const bool ptrCheck = ptrNr < (4294967296UL << SHIFT_LEN);
                }
                if (ptrCheck)
                {
                    static if (own < 1)
                    {
                        clearList(this._ptr);
                    }
                    this._ptr = cast(U)(ptrNr >>> SHIFT_LEN);
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
        private U _ptr = void;
     
        enum SHIFT_LEN = -(cmpsType + 1);

        pragma(inline, true)
        {
            public:
            @safe Bit compressed() const @nogc nothrow
            {
                return true;
            }
            
            @system T* addr() const @nogc nothrow
            {
                static if (USE_GLOBAL_MASK)
                {
                    auto ptr = this._ptr;
                    if (ptr == 0U)
                    {
                        return nil;
                    }
                    else
                    {
                        return cast(T*)applyGlobalMask((cast(PNr)ptr) << SHIFT_LEN);
                    }
                }
                else
                {
                    return cast(T*)((cast(PNr)this._ptr) << SHIFT_LEN);
                }
            }
            
            @trusted void ptr(P, const Bit remove = true)(P* ptr)
            {
                this.doCount!(P, remove)(ptr);
                static if (USE_GLOBAL_MASK)
                {
                    if (ptr == nil)
                    {
                        this._ptr = 0U;
                    }
                    else
                    {
                        auto ptrNr = (cast(PNr)ptr);
                        if (checkGlobalMask!SHIFT_LEN(ptrNr))
                        {
                            this._ptr = cast(U)(ptrNr >>> SHIFT_LEN);
                        }
                        else
                        {
                            import std.format : format;
                            version (assert)
                            {
                                assert(0, format("Pointer address %ull cannot be compressed.", ptrNr));
                            }
                            else
                            {
                                this._ptr = 0U;
                            }
                        }
                    }
                }
                else
                {
                    this._ptr = cast(U)((cast(PNr)ptr) >>> SHIFT_LEN);
                }
            }
        }
    }
    
    static if (implicitCast)
    {
        alias ptr this;
    }
    else
    {
        mixin ForwardTo!obj;
        //mixin ForwardDispatch;

        auto opCast() const
        {
            return this.ptr;
        }
    }

    public pragma(inline, true):
    static if (opt)
    {
        private @system void copy(const Bit remove = true)(ref return scope const CmpsPtr!(T,
                                    own, Opt.nonNull, track, false, cmpsType, U) copy) //@nogc nothrow
        {
            static if (own || cmpsType < 1)
            {
                this._ptr = copy._ptr;
                static if (own > 0)
                {
                    this.count = copy.count;
                    this.increase;
                }
            }
            else
            {
                this.ptr!(T, remove) = copy.addr;
            }
        }

        static if (own != -1)
        {
            @trusted void opAssign(ref return scope const CmpsPtr!(T, own, Opt.nonNull, track, false, cmpsType, U) copy)
            {
                static if (own < -1)
                {                        
                    auto oPtr = this._ptr;
                }
                this.copy!true(forward!copy);
                static if (own < -1)
                {
                    copy._ptr = oPtr;
                }
            }
        }

        @trusted this(ref return scope const CmpsPtr!(T, own, Opt.nonNull, track, false, cmpsType, U) copy) //@nogc nothrow
        {
            this.copy!false(forward!copy);
            static if (own < - 1)
            {
                static if (cmpsType)
                {
                    copy._ptr = 0U;
                }
                else
                {
                    copy._ptr = nil;
                }
            }
        }
    }
    static if (own < 0)
    {
        @trusted ~this() //@nogc nothrow
        {
            this.clean;
        }
    }
    else static if (own > 0)
    {
        @trusted ~this() //@nogc nothrow
        {
            this.decrease;
        }
    }
    else static if (cmpsType > 0)
    {
        @trusted ~this() //@nogc nothrow
        {
            this.clearList(this._ptr);
        }
    }

    static if (own)
    {        
        @disable this(this);
    }

    static if (own > 0)
    {
        private @system void copy(ref return scope const CmpsPtr copy) //@nogc nothrow
        {
            //this.count = nil;
            static if (own > 0)
            {
                this.count = copy.count;
                this.increase;
            }
        }

        @trusted void opAssign(ref return scope const CmpsPtr copy)
        {
            this.ptr = copy.addr;
            this.copy(forward!copy);
        }

        @trusted this(ref return scope const CmpsPtr copy) //@nogc nothrow
        {
            this.ptr!(T, false) = copy.addr;
            //this.copy(forward!copy);
            static if (own > 0)
            {
                this.count = copy.count;
                this.increase;
            }
        }
    }
    else static if (own == 0)
    {
        private @system void copy(const Bit remove = true)(ref return scope const CmpsPtr copy) //@nogc nothrow
        {
            static if (cmpsType > 0)
            {
                this.ptr!(T, remove) = copy.addr;
            }
            else
            {
                this._ptr = copy._ptr;
            }
        }

        @trusted void opAssign(ref return scope const CmpsPtr copy)
        {
            this.copy!true(forward!copy);
        }

        @trusted this(ref return scope const CmpsPtr copy) //@nogc nothrow
        {
            this.copy!false(forward!copy);
        }
    }
    else static if (own == -1)
    {
        @disable this(ref return scope const CmpsPtr copy);
        @disable this(ref return scope CmpsPtr copy);
    }
    else static if (own < -1)
    {
        @trusted this(ref return scope CmpsPtr copy) //@nogc nothrow
        {
            this._ptr = copy._ptr;
            static if (cmpsType)
            {
                copy._ptr = 0U;
            }
            else
            {
                copy._ptr = nil;
            }
        }
        @trusted void opAssign(ref return scope CmpsPtr copy)
        {
            //static assert(own != -1, "Cannot reassign unique pointer.");
            auto oPtr = this._ptr;
            this._ptr = copy._ptr;
            copy._ptr = oPtr;
        }
    }

    private
    {
        @trusted void copy(P = T)(P* ptr) if (is(P == T) || is(P == Nil))
        {
            static assert(own != -1, "Cannot reassign unique pointer.");
            //static assert (own != -1 || is(P == Nil));                
            static if (cmpsType > 0)
            {
                auto oPtr = this.addr;
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

    public @trusted
    {
        static if (copyable)
        {
            CmpsPtr clone() const
            {
                return CmpsPtr(Mgr!cmpsType.allocNew!T(*this.addr));
            }
        }

        void opAssign(P)(P* ptr) if (is(P == T) && own != -1)
        {
            this.copy!P(ptr);
        }

        static if (opt > 0 && own != -1)
        {
            void opAssign(Nil)
            {
                this.copy!T(nil);
            }
        }

        CmpsPtr!(T, Own.borrowed, Opt.nullable, track, implicitCast, cmpsType) borrow() //const
        {
            return CmpsPtr!(T, Own.borrowed, Opt.nullable, track, implicitCast, cmpsType)(this._ptr);
        }

        CmpsPtr!(T, Own.borrowed, Opt.nonNull, track, implicitCast, cmpsType) borrowNonNull() //const
        {
            //this.obj;
            auto ptr = this._ptr;
            assert(ptr, "Non-nullable pointers cannot be null.");
            return CmpsPtr!(T, Own.borrowed, Opt.nonNull, track, implicitCast, cmpsType)(ptr);
        }

        CmpsPtr!(T, Own.borrowed, Opt.nonNull, track, implicitCast, cmpsType) borrowOrNew(Args...)(auto ref Args args)
        {
            auto ptr = this._ptr;
            //this.addrOrNew(forward!args);
            if (!ptr)
            {
                this.ptr = Mgr!cmpsType.allocNew!T(forward!args);
                ptr = this._ptr;
            }
            return CmpsPtr!(T, Own.borrowed, Opt.nonNull, track, implicitCast, cmpsType)(ptr);
        }

        CmpsPtr!(T, Own.borrowed, Opt.nonNull, track, implicitCast, cmpsType) borrowOrElse(F, Args...)(F fn, auto ref Args args)
        {
            auto ptr = this._ptr;
            //this.addrOrElse((fn, forward!args));
            if (!ptr)
            {
                this.ptr = fn(forward!args);
                ptr = this._ptr;
            }
            return CmpsPtr!(T, Own.borrowed, Opt.nonNull, track, implicitCast, cmpsType)(ptr);
        }

        @Dispatch ref auto obj() const @nogc nothrow
        {
            auto ptr = this.ptr;
            assert(ptr, "References cannot be null.");
            return *cast(const T*)ptr;
        }

        static if (opt)
        {
            @Dispatch ref T obj()
            {
                auto ptr = this.ptr;
                static if (constructible)
                {
                    if (ptr == nil)
                    {
                        ptr = Mgr!(cmpsType).allocNew!T;
                        this.ptr = ptr;
                    }
                }
                else
                {
                    assert(ptr, "References cannot be null.");
                }
                return *ptr;
            }

            T* ptrOrNew(Args...)(auto ref Args args)
            {
                auto ptr = this.ptr;
                if (ptr == nil)
                {
                    ptr = Mgr!(cmpsType).allocNew!T(forward!args);
                    this.ptr = ptr;
                }
                return ptr;
            }

            @system T* addrOrNew(Args...)(auto ref Args args)
            {
                auto ptr = this.addr;
                if (ptr == nil)
                {
                    ptr = Mgr!(cmpsType).allocNew!T(forward!args);
                    this.ptr = ptr;
                }
                return ptr;
            }

            import std.traits : ReturnType;
            T* ptrOrElse(F, Args...)(F fn, auto ref Args args) if (is(ReturnType!F == T*))
            {
                auto ptr = this.ptr;
                if (ptr == nil)
                {
                    ptr = fn(forward!args);
                    this.ptr = ptr;
                }
                return ptr;
            }
                    
            @system T* addrOrElse(F, Args...)(F fn, auto ref Args args) if (is(ReturnType!F == T*))
            {
                auto ptr = this.addr;
                if (ptr == nil)
                {
                    ptr = fn(forward!args);
                    this.ptr = ptr;
                }
                return ptr;
            }

            ref T objOrElse(F, Args...)(F fn, auto ref Args args)
            {
                auto ptr = this.ptrOrElse(fn, forward!args);
                static if (constructible)
                {
                    if (ptr == nil)
                    {
                        ptr = Mgr!(cmpsType).allocNew!T;
                        this.ptr = ptr;
                    }
                }
                else
                {
                    assert(ptr, "References cannot be null.");
                }
                return *ptr;
            }

            static if (own < -1)
            {
                T* swapPtr(T* newPtr)
                {
                    auto ptr = this.addr;
                    /*if (ptr)
                    {
                        static if (own > 0)
                        {
                            auto count = &this.count;
                            auto cntPtr = count.ptr;
                            if (cntPtr)
                            {
                                const auto cntNr = *cntPtr;
                                if (cntNr > 1)
                                {
                                    (*cntPtr) = cntNr - 1;
                                }
                                else
                                {
                                    count.ptr!ZNr = nil;
                                    Mgr!COMPRESS_POINTERS.erase!(ZNr, false)(cntPtr);
                                }
                                count = nil;
                            }
                        }
                        static if (cmpsType)
                        {
                            this._ptr = 0U;
                        }
                        else
                        {
                            this._ptr = nil;
                        }
                    }*/
                    this.ptr = newPtr;
                    return ptr;
                }

                T* takePtr()
                {
                    return this.swapPtr(nil);
                }
            }
        }
        else
        {
            @Dispatch ref T obj()
            {
                return *this.ptr;
            }

            T* ptrOrNew(Args...)(auto ref Args args)
            {
                return this.ptr;
            }

            T* addrOrNew(Args...)(auto ref Args args)
            {
                return this.addr;
            }

            import std.traits : ReturnType;
            T* ptrOrElse(F, Args...)(F fn, auto ref Args args) if (is(ReturnType!F == T*))
            {
                return this.ptr;
            }
                    
            T* addrOrElse(F, Args...)(F fn, auto ref Args args) if (is(ReturnType!F == T*))
            {
                return this.addr;
            }

            ref T objOrElse(F, Args...)(F fn, auto ref Args args)
            {
                return *this.ptr;
            }
        }

        ref auto constObj() const //@nogc nothrow
        {
            auto ptr = cast(const T*)this.addr;
            assert(ptr, "References cannot be null.");
            return *ptr;
        }

        ref T objOrNew(Args...)(auto ref Args args)
        {
            return *(this.ptrOrNew(forward!args));
        }

        ReturnType!F call(F, Args...)(F fn, auto ref Args args) const
        {
            auto ptr = this.ptr;
            if (ptr)
            {
                return fn(*ptr, forward!args);
            }
        }

        ReturnType!F call(F, Args...)(F fn, auto ref Args args) //if (isCallable!F)
        {
            auto ptr = this.ptr;
            if (ptr)
            {
                return fn(*ptr, forward!args);
            }
        }

        ref auto opCall() const @nogc nothrow
        {
            return this.obj;
        }

        ref T opCall()
        {
            return this.obj;
        }

        static if (own != -1)
        {
            private
            {
                void applyCopy(P)(P copy)
                {
                    static if (own > 0)
                    {
                        copy.count = this.count;
                        this.increase;
                    }
                    else static if (own < -1)
                    {
                        this._ptr = 0U;
                    }
                }

                CmpsPtr!(T, own, Opt.nonNull, track, implicitCast, cmpsType) getNonNull()
                {
                    auto cmpsPtr = CmpsPtr!(T, own, Opt.nonNull, track, implicitCast, cmpsType)(this._ptr);
                    this.applyCopy(cmpsPtr);
                    return cmpsPtr;
                }
            }

            CmpsPtr!(T, own, Opt.nonNull, track, implicitCast, cmpsType) nonNull()
            {
                static if (opt)
                {
                    if (this.isNil)
                    {
                        static if (constructible)
                        {
                            this.ptr = Mgr!(cmpsType).allocNew!T;
                        }
                        else
                        {
                            assert(0, "References cannot be null.");
                        }
                    }
                }
                return this.getNonNull;
            }

            CmpsPtr!(T, own, Opt.nonNull, track, implicitCast, cmpsType) nonNullOrNew(Args...)(auto ref Args args)
            {
                this.addrOrNew(forward!args);
                return this.getNonNull;
            }

            CmpsPtr!(T, own, Opt.nonNull, track, implicitCast, cmpsType) nonNullOrElse(F, Args...)(F fn, auto ref Args args)
            {
                this.addrOrElse((fn, forward!args));
                return this.nonNull;
            }

            CmpsPtr!(T, own, Opt.nullable, track, implicitCast, cmpsType) nullable()
            {
                auto cmpsPtr = CmpsPtr!(T, own, Opt.nullable, track, implicitCast, cmpsType)(this._ptr);
                this.applyCopy(cmpsPtr);
                return cmpsPtr;
            }
        }

        ReturnType!F opCall(F, Args...)(F fn, auto ref Args args) const
        {
            return this.call(fn, forward!args);
        }

        ReturnType!F opCall(F, Args...)(F fn, auto ref Args args)
        {
            return this.call(fn, forward!args);
        }

        @safe Bit opEquals()(auto ref const CmpsPtr cmp) const @nogc nothrow
        {
            return this._ptr == cmp._ptr;
        }

        @safe SNr opCmp()(auto ref const CmpsPtr cmp) const @nogc nothrow
        {
            const auto cmpAddr = cmp._ptr;
            const auto ptrAddr = this._ptr;
            return ptrAddr > cmpAddr ? 1 : (ptrAddr < cmpAddr ? -1 : 0);
        }

        Bit opEquals(const T* ptr) const @nogc nothrow
        {
            return this.addr == ptr;
        }

        SNr opCmp(const T* ptr) const @nogc nothrow
        {
            const auto addr = this.addr;
            return addr > ptr ? 1 : (addr < ptr ? -1 : 0);
        }

        @disable this();
    }
}

public template MemoryManager(SNr cmpsType = COMPRESS_POINTERS, SNr ptrAlignBytes = cmpsType
                              ? (abs(cmpsType) > 5 ? 1 << (abs(cmpsType > 0 ? cmpsType - 1
                              : cmpsType) - 1) : -2) : -2)
{
    version (D_BetterC)
    {
        enum USE_GC_ALLOC = false;
    }
    else
    {
        enum USE_GC_ALLOC = ptrAlignBytes < -1  && cmpsType > -1 && cmpsType < 2;
    }

    static if (USE_GC_ALLOC)
    {
        import core.memory : GC;
    }
    else static if (ptrAlignBytes == 0)
    {
        version (Windows)
        {
            //Source: $(PHOBOSSRC std/experimental/allocator/_mmap_allocator.d)
            extern (Windows) private pure @system @nogc nothrow
            {
                import core.sys.windows.basetsd : SIZE_T;
                import core.sys.windows.windef : BOOL, DWORD;
                import core.sys.windows.winnt : LPVOID, PVOID;

                DWORD GetLastError();
                void SetLastError(DWORD);
                PVOID VirtualAlloc(PVOID, SIZE_T, DWORD, DWORD);
                BOOL VirtualFree(PVOID, SIZE_T, DWORD);
            }
        }
    }
    else static if (ptrAlignBytes > 0)
    {
        version (Windows)
        {
            //Source: $(PHOBOSSRC std/experimental/allocator/mallocator.d)
            extern (Windows) private @system @nogc nothrow
            {
                void* _aligned_malloc(size_t, size_t);
                void _aligned_free(void* memblock);
            }
        }
    }

    public pragma(inline, true)
    {
        @trusted T* alloc(T)(const SNr qty = 1) //@nogc nothrow
        {
            static if (USE_GC_ALLOC)
            {
                return cast(T*)GC.malloc(T.sizeof * qty);
            }
            else static if (ptrAlignBytes < 0)
            {
                import core.stdc.stdlib : malloc;
                return cast(T*)malloc(T.sizeof * qty);
            }
            else static if (ptrAlignBytes == 0)
            {
                //Source: $(PHOBOSSRC std/experimental/allocator/_mmap_allocator.d)
                version (Posix)
                {
                    import core.sys.posix.sys.mman : mmap, MAP_ANON, PROT_READ, PROT_WRITE, MAP_PRIVATE, MAP_FAILED;
                    auto p = mmap(cast(void*)1U, T.sizeof * qty, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
                    return (p is MAP_FAILED) ? nil : cast(T*)p;
                }
                version (Windows)
                {
                    import core.sys.windows.winnt : MEM_COMMIT, PAGE_READWRITE;
                    return cast(T*)VirtualAlloc(cast(void*)1U, T.sizeof * qty, MEM_COMMIT, PAGE_READWRITE);
                }
                else
                {
                    import core.stdc.stdlib : malloc;
                    return cast(T*)malloc(T.sizeof * qty);
                }
            }
            else
            {
                //Source: $(PHOBOSSRC std/experimental/allocator/mallocator.d)
                version (Posix)
                {
                    void* ptr = void;
                    import core.sys.posix.stdlib : posix_memalign;
                    return (posix_memalign(&ptr, ptrAlignBytes, T.sizeof * qty)) ? nil : cast(T*)ptr;
                }
                else version (Windows)
                {
                    return cast(T*)_aligned_malloc(ptrAlignBytes, T.sizeof * qty);
                }
                else
                {
                    import core.stdc.stdlib : malloc;
                    return cast(T*)malloc(T.sizeof * qty);                    
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

        /*@system void clear(T, const Bit check = false)(CmpsPtr!T ptr) @nogc nothrow
        {
            ptr.erase!(T, check);
            ptr.ptr = nil;
        }*/

        @system void erase(T, const Bit check = false)(T* ptr, const SNr qty = 1)
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
                version (Posix)
                {
                    static if (ptrAlignBytes)
                    {
                        ptr.free;
                    }
                    else
                    {
                        //Source: $(PHOBOSSRC std/experimental/allocator/_mmap_allocator.d)
                        import core.sys.posix.sys.mman : munmap;
                        ptr.munmap(T.sizeof * qty);
                    }
                }
                version (Windows)
                {
                    static if (ptrAlignBytes == 0)
                    {
                        //Source: $(PHOBOSSRC std/experimental/allocator/_mmap_allocator.d)
                        import core.sys.windows.winnt : MEM_RELEASE;
                        ptr.VirtualFree(0, MEM_RELEASE);
                    }
                    else static if (ptrAlignBytes > 0)
                    {
                        //Source: $(PHOBOSSRC std/experimental/allocator/mallocator.d)
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

        /*@system void erase(T, const Bit check = false)(CmpsPtr!T ptr) @nogc nothrow
        {
            ptr.ptr.erase!(T, check);
        }*/

        @trusted T* allocNew(T, Args...)(auto ref Args args)
        {
            import core.lifetime : emplace;
            T* newInstance = alloc!T(1);
            emplace!T(newInstance, forward!args);    
            return newInstance;
        }
    }
}

alias Ptr = CmpsPtr;
alias Mgr = MemoryManager;

static if (USE_GLOBAL_MASK)
{
    pragma(inline, true):
    private
    {
        static if (USE_GLOBAL_MASK > 0)
        {
            PNr _global_mask = -1L;

            @safe Bit checkGlobalMask(SNr shiftBits = COMPRESS_POINTERS ? abs(COMPRESS_POINTERS) - 1 : 0)(const PNr ptr) @nogc nothrow
            {
                enum SHIFT_BITS = (32 + shiftBits);
                if (_global_mask == -1L)
                {
                    _global_mask = (ptr >>> SHIFT_BITS) << SHIFT_BITS;
                    return true;
                }
                else
                {
                    return _global_mask == ((ptr >>> SHIFT_BITS) << SHIFT_BITS);
                }
            }

            @safe PNr applyGlobalMask(const PNr ptr) @nogc nothrow
            {
                return ptr | _global_mask;
            }
        }
        else
        {
            UNr _global_mask = -1;

            @safe Bit checkGlobalMask(SNr shiftBits = COMPRESS_POINTERS ? abs(COMPRESS_POINTERS) - 1 : 0)(const PNr ptr) @nogc nothrow
            {
                enum SHIFT_BITS = (32 + shiftBits);
                if (_global_mask == -1)
                {
                    _global_mask = (ptr >>> SHIFT_BITS) << shiftBits;
                    return true;
                }
                else
                {
                    return _global_mask == ((ptr >>> SHIFT_BITS) << shiftBits);
                }
            }

            @safe PNr applyGlobalMask(const PNr ptr) @nogc nothrow
            {
                return ptr | ((cast(PNr)_global_mask) << 32);
            }
        }
    }

    @safe auto globalMask() @nogc nothrow
    {
        return _global_mask;
    }
}
else
{
    @safe Bit globalMask() @nogc nothrow
    {
        return false;
    }
}

struct IdxHndl(alias array, U = Idx, const Bit compress = true, const Bit implicitCast = COMPRESS_POINTERS > 0, C = void)
{
    private:
    alias O = typeof(array[0]);

    static if (is(C == void))
    {
        alias T = O;
    }
    else
    {
        alias T = C;
    }

    static if (compress && !is(O == const))
    {
        alias P = CmpsPtr!(O, Own.borrowed, Optionality.nonNull, false, true, (COMPRESS_POINTERS > 2
                           ? 3 : (COMPRESS_POINTERS < -1 ? -2 : COMPRESS_POINTERS))); //Arrays can have some tagged low bits;
    }
    else
    {
        alias P = O*;
    }

    @trusted static U findIdx(O* ptr) //@nogc nothrow
    {
        import std.traits;
        static if (isArray!(typeof(array)))
        {
            enum objSize = O.sizeof;
            auto idPtr = cast(PNr)ptr;
            auto arPtr = cast(PNr)array.ptr;
            if (idPtr >= arPtr && idPtr < arPtr + (array.length * objSize))
            {
                return cast(U)((idPtr - arPtr) / objSize);
            }
        }
        else
        {
            const auto arrLn = array.length;
            for (U i = 0; i < arrLn; ++i)
            {
                if (&(array[i]) == ptr)
                {
                    return i;
                }
            }
        }
        return cast(U)-1;
    }

    pragma(inline, true):
    static if (U.sizeof < P.sizeof)
    {
        U _idx = void;

        @safe void copy(T* ptr) //@nogc nothrow
        {
            this._idx = this.findIdx(cast(O*)ptr);
        }

        @trusted void copy(U idx) @nogc nothrow
        {
            assert(idx < array.length, "Index outside of array length.");
            this._idx = idx;
        }
        
        @safe void copy(ref return scope const IdxHndl copy) //@nogc nothrow
        {
            this._idx = copy._idx;
        }

        public:
        @trusted @Dispatch ref T obj() const @nogc nothrow
        {
            return cast(T)array[this._idx];
        }

        @safe T* ptr() const @nogc nothrow
        {
            return &(this.obj());
        }

        @system U index() const @nogc nothrow
        {
            return this._idx;
        }
    }
    else
    {
        private:
        P _ptr = void;
        
        @trusted void copy(U idx) //@nogc nothrow
        {
            this._ptr = &(array[idx]);
        }
        
        @safe void copy(T* ptr) //@nogc nothrow
        {
            this._ptr = cast(O*)ptr;
        }
        
        @safe void copy(ref return scope const IdxHndl copy) //@nogc nothrow
        {
            this._ptr = copy._ptr;
        }

        public:
        @safe @Dispatch ref T obj() const @nogc nothrow
        {
            return *(this.ptr);
        }
        
        @trusted T* ptr() const @nogc nothrow
        {
            return cast(T*)this._ptr;
        }

        @system U index() const //@nogc nothrow
        {
            return findIdx(cast(O*)this._ptr);
        }
    }

    void copy(ref T obj) //@nogc nothrow
    {
        this.copy(&obj);
    }

    public:
    @safe void opAssign(U idx) //@nogc nothrow
    {
        this.copy(idx);
    }

    @safe void opAssign(T* ptr) //@nogc nothrow
    {
        this.copy(ptr);
    }

    @safe void opAssign(ref return scope const IdxHndl copy) //@nogc nothrow
    {
        this.copy(copy);
    }

    /*@trusted void opAssign(ref T obj) @nogc nothrow
    {
        this.copy(obj);
    }*/

    @safe this(U idx) //@nogc nothrow
    {
        this.copy(idx);
    }

    @safe this(T* ptr) //@nogc nothrow
    {
        this.copy(ptr);
    }

    @safe this(ref return scope const IdxHndl copy) //@nogc nothrow
    {
        this.copy(copy);
    }

    /*@system this(ref T obj) @nogc nothrow
    {
        this.copy(obj);
    }*/

    @disable this();
    
    static if (implicitCast)
    {
        alias obj this;
    }
    else
    {
        mixin ForwardTo!obj;
        //mixin ForwardDispatch;

        ref T opCast() const
        {
            return this.obj;
        }
    }
}

enum Dispatch;

mixin template ForwardDispatch(frwAttr = Dispatch)
{
    enum dipsatchMethod = q{
        import std.algorithm.comparison : among;
        foreach (mbr; __traits(allMembers, typeof(this)))
        {
            static if (!mbr.among("__xpostblit", "__xdtor", "__dtor", "__ctor", "opAssign"))
            {
                alias M = typeof(mixin(mbr));
                import std.traits : isCallable;
                static if (isCallable!M)
                {
                    import std.traits : ReturnType;
                    alias F = ReturnType!M;
                }
                else
                {
                    alias F = M;
                }
                import std.traits : isPointer;
                static if (isPointer!F)
                {
                    import std.traits : PointerTarget;
                    alias P = PointerTarget!F;
                }
                else
                {
                    alias P = F;
                }
                import std.traits : isAggregateType;
                static if (isAggregateType!P)
                {
                    import std.traits : hasUDA;
                    static if (hasUDA!(mixin(mbr), frwAttr))
                    {
                        enum argsLen = args.length;
                        static if (argsLen > 0)
                        {
                            static if (argsLen > 1)
                            {
                                import core.lifetime : forward;
                                enum callStmt = "(" ~ q{mixin(mbr ~ "." ~ called ~ "(forward!args)")} ~ ")";
                            }
                            else
                            {
                                enum callStmt = "(" ~ q{mixin(mbr ~ "." ~ called ~ " = args[0]")} ~ ")";
                            }
                        }
                        else
                        {
                            enum callStmt = "(" ~ q{mixin(mbr ~ "." ~ called)} ~ ")";
                        }
                        static if (/*__traits(hasMember, P, called) ||*/__traits(compiles, mixin(callStmt)))
                        {
                            return mixin(callStmt);
                        }
                    }
                }
            }
        }
    };

    auto opDispatch(string called, Args...)(auto ref Args args) const
    {
        mixin(dipsatchMethod);
    }

    auto opDispatch(string called, Args...)(auto ref Args args)
    {
        mixin(dipsatchMethod);
    }
}

mixin template ForwardTo(alias mbr)
{
    enum dispatchMethod = q{
        enum argsLen = args.length;
        static if (argsLen > 0)
        {
            static if (argsLen > 1)
            {
                import core.lifetime : forward;
                return mixin("mbr." ~ called ~ "(forward!args)");
            }
            else
            {
                return mixin("mbr." ~ called ~ " = args[0]");
            }
        }
        else
        {
            return mixin("mbr." ~ called);
        }
    };

    auto opDispatch(string called, Args...)(auto ref Args args) const
    {
        mixin(dispatchMethod);
    }

    auto opDispatch(string called, Args...)(auto ref Args args)
    {
        mixin(dispatchMethod);
    }
}

alias Hnd = IdxHndl;