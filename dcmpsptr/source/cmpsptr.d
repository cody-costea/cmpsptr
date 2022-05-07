/*
Copyright (C) AD 2022 Claudiu-Stefan Costea

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/
module cmpsptr;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.stdint;
import std.container.array : Array;
/*
If the COMPRESS_POINTERS enum is set to a non-zero value, 64bit pointers will be compressed into 32bit integers, according to the following options:
    +4 can compress addresses up to 32GB, at the expense of the 4 lower tag bits, which can no longer be used for other purporses
    +3 can compress addresses up to 16GB, at the expense of the 3 lower tag bits, which can no longer be used for other purporses
    +2 can compress addresses up to 8GB, at the expense of the 2 lower tag bits, which can no longer be used for other purporses
    +1 can compress addresses up to 4GB, at the expense of the lower tag bit, which can no longer be used for other purporses
Attempting to compress an address higher than the mentioned limits, will lead however to increased CPU and RAM usage and cannot be shared between threads;
The following negative values can also be used, but they are not safe and will lead to crashes, when the memory limits are exceeded:
    -5 can compress addresses up to 64GB, at the expense of the 4 lower tag bits, which can no longer be used for other purporses
    -4 can compress addresses up to 32GB, at the expense of the 3 lower tag bits, which can no longer be used for other purporses
    -3 can compress addresses up to 16GB, at the expense of the 2 lower tag bits, which can no longer be used for other purporses
    -2 can compress addresses up to 8GB, at the expense of the lower tag bit, which can no longer be used for other purporses
    -1 can compress addresses up to 4GB, leaving the 3 lower tag bits to be used for other purporses
*/
enum COMPRESS_POINTERS = (void*).sizeof < 8 ? 0 : -4;

enum nil = null;
alias S8 = byte;
alias U8 = ubyte;
alias Bit = bool;
alias SBt = byte;
alias UBt = ubyte;
alias Idx = ubyte;
alias Dec = float;
alias Vct = Array;
alias Flt = float;
alias SSr = short;
alias S16 = short;
alias U16 = ushort;
alias USr = ushort;
alias Dbl = double;
alias ZNr = size_t;
alias DNr = ptrdiff_t;
alias PNr = uintptr_t;
alias Str = const(char)*;
alias Txt = char*;
alias U64 = ulong;
alias ULn = ulong;
alias SLn = long;
alias S64 = long;
alias Chr = char;
alias UNr = uint;
alias U32 = uint;
alias S32 = int;
alias SNr = int;
alias Nr = SNr;

//static if (COMPRESS_POINTERS > 0)
//{
    private Vct!(void*) _ptrList; //TODO: multiple thread shared access safety and analyze better solutions
//}

/*private
{
    void* ptr(UNr ptr)
    {
        if (ptr == 0U)
        {
            return nil;
        }
        //PNr ptrNr = void;
        else if ((ptr & 1U) == 1U)
        {
            return cast(void*)_ptrList[(ptr >>> 1) - 1U];
        }
        else
        {
            //ptrNr = (cast(PNr)ptr) << SHIFT_LEN;
            return cast(void*)((cast(PNr)ptr) << SHIFT_LEN);
        }
        //return cast(void*)((ptrNr & ((1UL << 48) - 1UL)) | ~((ptrNr & (1UL << 47)) - 1UL));
    }

    UNr listPtr(void* ptr)
    {
        UNr oldPtr = this._ptr;
        auto ptrList = &_ptrList;
        if ((oldPtr & 1U) == 1U)
        {
            oldPtr >>>= 1;
            if (oldPtr > 0U)
            {
                (*ptrList)[oldPtr - 1U] = ptr;
                return;
            }
        }
        size_t ptrLength = ptrList.length;
        for (UNr i = 0; i < ptrLength; i += 1U)
        {
            if ((*ptrList)[i] == nil)
            {
                (*ptrList)[i] = ptr;
                this._ptr = (i << 1U) | 1U;
                return;
            }
        }
        ptrList.insert(ptr);
        return cast(UNr)(((ptrLength + 1) << 1) | 1);
    }

    void ptr(void* ptr)
    {
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
                else
                {
                    this.clean;
                }
            }
            else
            {
                return;
            }
        }
        PNr ptrNr = cast(PNr)ptr; //<< 16) >>> 16;
        if (ptrNr < (4294967296UL << SHIFT_LEN))
        {
            static if (own < 0)
            {
                clearList(this._ptr);
            }
            this._ptr = cast(UNr)(ptrNr >>> SHIFT_LEN);
        }
        else
        {
            this.listPtr(ptr);
        }
    }
}*/

struct CmpsPtr(T, const SNr own = 0, const SNr cmpsType = COMPRESS_POINTERS)
{
    static if (own != 0 && cmpsType > 0)
    {
        pragma(inline, true)
        @system protected void clean() @nogc nothrow
        {
            this.ptr.erase;
            //T* ptr = this.ptr;
            //(&(ptr)).clear;
            static if (cmpsType > 0)
            {
                clearList(this._ptr);
            }
            //GC.removeRange(ptr);
        }
    }
    
    static if (own > 0)
    {
        protected CmpsPtr!(size_t, 0, cmpsType == 0 ? 0 : (cmpsType > 0 ? 3 : -4)) count = void;

        pragma(inline, true)
        {
            protected
            {
                @system void reset() @nogc nothrow
                {
                    size_t* countPtr = alloc!size_t;
                    (*countPtr) = 0;
                    this.count.ptr(countPtr);
                }
                
                @system void increase() @nogc nothrow 
                {
                    auto cntPtr = this.count.ptr;
                    if (cntPtr)
                    {
                        (*cntPtr) += 1;
                    }
                }
            }
        }

        @system protected void decrease() @nogc nothrow
        {
            auto count = &this.count;
            auto cntPtr = count.ptr;
            if (cntPtr)
            {
                const auto cntNr = *cntPtr;
                if (cntNr == 1)
                {
                    this.clean;
                    count.ptr = nil;
                    cntPtr.free;
                }
                else
                {
                    (*cntPtr) = cntNr - 1;
                }
            }
        }
    }
    
    static if (cmpsType == 0)
    {
        public T* ptr = void;
    }
    else static if (cmpsType > 0)
    {
        enum SHIFT_LEN = cmpsType > 3 ? 3 : (cmpsType - 1);
        private UNr _ptr = 0U;

        @system private static bool clearList(UNr ptr) @nogc nothrow
        {
            if (ptr == 0U)
            {
                return false;
            }
            if ((ptr & 1U) == 1U)
            {
                auto ptrList = &_ptrList;
                ptr >>>= 1;
                
                if (ptr == ptrList.length)
                {
                    size_t ptrListLen = void;
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
                @safe bool compressed() @nogc nothrow
                {
                    return (this._ptr & 1U) != 1U;
                }

                @system T* ptr() @nogc nothrow
                {
                    const UNr ptr = this._ptr;
                    if (ptr == 0U)
                    {
                        return nil;
                    }
                    //PNr ptrNr = void;
                    else if ((ptr & 1U) == 1U)
                    {
                        return cast(T*)_ptrList[(ptr >>> 1) - 1U];
                    }
                    else
                    {
                        //ptrNr = (cast(PNr)ptr) << SHIFT_LEN;
                        return cast(T*)((cast(PNr)ptr) << SHIFT_LEN);
                    }
                    //return cast(T*)((ptrNr & ((1UL << 48) - 1UL)) | ~((ptrNr & (1UL << 47)) - 1UL));
                }
            }
        }

        @system private void listPtr(T* ptr) @nogc nothrow
        {
            UNr oldPtr = this._ptr;
            auto ptrList = &_ptrList;
            if ((oldPtr & 1U) == 1U)
            {
                oldPtr >>>= 1;
                if (oldPtr > 0U)
                {
                    (*ptrList)[oldPtr - 1U] = ptr;
                    return;
                }
            }
            size_t ptrLength = ptrList.length;
            for (UNr i = 0; i < ptrLength; i += 1U)
            {
                if ((*ptrList)[i] == nil)
                {
                    (*ptrList)[i] = ptr;
                    this._ptr = (i << 1U) | 1U;
                    return;
                }
            }
            ptrList.insert(ptr);
            this._ptr = cast(UNr)(((ptrLength + 1) << 1) | 1);
        }

        pragma(inline, true)
        @system public void ptr(T* ptr) @nogc nothrow
        {
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
                    else
                    {
                        this.clean;
                    }
                }
                else
                {
                    return;
                }
            }
            const PNr ptrNr = cast(PNr)ptr; //<< 16) >>> 16;
            if (ptrNr < (4294967296UL << SHIFT_LEN))
            {
                static if (own < 0)
                {
                    clearList(this._ptr);
                }
                this._ptr = cast(UNr)(ptrNr >>> SHIFT_LEN);
            }
            else
            {
                this.listPtr(ptr);
            }
        }
        /*pragma(inline, true):
        this(this)
        {
            T* ptr = this.ptr;
            this._ptr = 0U;
            this.ptr = ptr;
        }*/        

        static if (own < 0)
        {
            pragma(inline, true)
            @system ~this() @nogc nothrow
            {
                this.clean;
            }
        }
        else
        {
            pragma(inline, true)
            @system ~this() @nogc nothrow
            {
                static if (own < 1)
                {
                    //this._ptr.clearList;
                    clearList(this._ptr);
                }
                else
                {
                    this.decrease;
                }
            }
        }
    }
    else
    {
        private UNr _ptr = void;
     
        enum SHIFT_LEN = cmpsType < -4 ? 4 : -(cmpsType + 1);

        pragma(inline, true)
        {
            public:
            @safe bool compressed() @nogc nothrow
            {
                return true;
            }
            
            @system T* ptr() @nogc nothrow
            {
                /*UNr ptr = this._ptr;
                if (ptr == 0U)
                {
                    return nil;
                }
                else
                {
                    PNr ptrNr = (cast(PNr)ptr) << SHIFT_LEN;
                    return cast(T*)((ptrNr & ((1UL << 48) - 1UL)) | ~((ptrNr & (1UL << 47)) - 1UL));
                }*/
                //printf("this._ptr = %d\n", this._ptr);
                //printf("SHIFT_LEN = %d\n", SHIFT_LEN);
                //printf("%d << %d = %d\n", this._ptr, SHIFT_LEN, ((cast(PNr)this._ptr) << SHIFT_LEN));
                return cast(T*)((cast(PNr)this._ptr) << SHIFT_LEN);
            }
            
            @system void ptr(const T* ptr) @nogc nothrow
            {
                /*if (ptr == nil)
                {
                    this._ptr = 0U;
                }
                else
                {*/
                    static if (own > 0)
                    {
                        if (ptr != this.ptr)
                        {
                            this.decrease;
                            this.reset;
                        }
                    }
                    PNr ptrNr = cast(PNr)ptr;
                    //printf("PNr = %d\n", ptrNr);
                    //PNr ptrNr = (cast(PNr)ptr << 16) >>> 16;
                    //assert(ptrNr < (4294967296UL << SHIFT_LEN)); //TODO: analyze alternative solutions
                    this._ptr = cast(UNr)(ptrNr >>> SHIFT_LEN);
                //}
            }
        }
        
        static if (own < 0)
        {
            pragma(inline, true):
            @system ~this() @nogc nothrow
            {
                this.clean;
            }
        }
        else static if (own > 0)
        {
            pragma(inline, true)
            @system ~this() @nogc nothrow
            {
                this.decrease;
            }
        }
    }
    
    alias ptr this;

    static if (own > 0)
    {
        @disable this(this);
        
        pragma(inline, true)
        @system this(ref return scope CmpsPtr copy) @nogc nothrow
        {
            //this.count = nil;
            this.ptr = copy.ptr;
            static if (own > 0)
            {
                this.count = copy.count;
                this.increase;
            }
        }
    }
    else static if (own < 0)
    {
        @disable this(this);
        
        @disable this(ref return scope CmpsPtr copy);
    }
            
    pragma(inline, true)
    @system this(T* ptr) @nogc nothrow
    {
        static if (own > 0)
        {
            this.count = nil;
        }
        this.ptr = ptr;
    }
}

pragma(inline, true)
{
    @system T* alloc(T)(const SNr qty = 1) @nogc nothrow
    {
        return cast(T*)malloc(T.sizeof * qty);
    }

    @system void clear(T, const bool check = false)(T** ptr) @nogc nothrow
    {
        static if (check)
        {
            if (ptr == nil) return;
        }
        (*ptr).erase!(T, check);
        (*ptr) = nil;
    }

    @system void clear(T, const bool check = false)(CmpsPtr!T ptr) @nogc nothrow
    {
        ptr.erase!(T, check);
        ptr.ptr = nil;
    }

    @system void erase(T, const bool check = false)(T* ptr) @nogc nothrow
    {
        static if (check)
        {
            if (ptr == nil) return;
        }
        (*ptr).destroy;
        ptr.free;
    }

    @system void erase(T, const bool check = false)(CmpsPtr!T ptr) @nogc nothrow
    {
        ptr.ptr.erase!(T, check);
    }
}

alias Ptr = CmpsPtr;

struct IdxHndl(T, string array, U = UNr)
{
    private U _idx = void;

    public:
    pragma(inline, true)
    {
        @system ref T obj() @nogc nothrow
        {
            mixin("return " ~ array ~ "[this._idx];");
        }
        
        @safe this(U idx) @nogc nothrow
        {
            this._idx = idx;
        }
        
        /*@safe this(ref return scope IdxHndl copy) @nogc nothrow
        {
            this._idx = copy.idx;
        }*/

        @disable this();
    }
    
    alias obj this;
}

alias Hnl = IdxHndl;