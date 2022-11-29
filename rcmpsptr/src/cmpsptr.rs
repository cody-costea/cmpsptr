/*
Copyright (C) AD 2022 Claudiu-Stefan Costea

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/
pub mod cmpsptr {
    use std::vec::Vec;
    use std::marker::PhantomData;
    use lazy_static::lazy_static;
    use std::ops::{Deref, DerefMut};
    use std::ptr::copy_nonoverlapping;
    use std::sync::{Mutex, MutexGuard};
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::alloc::{alloc, dealloc, handle_alloc_error, Layout};

    lazy_static! {
        static ref _PTR_LIST: Mutex<Vec<usize>> = Mutex::new(vec![]);
    }

    static mut _GLOBAL_NEW_MASK: usize = usize::MAX;
    static mut _GLOBAL_MASK: usize = usize::MAX;
    static mut _NULL_IDX: usize = 0;

    #[inline(always)]
    fn listed(ptr: usize) -> bool {
        (ptr & 1) == 1
    }

    #[inline(always)]
    fn ptr_list() -> MutexGuard<'static, Vec<usize>> {
        _PTR_LIST.lock().unwrap_or_else(|e| {
            panic!("CANNOT UNWRAP POINTER LIST: {}", e);
        })
    }

    fn list_ptr<const LIST_ONLY: bool>(ptr: usize) -> u32 {
        unsafe {
            let mut mutex_list = ptr_list();
            let ptr_list = mutex_list.deref_mut();
            let mut list_len = ptr_list.len();
            for mut i in _NULL_IDX..list_len {
                if ptr_list[i] == 0 {
                    ptr_list[i] = ptr;
                    i += 1; _NULL_IDX = i;
                    if LIST_ONLY {
                        return i as u32;
                    }
                    return ((i << 1) | 1) as u32;
                }
            }
            list_len += 1;
            ptr_list.push(ptr);
            _NULL_IDX = list_len;
            if LIST_ONLY {
                list_len as u32
            } else {
                ((list_len << 1) | 1) as u32
            }
        }
    }

    fn unlist_ptr<const CMPS_LEVEL: i32>(ptr: u32) {
        if CMPS_LEVEL == 0 {
            ptr_list()[(ptr as usize) - 1] = 0;
        } else if CMPS_LEVEL > 0 {
            let p = ptr as usize;
            if listed(p) {
                ptr_list()[(p >> 1) - 1] = 0;
            }
        }
    }

    #[inline(always)]
    const fn cmps_level<const CMPS_LEVEL: i32>() -> u32 {
        if CMPS_LEVEL < 1 {
            CMPS_LEVEL.abs() as u32
        } else {
            (CMPS_LEVEL - 1) as u32
        }
    }

    #[inline(always)]
    fn check_global_mask<const CMPS_LEVEL: i32, const NEW_ALLOC: bool>(ptr: usize) -> u32 {
        if CMPS_LEVEL == 0 {
            list_ptr::<true>(ptr)
        } else if NEW_ALLOC {
            global_compress_new::<CMPS_LEVEL>(ptr)
        } else {
            global_compress::<CMPS_LEVEL>(ptr)
        }
    }
    
    macro_rules! compress {
        ($mask: ident, $ptr: ident) => {
            {
                let shift_bits = 32 + cmps_level::<CMPS_LEVEL>();
                unsafe {
                    if $mask == usize::MAX {
                        $mask = ($ptr >> shift_bits) << shift_bits;
                        ($ptr >> cmps_level::<CMPS_LEVEL>()) as u32
                    } else {
                        if $mask == ($ptr >> shift_bits) << shift_bits {
                            ($ptr >> cmps_level::<CMPS_LEVEL>()) as u32
                        } else {
                            if CMPS_LEVEL < 0 {
                                panic!("CANNOT COMPRESS POINTER {}!", $ptr)
                            } else {
                                list_ptr::<false>($ptr)
                            }
                        }
                    }
                }
            }
        }
    }

    fn global_compress_new<const CMPS_LEVEL: i32>(ptr: usize) -> u32 {
        compress!(_GLOBAL_NEW_MASK, ptr)
    }

    fn global_compress<const CMPS_LEVEL: i32>(ptr: usize) -> u32 {
        compress!(_GLOBAL_MASK, ptr)
    }
    
    #[inline(always)]
    fn apply_global_mask<const NEW_ALLOC: bool, const CMPS_LEVEL: i32>(ptr: usize) -> usize {
        unsafe {
            if CMPS_LEVEL == 0 {                
                ptr_list()[ptr - 1]
            } else if CMPS_LEVEL > 0 && listed(ptr) {
                ptr_list()[(ptr >> 1) - 1]
            } else if NEW_ALLOC {
                ptr | _GLOBAL_NEW_MASK
            } else {
                ptr | _GLOBAL_MASK
            }
        }
    }

    pub trait Counter {
        fn increase_count(&mut self) -> usize;
        fn decrease_count(&mut self) -> usize;
        fn current_count(&self) -> usize;
        fn reset_count(&mut self);
    }

    impl Counter for u32 {

        fn increase_count(&mut self) -> usize {
            let cnt = *self + 1;
            *self = cnt;
            cnt as usize
        }

        fn decrease_count(&mut self) -> usize {
            let cnt = *self - 1;
            *self = cnt;
            cnt as usize
        }

        fn current_count(&self) -> usize {
            *self as usize
        }

        fn reset_count(&mut self) {
            (*self) = 1;
        }
    }

    impl Counter for AtomicU32 {

        fn increase_count(&mut self) -> usize {
            (*self).fetch_add(1, Ordering::SeqCst) as usize
        }

        fn decrease_count(&mut self) -> usize {
            (*self).fetch_min(1, Ordering::SeqCst) as usize
        }

        fn current_count(&self) -> usize {
            self.load(Ordering::SeqCst) as usize
        }

        fn reset_count(&mut self) {
            (*self).store(1, Ordering::SeqCst);
        }
    }

    //#[derive(Copy, Clone)]
    pub struct CmpsPtr<'a, T: 'a, const CMPS_LEVEL: i32, const NEW_ALLOC: bool> {
        _phantom: PhantomData<&'a T>,
        _ptr: u32
    }

    impl<T, const CMPS_LEVEL: i32, const NEW_ALLOC: bool> CmpsPtr<'_, T, CMPS_LEVEL, NEW_ALLOC> {
        #[inline(always)]
        fn get_ptr(&self) -> usize {
            apply_global_mask::<NEW_ALLOC, CMPS_LEVEL>((self._ptr  as usize) << cmps_level::<CMPS_LEVEL>())
        }
        
        #[inline(always)]
        pub fn ptr(&self) -> &T {
            unsafe {
                &*(self.get_ptr() as *const T)
            }
        }

        #[inline(always)]
        pub fn ptr_mut(&self) -> &mut T {
            unsafe {
                &mut *(self.get_ptr() as *mut T)
            }
        }

        #[inline(always)]
        fn compress(ptr: &mut T) -> u32 {
            let p = (ptr as *mut T) as usize;
            check_global_mask::<CMPS_LEVEL, NEW_ALLOC>(p)
        }

        #[inline(always)]
        pub fn set_ptr(&mut self, ptr: &mut T) {
            self._ptr = CmpsPtr::<'_, T, CMPS_LEVEL, NEW_ALLOC>::compress(ptr);
        }

        fn new_alloc<'a>() -> CmpsPtr<'a, T, CMPS_LEVEL, NEW_ALLOC> {
            unsafe {
                let layout = Layout::new::<T>();
                let ptr = alloc(layout);
                if ptr.is_null() {
                    handle_alloc_error(layout);
                }
                CmpsPtr::<'a, T, CMPS_LEVEL, NEW_ALLOC>::new(&mut *(ptr as *mut T))
            }
        }

        #[inline(always)]
        pub fn new(ptr: &mut T) -> CmpsPtr<'_, T, CMPS_LEVEL, NEW_ALLOC> {
            if CMPS_LEVEL > 3 || CMPS_LEVEL < -3 {                
                panic!("A COMPRESSION LEVEL HIGHER THAN 3 IS NOT SUPPORTED!")
            }
            CmpsPtr::<'_, T, CMPS_LEVEL, NEW_ALLOC> {
                _ptr: CmpsPtr::<'_, T, CMPS_LEVEL, NEW_ALLOC>::compress(ptr),
                _phantom: PhantomData
            }
        }

        #[inline(always)]
        fn new_copy<'a>(ptr: u32) -> CmpsPtr<'a, T, CMPS_LEVEL, NEW_ALLOC> {
            CmpsPtr::<'a, T, CMPS_LEVEL, NEW_ALLOC> {
                _phantom: PhantomData,
                _ptr: ptr
            }
        }

    }

    impl<T, const CMPS_LEVEL: i32, const NEW_ALLOC: bool> Copy for CmpsPtr<'_, T, CMPS_LEVEL, NEW_ALLOC> {}

    impl<'a, T, const CMPS_LEVEL: i32, const NEW_ALLOC: bool> Clone for CmpsPtr<'a, T, CMPS_LEVEL, NEW_ALLOC> {
        #[inline(always)]
        fn clone(&self) -> CmpsPtr<'a, T, CMPS_LEVEL, NEW_ALLOC> {
            CmpsPtr::<'a, T, CMPS_LEVEL, NEW_ALLOC>::new_copy(self._ptr)
        }
    }

    impl<T, const CMPS_LEVEL: i32, const NEW_ALLOC: bool> Deref for CmpsPtr<'_, T, CMPS_LEVEL, NEW_ALLOC> {
        type Target = T;
        #[inline(always)]
        fn deref(&self) -> &Self::Target {
            self.ptr()
        }
    }

    impl<T, const CMPS_LEVEL: i32, const NEW_ALLOC: bool> DerefMut for CmpsPtr<'_, T, CMPS_LEVEL, NEW_ALLOC> {
        #[inline(always)]    
        fn deref_mut(&mut self) -> &mut Self::Target {
            self.ptr_mut()
        }
    }

    pub struct CmpsRef<'a, T: 'a, const CMPS_LEVEL: i32> {
        _ptr: CmpsPtr<'a, T, CMPS_LEVEL, false>
    }

    impl<'a, T, const CMPS_LEVEL: i32> CmpsRef<'a, T, CMPS_LEVEL> {
        #[inline(always)]    
        pub fn new(ptr: &'a mut T) -> CmpsRef<'_, T, CMPS_LEVEL> {
            CmpsRef::<'a, T, CMPS_LEVEL> {
                _ptr: CmpsPtr::<'a, T, CMPS_LEVEL, false>::new(ptr),
            }
        }

    }

    impl<'a, T, const CMPS_LEVEL: i32> Deref for CmpsRef<'a, T, CMPS_LEVEL> {
        type Target = CmpsPtr<'a, T, CMPS_LEVEL, false>;
        #[inline(always)]
        fn deref(&self) -> &Self::Target {
            &self._ptr
        }
    }

    impl<T, const CMPS_LEVEL: i32> DerefMut for CmpsRef<'_, T, CMPS_LEVEL> {
        #[inline(always)]
        fn deref_mut(&mut self) -> &mut Self::Target {
            &mut self._ptr
        }
    }

    pub struct CmpsUnq<'a, T: 'a, const CMPS_LEVEL: i32> {
        _ptr: CmpsPtr<'a, T, CMPS_LEVEL, true>
    }

    impl<'a, T, const CMPS_LEVEL: i32> CmpsUnq<'a, T, CMPS_LEVEL> {
        #[inline(always)]
        pub fn new() -> CmpsUnq<'a, T, CMPS_LEVEL> {
            CmpsUnq::<'a, T, CMPS_LEVEL> {
                _ptr: CmpsPtr::<'a, T, CMPS_LEVEL, true>::new_alloc(),
            }
        }

        #[inline(always)]
        pub fn ptr_mut(&self) -> &mut T {
            self._ptr.ptr_mut()
        }

        #[inline(always)]
        pub fn ptr(&self) -> &T {
            self._ptr.ptr()
        }

    }

    impl<T, const CMPS_LEVEL: i32> Deref for CmpsUnq<'_, T, CMPS_LEVEL> {
        type Target = T;
        #[inline(always)]
        fn deref(&self) -> &Self::Target {
            self.ptr()
        }
    }

    impl<T, const CMPS_LEVEL: i32> DerefMut for CmpsUnq<'_, T, CMPS_LEVEL> {
        #[inline(always)]
        fn deref_mut(&mut self) -> &mut Self::Target {
            self.ptr_mut()
        }
    }

    impl<T, const CMPS_LEVEL: i32> Drop for CmpsUnq<'_, T, CMPS_LEVEL> {
        #[inline(always)]
        fn drop(&mut self) {
            let layout = Layout::new::<T>();
            unsafe {
                unlist_ptr::<CMPS_LEVEL>(self._ptr._ptr);
                dealloc((self.ptr_mut() as *mut T) as *mut u8, layout);
            }
        }
    }

    pub struct CmpsCnt<'a, T: 'a, const COW: bool, const CMPS_LEVEL: i32> where T: Counter {
        _ptr: CmpsPtr<'a, T, CMPS_LEVEL, true>
    }

    impl<'a, T, const COW: bool, const CMPS_LEVEL: i32> CmpsCnt<'a, T, COW, CMPS_LEVEL> where T: Counter {

        pub fn new() -> CmpsCnt<'a, T, COW, CMPS_LEVEL> {
            let mut rfc = CmpsPtr::<'a, T, CMPS_LEVEL, true>::new_alloc();
            rfc.reset_count();
            CmpsCnt::<'a, T, COW, CMPS_LEVEL> {
                _ptr: rfc
            }
        }

        pub fn detach(&mut self) {
            if self.current_count() > 1 {
                let mut ptr = CmpsPtr::<'a, T, CMPS_LEVEL, true>::new_alloc();
                let layout = Layout::new::<T>();
                unsafe {
                    copy_nonoverlapping(self._ptr.ptr_mut() as *mut T, ptr.ptr_mut() as *mut T, layout.size());
                }
                ptr.reset_count();
                self.decrease_count();
                self._ptr = ptr;
            }
        }

        #[inline(always)]
        pub fn ptr_mut(&mut self) -> &mut T {
            if COW {
                self.detach();
            }
            self._ptr.ptr_mut()
        }

        #[inline(always)]
        pub fn ptr(&self) -> &T {
            self._ptr.ptr()
        }

    }

    impl<T, const COW: bool, const CMPS_LEVEL: i32> Deref for CmpsCnt<'_, T, COW, CMPS_LEVEL> where T: Counter {
        type Target = T;
        #[inline(always)]
        fn deref(&self) -> &Self::Target {
            self.ptr()
        }
    }

    impl<T, const COW: bool, const CMPS_LEVEL: i32> DerefMut for CmpsCnt<'_, T, COW, CMPS_LEVEL> where T: Counter {
        #[inline(always)]
        fn deref_mut(&mut self) -> &mut Self::Target {
            self.ptr_mut()
        }
    }

    impl<T, const COW: bool, const CMPS_LEVEL: i32> Drop for CmpsCnt<'_, T, COW, CMPS_LEVEL> where T: Counter {
        #[inline(always)]
        fn drop(&mut self) {
            if self.decrease_count() == 0 {
                let obj_layout = Layout::new::<T>();
                unsafe {
                    unlist_ptr::<CMPS_LEVEL>(self._ptr._ptr);
                    dealloc((self.ptr_mut() as *mut T) as *mut u8, obj_layout);
                }
            }
        }
    }

    impl<'a, T, const COW: bool, const CMPS_LEVEL: i32> Clone for CmpsCnt<'a, T, COW, CMPS_LEVEL> where T: Counter {
        #[inline(always)]
        fn clone(&self) -> CmpsCnt<'a, T, COW, CMPS_LEVEL> {
            unsafe {
                (*((self as *const Self) as *mut Self)).increase_count();
            }
            CmpsCnt::<'a, T, COW, CMPS_LEVEL> {
                _ptr: self._ptr
            }
        }
    }

    pub struct CmpsShr<'a, T: 'a, C: 'a, const COW: bool, const CMPS_LEVEL: i32> where C: Counter {
        _ptr: CmpsPtr<'a, T, CMPS_LEVEL, true>,
        _rfc: CmpsPtr<'a, C, 3, true>
    }

    impl<'a, T, C, const COW: bool, const CMPS_LEVEL: i32> CmpsShr<'a, T, C, COW, CMPS_LEVEL> where C: Counter {

        pub fn new() -> CmpsShr<'a, T, C, COW, CMPS_LEVEL> {
            let mut rfc = CmpsPtr::<'a, C, 3, true>::new_alloc();
            rfc.reset_count();
            CmpsShr::<'a, T, C, COW, CMPS_LEVEL> {
                _ptr: CmpsPtr::<'a, T, CMPS_LEVEL, true>::new_alloc(),
                _rfc: rfc
            }
        }

        pub fn detach(&mut self) {
            if self._rfc.current_count() > 1 {
                let ptr = CmpsPtr::<'a, T, CMPS_LEVEL, true>::new_alloc();
                let layout = Layout::new::<T>();
                unsafe {
                    copy_nonoverlapping(self._ptr.ptr_mut() as *mut T, ptr.ptr_mut() as *mut T, layout.size());
                }
                self._ptr = ptr;
                self._rfc.decrease_count();
                let mut rfc = CmpsPtr::<'a, C, 3, true>::new_alloc();
                rfc.reset_count();
                self._rfc = rfc;
            }
        }

        #[inline(always)]
        pub fn ptr_mut(&mut self) -> &mut T {
            if COW {
                self.detach();
            }
            self._ptr.ptr_mut()
        }

        #[inline(always)]
        pub fn ptr(&self) -> &T {
            self._ptr.ptr()
        }

    }

    impl<T, C, const COW: bool, const CMPS_LEVEL: i32> Deref for CmpsShr<'_, T, C, COW, CMPS_LEVEL> where C: Counter {
        type Target = T;
        #[inline(always)]
        fn deref(&self) -> &Self::Target {
            self.ptr()
        }
    }

    impl<T, C, const COW: bool, const CMPS_LEVEL: i32> DerefMut for CmpsShr<'_, T, C, COW, CMPS_LEVEL> where C: Counter {
        #[inline(always)]
        fn deref_mut(&mut self) -> &mut Self::Target {
            self.ptr_mut()
        }
    }

    impl<T, C, const COW: bool, const CMPS_LEVEL: i32> Drop for CmpsShr<'_, T, C, COW, CMPS_LEVEL> where C: Counter {
        #[inline(always)]
        fn drop(&mut self) {
            if self._rfc.decrease_count() == 0 {
                let obj_layout = Layout::new::<T>();
                let cnt_layout = Layout::new::<u32>();
                unsafe {                    
                    unlist_ptr::<CMPS_LEVEL>(self._ptr._ptr);
                    dealloc((self.ptr_mut() as *mut T) as *mut u8, obj_layout);
                    dealloc((self._rfc.ptr_mut() as *mut C) as *mut u8, cnt_layout);
                }
            }
        }
    }

    impl<'a, T, C, const COW: bool, const CMPS_LEVEL: i32> Clone for CmpsShr<'a, T, C, COW, CMPS_LEVEL> where C: Counter {
        #[inline(always)]
        fn clone(&self) -> CmpsShr<'a, T, C, COW, CMPS_LEVEL> {
            unsafe {
                (*((self as *const Self) as *mut Self))._rfc.increase_count();
            }
            CmpsShr::<'a, T, C, COW, CMPS_LEVEL> {
                _ptr: self._ptr,
                _rfc: self._rfc
            }
        }
    }

}