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
enum COMPRESS_POINTERS = (void*).sizeof < 8 ? 0 : 4;

enum nil = null;
alias I8 = byte;
alias U8 = ubyte;
alias Bit = bool;
alias SBt = byte;
alias UBt = ubyte;
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
alias Idx = U8;
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
        ZNr ptrLength = ptrList.length;
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
    static if (own != 0)
    {
        pragma(inline, true)
        @system protected void clean()
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
        protected CmpsPtr!(ZNr, 0, cmpsType == 0 ? 0 : (cmpsType > 0 ? 4 : -5)) count = void;        

        pragma(inline, true)
        {
            public ZNr refCount()
            {
                return *(this.count.ptr);
            }

            protected
            {
                @system void reset() //@nogc nothrow
                {
                    ZNr* countPtr = alloc!ZNr;
                    (*countPtr) = 0;
                    this.count.ptr(countPtr);
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

        @system private static Bit clearList(UNr ptr)
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
                    return (this._ptr & 1U) != 1U;
                }

                @system T* ptr() const @nogc nothrow
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
            ZNr ptrLength = ptrList.length;
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
        @system public void ptr(T* ptr)
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
            if (ptrNr < (4294967295UL << SHIFT_LEN))
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
            @system ~this()
            {
                this.clean;
            }
        }
        else
        {
            pragma(inline, true)
            @system ~this()
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
            @safe Bit compressed() const @nogc nothrow
            {
                return true;
            }
            
            @system T* ptr() const @nogc nothrow
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
            
            @system void ptr(const T* ptr) //@nogc nothrow
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
                    //PNr ptrNr = cast(PNr)ptr;
                    //printf("PNr = %d\n", ptrNr);
                    //PNr ptrNr = (cast(PNr)ptr << 16) >>> 16;
                    //assert(ptrNr < (4294967295UL << SHIFT_LEN)); //TODO: analyze alternative solutions
                    this._ptr = cast(UNr)((cast(PNr)ptr) >>> SHIFT_LEN);
                    //this._ptr = cast(UNr)(ptrNr >>> SHIFT_LEN);
                //}
            }
        }
        
        pragma(inline, true):
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
    }
    
    alias ptr this;
    pragma(inline, true):
    static if (own > 0)
    {
        @disable this(this);
        
        @system void copy(ref return scope CmpsPtr copy) //@nogc nothrow
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
       
    @system void copy(T* ptr)
    {
        static if (own > 0)
        {
            this.count = nil;
        }
        this.ptr = ptr;
    }

    @system this(T* ptr)
    {
        this.copy(ptr);
    }

    //static if (own == 0)
    //{
        @system void opAssign(T* ptr)
        {
            this.copy(ptr);
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

    @disable this();
}

pragma(inline, true)
{
    @system T* alloc(T)(const SNr qty = 1) @nogc nothrow
    {
        return cast(T*)malloc(T.sizeof * qty);
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
        ptr.free;
    }

    @system void erase(T, const Bit check = false)(CmpsPtr!T ptr) @nogc nothrow
    {
        ptr.ptr.erase!(T, check);
    }
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