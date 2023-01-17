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
alias S8 = byte;
alias U8 = ubyte;
alias Bit = bool;
alias Raw(T) = T*;
alias Vct = Array;
alias F32 = float;
alias S16 = short;
alias U16 = ushort;
alias ZNr = size_t;
alias PNr = uintptr_t;
alias Nil = typeof(nil);
alias Str = const(char)*;
alias DPt = ptrdiff_t;
alias F64 = double;
alias Txt = char*;
alias U64 = ulong;
alias S64 = long;
alias Chr = char;
alias U32 = uint;
alias S32 = int;
alias UNr = U32;
alias SNr = S32;
alias Dec = F32;
alias Idx = U16;
alias SBt = S8;
alias UBt = U8;
alias Nr = SNr;

struct ListPtr
{
    protected:
    Raw!void _ptr = void;
    UNr _cnt = void;

    pragma(inline, true):
    void clear(const UNr idx) @nogc nothrow
    {
        this._ptr = nil;
        if (idx < _ptr_index)
        {
            _ptr_index = idx;
        }
    }

    public:
    void ptr(Raw!void ptr) @nogc nothrow
    {
        this._ptr = ptr;
        this._cnt = 0U;
    }

    Raw!void ptr() const @nogc nothrow
    {
        return this._ptr;
    }

    UNr count() const @nogc nothrow
    {
        return this._cnt;
    }

    UNr decrease(const UNr idx = 0U) @nogc nothrow
    {
        auto cnt = this._cnt;
        if (cnt)
        {
            this._cnt = --cnt;
        }
        else
        {
            this.clear(idx);
        }
        return cnt;
    }

    UNr increase() @nogc nothrow
    {
        const auto cnt = this._cnt + 1U;
        this._cnt = cnt;
        return cnt;
    }

    PNr toHash() const @nogc nothrow
    {
        return cast(PNr)this._ptr;
    }

    SNr opCmp(const ListPtr other) const @nogc nothrow
    {
        return this._ptr - other._ptr;
    }

    Bit opEquals(const ListPtr other) const @nogc nothrow
    {
        return this._ptr == other._ptr;
    }

    this(Raw!void ptr) @nogc nothrow
    {
        this.ptr = ptr;
        this._cnt = 0U;
    }

    alias ptr this;
}

private
{
    Vct!ListPtr _ptr_list; //TODO: multiple thread shared access safety and analyze better solutions
    UNr _ptr_index = 0U;
}

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

struct CmpsPtr(T, const Own own = Own.sharedCounted, const Opt opt = Opt.nullable, const Bit initialize = true,
               const Bit implicitCast = opt > 0 && !own, const SNr cmpsType = COMPRESS_POINTERS, U = UNr)
{
    enum _copyable = __traits(isCopyable, T);
    enum _constructible = initialize && __traits(compiles, T());
    static assert (own != Own.cowCounted || _copyable, "Only copyable types can have copy-on-write pointers.");
    static assert (cmpsType < 1 || (!(is(typeof(this) == shared) || is(T == shared))), "Compressed pointers cannot be shared.");

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
                        this.resetCount;
                    }
                }
            }
        }
    }

    public pragma(inline, true)
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
        import std.algorithm.searching : canFind;
        static if ([__traits(allMembers, T)[]].canFind("resetCount", "increase", "decrease", "refCount"))
        {
            mixin RefCounted!(false, self.addr, cmpsType);
        }
        else
        {
            mixin RefCounted!(false, void, cmpsType);
        }

        static if (_copyable)
        {
            pragma(inline, true)
            public @trusted void detach()
            {
                if (this.refCount > 1U)
                {
                    this.ptr = Mgr!cmpsType.allocNew!T(*this.addr);
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
                        this.resetCount;
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
        enum _SHIFT_LEN = cmpsType - 2;
        enum _ONLY_LIST = _SHIFT_LEN < 0;
        private U _ptr = 0U;

        @system private static Bit clearList(U ptr)
        {
            if (ptr == 0U)
            {
                return false;
            }
            if (_ONLY_LIST || (ptr & 1U) == 1U)
            {
                auto ptrList = &_ptr_list;
                static if (!_ONLY_LIST)
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
                    while ((ptrListLen = ptrList.length) > 0 && (--ptr) == ptrListLen && (*ptrList)[ptr - 1U].ptr == nil);
                }
                else
                {
                    const auto idx = ptr - 1U;
                    (*ptrList)[idx].decrease(idx);
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
                    static if (_ONLY_LIST)
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
                        static if (_ONLY_LIST)
                        {
                            return cast(T*)_ptr_list[ptr - 1U];
                        }
                        else
                        {
                            if ((ptr & 1U) == 1U)
                            {
                                return cast(T*)_ptr_list[(ptr >>> 1) - 1U].ptr;
                            }
                            else
                            {
                                static if (USE_GLOBAL_MASK)
                                {
                                    return cast(T*)applyGlobalMask((cast(PNr)ptr) << _SHIFT_LEN);
                                }
                                else
                                {
                                    return cast(T*)((cast(PNr)ptr) << _SHIFT_LEN);
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
                if (_ONLY_LIST || (oldPtr & 1U) == 1U)
                {
                    static if (!_ONLY_LIST)
                    {
                        oldPtr >>>= 1;
                    }
                    UNr idx = void;
                    if (oldPtr > 0U && !((*ptrList)[(idx = oldPtr - 1U)].decrease(idx)))
                    {
                        
                        (*ptrList)[idx] = ListPtr(ptr);
                        return;
                    }
                }
            }
            UNr ptrLength = cast(UNr)ptrList.length;
            for (UNr i = _ptr_index; i < ptrLength; i += 1U)
            {
                auto lPtr = (*ptrList)[i];
                do
                {
                    if (lPtr.ptr == nil)
                    {
                        (*ptrList)[i].ptr = ptr;
                    }
                    else if (lPtr.ptr != ptr)
                    {
                        break;
                    }
                    (*ptrList)[i].increase;
                    static if (_ONLY_LIST)
                    {
                        this._ptr = i + 1U;
                    }
                    else
                    {
                        this._ptr = ((i + 1U) << 1U) | 1U;
                    }
                    return;
                }
                while(false);
            }
            ptrList.insert(ListPtr(ptr));
            static if (_ONLY_LIST)
            {
                this._ptr = cast(U)(++ptrLength);
            }
            else
            {
                this._ptr = cast(U)(((++ptrLength) << 1U) | 1U);
            }
            _ptr_index = ptrLength;
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
                            this.resetCount;
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
                    this.resetCount;
                }
            }
            static if (_ONLY_LIST)
            {
                this.listPtr!remove(ptr);
            }
            else
            {
                const PNr ptrNr = cast(PNr)ptr;
                static if (USE_GLOBAL_MASK)
                {
                    const bool ptrCheck = checkGlobalMask!_SHIFT_LEN(ptrNr);
                }
                else
                {
                    const bool ptrCheck = ptrNr < (4294967296UL << _SHIFT_LEN);
                }
                if (ptrCheck)
                {
                    static if (own < 1)
                    {
                        clearList(this._ptr);
                    }
                    this._ptr = cast(U)(ptrNr >>> _SHIFT_LEN);
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
     
        enum _SHIFT_LEN = -(cmpsType + 1);

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
                        return cast(T*)applyGlobalMask((cast(PNr)ptr) << _SHIFT_LEN);
                    }
                }
                else
                {
                    return cast(T*)((cast(PNr)this._ptr) << _SHIFT_LEN);
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
                        if (checkGlobalMask!_SHIFT_LEN(ptrNr))
                        {
                            this._ptr = cast(U)(ptrNr >>> _SHIFT_LEN);
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
                    this._ptr = cast(U)((cast(PNr)ptr) >>> _SHIFT_LEN);
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
        static if (opt < 1)
        {
            mixin DispatchTo!obj;
            //mixin ForwardDispatch;
        }

        auto opCast() const
        {
            return this.ptr;
        }
    }

    public pragma(inline, true):
    static if (opt)
    {
        private @system void copy(const Bit remove = true)(ref return scope const CmpsPtr!(T,
                                    own, Opt.nonNull, initialize, implicitCast, cmpsType, U) copy) //@nogc nothrow
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

        static if (own < -1)
        {
            @trusted void opAssign(ref return scope CmpsPtr!(T, own, Opt.nonNull, initialize, implicitCast, cmpsType, U) copy)
            {
                auto oPtr = this._ptr;
                this.copy!true(forward!copy);
                copy._ptr = oPtr;
            }

            @trusted this(ref return scope CmpsPtr!(T, own, Opt.nonNull, initialize, implicitCast, cmpsType, U) copy) //@nogc nothrow
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

        static if (own > -1)
        {
            @trusted void opAssign(const CmpsPtr!(T, own, Opt.nonNull, initialize, implicitCast, cmpsType, U) copy)
            {
                this.copy!true(forward!copy);
            }

            @trusted this(const CmpsPtr!(T, own, Opt.nonNull, initialize, implicitCast, cmpsType, U) copy)
            {
                this.copy!false(forward!copy);
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

    private @system void incListCnt() @nogc nothrow
    {
        static if (cmpsType > 0)
        {
            auto idx = this._ptr;
            static if (_ONLY_LIST)
            {
                (_ptr_list)[idx - 1U].increase;
            }
            else
            {                
                if ((idx & 1U) == 1U)
                {
                    (_ptr_list)[(idx >>> 1U) - 1U].increase;
                }
            }
        }
    }

    static if (own > 0)
    {
        private @system void copy(ref return scope const CmpsPtr copy) //@nogc nothrow
        {
            //this.count = nil;
            this.incListCnt;
            this.count = copy.count;
            this.increase;
        }

        static if (opt > -1)
        {
            @trusted void opAssign(const CmpsPtr copy)
            {
                this.ptr = copy.addr;
                this.copy(forward!copy);
            }
        }

        @trusted this(ref return scope const CmpsPtr copy) //@nogc nothrow
        {
            this.ptr!(T, false) = copy.addr;
            //this.copy(forward!copy);
            this.incListCnt;
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
                this.incListCnt;
                this.ptr!(T, remove) = copy.addr;
            }
            else
            {
                this._ptr = copy._ptr;
            }
        }
        static if (opt > -1)
        {
            @trusted void opAssign(const CmpsPtr copy)
            {
                this.copy!true(forward!copy);
            }
        }

        @trusted this(ref return scope const CmpsPtr copy) //@nogc nothrow
        {
            this.copy!false(forward!copy);
        }
    }
    else static if (own == -1)
    {
        @disable void opAssign(CmpsPtr copy);
        @disable void opAssign(const CmpsPtr copy);
        @disable void opAssign(ref return scope const CmpsPtr copy);
        @disable void opAssign(ref return scope CmpsPtr copy);
        @disable this(ref return scope const CmpsPtr copy);
        @disable this(ref return scope CmpsPtr copy);
    }
    else static if (own < -1)
    {
        @disable this(ref return scope const CmpsPtr copy); //@nogc nothrow
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
        static if (opt > -1)
        {
            @disable void opAssign(const CmpsPtr copy);
            @disable void opAssign(ref return scope const CmpsPtr copy);
            @trusted void opAssign(ref return scope CmpsPtr copy)
            {
                //static assert(own != -1, "Cannot reassign unique pointer.");
                auto oPtr = this._ptr;
                this._ptr = copy._ptr;
                copy._ptr = oPtr;
            }
        }
    }

    static if (opt < 0 && own != -1)
    {
        @disable void opAssign(CmpsPtr copy);
        @disable void opAssign(const CmpsPtr copy);
        @disable void opAssign(ref return scope const CmpsPtr copy);
        @disable void opAssign(ref return scope CmpsPtr copy);
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
        static if (_copyable)
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

        auto borrow(const Bit initialize = initialize, const Bit implicitCast = implicitCast)() const
        {
            return CmpsPtr!(T, Own.borrowed, Opt.nullable, initialize, implicitCast, cmpsType)(this._ptr);
        }

        auto borrowNonNull(const Bit initialize = initialize, const Bit implicitCast = implicitCast)() const
        {
            return CmpsPtr!(T, Own.borrowed, Opt.nonNull, initialize, implicitCast, cmpsType)(this.nonNullPtr);
        }

        auto borrowNonNull(const Bit initialize = initialize, const Bit implicitCast = implicitCast)()
        {
            //this.obj;
            return CmpsPtr!(T, Own.borrowed, Opt.nonNull, initialize, implicitCast, cmpsType)(this.nonNullPtr);
        }

        auto borrowOrNew(const Bit initialize = initialize, const Bit implicitCast = implicitCast, Args...)(auto ref Args args)
        {
            return CmpsPtr!(T, Own.borrowed, Opt.nonNull, initialize, implicitCast, cmpsType)(this.nonNullPtrOrNew(forward!args));
        }

        auto borrowOrElse(const Bit initialize = initialize, const Bit implicitCast = implicitCast, F, Args...)(F fn, auto ref Args args)
        {
            
            return CmpsPtr!(T, Own.borrowed, Opt.nonNull, initialize, implicitCast, cmpsType)(this.nonNullPtrOrElse(fn, forward!args));
        }

        static if (opt)
        {
            @Dispatch ref T obj()
            {
                auto ptr = this.ptr;
                static if (_constructible)
                {
                    if (ptr == nil)
                    {
                        ptr = Mgr!cmpsType.allocNew!T;
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
                static if (_constructible)
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

            private
            {
                auto nonNullPtr() const
                {
                    auto ptr = this._ptr;
                    assert(ptr, "Non-nullable pointers cannot be null.");
                    return ptr;
                }

                auto nonNullPtr()
                {
                    auto ptr = this._ptr;
                    static if (_constructible)
                    {
                        if (ptr)
                        {
                            static if (own == 1)
                            {
                                this.detach;
                            }
                        }
                        else
                        {
                            this.ptr = Mgr!cmpsType.allocNew!T;
                            return this._ptr;
                        }
                    }
                    else
                    {
                        assert(ptr, "Non-nullable pointers cannot be null.");
                    }
                    return ptr;
                }

                auto nonNullPtrOrNew(Args...)(auto ref Args args)
                {
                    auto ptr = this._ptr;
                    if (ptr)
                    {
                        static if (own == 1)
                        {
                            this.detach;
                        }
                        return ptr;
                    }
                    else
                    {
                        this.ptr = Mgr!cmpsType.allocNew!T(forward!args);
                        return this._ptr;
                    }
                }

                auto nonNullPtrOrElse(F, Args...)(F fn, auto ref Args args)
                {
                    auto ptr = this._ptr;
                    if (ptr)
                    {
                        static if (own == 1)
                        {
                            this.detach;
                        }
                        return ptr;
                    }
                    else
                    {
                        this.ptr = fn(forward!args);
                        return this.nonNullPtr;
                    }
                }
            }

            static if (own < 1) @system
            {
                T* swapPtr(T* newPtr)
                {
                    auto ptr = this.addr;
                    this.ptr!(T, false) = newPtr;
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

            private
            {
                auto nonNullPtr() const
                {
                    return this._ptr;
                }

                auto nonNullPtrOrNew(Args...)(auto ref Args args)
                {
                    return this._ptr;
                }

                auto nonNullPtrOrElse(F, Args...)(F fn, auto ref Args args)
                {
                    return this._ptr;
                }
            }
        }

        @Dispatch ref auto obj() const @nogc nothrow
        {
            static if (opt)
            {
                auto ptr = this.ptr;
                assert(ptr, "References cannot be null.");
                return *cast(const T*)ptr;
            }
            else
            {
                return *cast(const T*)this.ptr;
            }
        }
        
        @system 
        {
            private auto self() const
            {
                return (cast(CmpsPtr*)(&this));
            }
            
            ref T mutObj() const //@nogc nothrow
            {
                static if (own == 1)
                {
                    self.detach;
                }
                static if (opt)
                {
                    auto ptr = this.addr;
                    assert(ptr, "References cannot be null.");
                    return *ptr;
                }
                else
                {
                    return *this.addr;
                }
            }

            ref T mutObj() //@nogc nothrow
            {
                return this.obj;
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

                auto getNonNull(const Bit initialize = initialize, const Bit implicitCast = implicitCast)()
                {
                    auto cmpsPtr = CmpsPtr!(T, own, Opt.nonNull, initialize, implicitCast, cmpsType)(this._ptr);
                    this.applyCopy(cmpsPtr);
                    return cmpsPtr;
                }
            }

            auto nonNull(const Bit initialize = initialize, const Bit implicitCast = implicitCast)()
            {
                static if (opt)
                {
                    if (this.isNil)
                    {
                        static if (_constructible)
                        {
                            this.ptr = Mgr!(cmpsType).allocNew!T;
                        }
                        else
                        {
                            assert(0, "References cannot be null.");
                        }
                    }
                }
                return this.getNonNull!(initialize, implicitCast);
            }

            auto nonNullOrNew(const Bit initialize = initialize, const Bit implicitCast = implicitCast, Args...)(auto ref Args args)
            {
                this.addrOrNew(forward!args);
                return this.getNonNull!(initialize, implicitCast);
            }

            auto nonNullOrElse(const Bit initialize = initialize, const Bit implicitCast = implicitCast, F, Args...)(F fn, auto ref Args args)
            {
                this.addrOrElse(fn, forward!args);
                return this.nonNull!(initialize, implicitCast);
            }

            auto nullable(const Bit initialize = initialize, const Bit implicitCast = implicitCast)()
            {
                auto cmpsPtr = CmpsPtr!(T, own, Opt.nullable, initialize, implicitCast, cmpsType)(this._ptr);
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

        @system void erase(T, const Bit check = false, const Bit destruct = true)(T* ptr, const SNr qty = 1)
        {
            static if (check)
            {
                if (ptr == nil) return;
            }
            static if (destruct)
            {
                (*ptr).destroy;
            }
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
                return ptr | ((cast(PNr)_global_mask) << 32UL);
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

        @trusted T* ptr() const @nogc nothrow
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

    @safe void opAssign(const IdxHndl copy) //@nogc nothrow
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
        mixin DispatchTo!obj;
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
                        static if (__traits(hasMember, P, called) || __traits(compiles, mixin(callStmt)))
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

mixin template DispatchTo(alias mbr)
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

string _forwardMethods(T, O)(string field) //inspired by "forwardToMember" from $(PHOBOSSRC std/experimental/allocator/common.d)
{
    import std.ascii : isUpper;
    import std.algorithm : startsWith;
    import std.algorithm.comparison : among;
    string ret = "import std.traits : Parameters; pragma(inline, true) {";
    foreach (string mbr; __traits(allMembers, T))
    {
        static if ((!mbr.startsWith("_")) && !(mbr.startsWith("op") && mbr.length > 2 && mbr[2].isUpper)
            && __traits(getVisibility, mixin("T." ~ mbr)) != "private" && !__traits(hasMember, O, mbr))
        {
            ret ~= "static if (is(typeof(" ~ field ~ "." ~ mbr ~ ") == function))
                    {
                        auto ref " ~ mbr ~ "(Parameters!(typeof(" ~ field ~ "." ~ mbr ~ ")) args)
                        {
                            return " ~ field ~ "." ~ mbr ~ "(args);
                        }
                    }
                    else
                    {
                        auto ref " ~ mbr ~ "()
                        {
                            return " ~ field ~ "." ~ mbr ~ ";
                        }
                    }\n";
        }
    }
    return ret ~ "}";
}

mixin template ForwardTo(Fields...)
{
    static assert(Fields.length > 0, "Forwarded fields have not been specified.");
    import std.traits : isCallable;
    import std.traits : isPointer;
    static foreach(mbr; Fields)
    {
        static if (isCallable!mbr)
        {
            import std.traits : ReturnType;
            static if (isPointer!(ReturnType!(typeof(mbr))))
            {
                import std.traits : PointerTarget;
                mixin(_forwardMethods!(PointerTarget!(ReturnType!(typeof(mbr))), typeof(this))(mbr.stringof));
            }
            else
            {
                mixin(_forwardMethods!(ReturnType!(typeof(mbr)), typeof(this))(mbr.stringof));
            }
        }
        else static if (isPointer!(typeof(mbr)))
        {
            import std.traits : PointerTarget;
            mixin(_forwardMethods!(PointerTarget!(typeof(mbr)), typeof(this))(mbr.stringof));
        }
        else
        {
            mixin(_forwardMethods!(typeof(mbr), typeof(this))(mbr.stringof));
        }
    }
}

mixin template SelfConstMutPointer()
{
    private auto self() const
    {
        import std.traits : Unqual;
        return (cast(Unqual!(typeof(this))*)(&this));
    }
}

mixin template RefCounted(const Bit construct = true, alias F = UNr, const SNr cmpsType = COMPRESS_POINTERS)
{
    protected:
    static if (is(F == void))
    {
        CmpsPtr!(ZNr, Own.borrowed, Opt.nullable, false) count = nil;//void;
        enum cmpsPtr = 1;
    }
    else
    {
        static if (__traits(isIntegral, F))
        {
            enum cmpsPtr = 0;
            F count = 1U;
        }
        else
        {
            enum cmpsPtr = -1;
        }
    }

    mixin SelfConstMutPointer;

    static if (construct)
    {
        pragma(inline, true) this(this)
        {
            self.resetCount;
        }
    }

    static if (cmpsPtr > 0)
    {
        pragma(inline, true)
        {
            public @trusted auto refCount() const @nogc nothrow
            {
                auto cPtr = self.count.ptr;
                if (cPtr)
                {
                    return *(cPtr);
                }
                else
                {
                    return 0U;
                }
            }

            @system void resetCount() //@nogc nothrow
            {
                self.count.ptr = Mgr!cmpsType.allocNew!ZNr(1);
            }
            
            @system void increase() //@nogc nothrow 
            {
                auto cntPtr = self.count.ptr;
                if (cntPtr)
                {
                    (*cntPtr) += 1U;
                }
            }
        }

        @system void decrease() //@nogc nothrow
        {
            auto count = &(self.count);
            auto cntPtr = count.ptr;
            if (cntPtr)
            {
                const auto cntNr = *cntPtr;
                if (cntNr == 1U)
                {
                    self.clean;
                    count.ptr!ZNr = nil;
                    Mgr!cmpsType.erase!(ZNr, false, false)(cntPtr);
                }
                else
                {
                    (*cntPtr) = cntNr - 1U;
                }
            }
        }
    }
    else static if (cmpsPtr < 0)
    {
        pragma(inline, true)
        {
            @trusted UNr count() const @nogc nothrow { return 0U; }

            @trusted void count(const UNr _) const @nogc nothrow {}

            public @trusted auto refCount() const @nogc nothrow
            {
                return F.refCount;
            }

            @trusted void resetCount() const @nogc nothrow {}
            
            @trusted void increase() const @nogc nothrow 
            {
                F.increase;
            }

            @system void decrease() const //@nogc nothrow
            {
                if (F.decrease)
                {
                    self.clean;
                }
            }
        }
    }
    else
    {
        public pragma(inline, true)
        {
            @trusted auto refCount() const @nogc nothrow
            {
                return this.count;
            }

            @system void resetCount() const @nogc nothrow
            {
                self.count = 1U;
            }
            
            @system void increase() const @nogc nothrow 
            {
                self.count += 1U;
            }

            @system Bit decrease() const @nogc nothrow
            {
                return ((--(self.count)) == 0U);
            }
        }
    }
}

alias Hnd = IdxHndl;